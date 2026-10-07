<?php

declare(strict_types=1);

/*
 * Quick scan: the images a visitor gets from one public page, each through
 * c2pa-verifier. Usage: php scan.php <page-url> [max-images=30]
 * Fetches only public URLs, one at a time, with a size and time limit.
 */

require __DIR__.'/../vendor/autoload.php';

use Provemark\C2paVerifier\Verifier\Verifier;

const UA = 'provemark-quickscan/0.1 (C2PA research; one request per image)';
const MAX_BYTES = 20 * 1024 * 1024;

function fetch(string $url, int $max = MAX_BYTES): ?array
{
    $ch = curl_init($url);
    $body = '';
    curl_setopt_array($ch, [
        CURLOPT_FOLLOWLOCATION => true, CURLOPT_MAXREDIRS => 5, CURLOPT_TIMEOUT => 30,
        CURLOPT_USERAGENT => UA, CURLOPT_ENCODING => '',
        CURLOPT_HTTPHEADER => ['Accept: image/avif,image/webp,image/*,text/html;q=0.9,*/*;q=0.8'],
        CURLOPT_WRITEFUNCTION => static function ($ch, string $chunk) use (&$body, $max): int {
            $body .= $chunk;

            return strlen($body) > $max ? 0 : strlen($chunk);
        },
    ]);
    $ok = curl_exec($ch);
    $info = curl_getinfo($ch);
    if ($ok === false || ($info['http_code'] ?? 0) >= 400) {
        return null;
    }

    return ['body' => $body, 'type' => (string) ($info['content_type'] ?? ''), 'url' => (string) ($info['url'] ?? $url)];
}

function absolute(string $base, string $ref): ?string
{
    $ref = html_entity_decode(trim($ref));
    if ($ref === '' || str_starts_with($ref, 'data:')) {
        return null;
    }
    if (preg_match('#^https?://#i', $ref)) {
        return $ref;
    }
    $p = parse_url($base);
    $root = ($p['scheme'] ?? 'https').'://'.($p['host'] ?? '').(isset($p['port']) ? ':'.$p['port'] : '');
    if (str_starts_with($ref, '//')) {
        return ($p['scheme'] ?? 'https').':'.$ref;
    }
    if (str_starts_with($ref, '/')) {
        return $root.$ref;
    }
    $dir = preg_replace('#/[^/]*$#', '/', $p['path'] ?? '/');

    return $root.$dir.$ref;
}

/** Image URLs of a page: img src, srcset (largest), picture sources, og:image. */
function imageUrls(string $html, string $base): array
{
    $urls = [];
    preg_match_all('#<meta[^>]+(?:property|name)=["\'](?:og:image|twitter:image)["\'][^>]*content=["\']([^"\']+)#i', $html, $m);
    $urls = array_merge($urls, $m[1]);
    preg_match_all('#<img[^>]*?\s(?:data-src|src)=["\']([^"\']+)#i', $html, $m);
    $urls = array_merge($urls, $m[1]);
    preg_match_all('#\s(?:data-srcset|srcset)=["\']([^"\']+)#i', $html, $m);
    foreach ($m[1] as $set) {
        $best = null;
        $bestW = -1;
        foreach (explode(',', $set) as $part) {
            $bits = preg_split('/\s+/', trim($part));
            $w = isset($bits[1]) ? (int) $bits[1] : 0;
            if ($w > $bestW) {
                [$best, $bestW] = [$bits[0], $w];
            }
        }
        if ($best !== null) {
            $urls[] = $best;
        }
    }
    $out = [];
    foreach ($urls as $u) {
        $a = absolute($base, $u);
        if ($a !== null && ! preg_match('#\.(svg|ico)(\?|$)#i', $a)) {
            $out[$a] = true;
        }
    }

    return array_keys($out);
}

$page = $argv[1] ?? '';
$max = (int) ($argv[2] ?? 30);
$got = fetch($page, 5 * 1024 * 1024);
if ($got === null) {
    fwrite(STDERR, "cannot fetch $page\n");
    exit(1);
}
$urls = array_slice(imageUrls($got['body'], $got['url']), 0, $max);
$verifier = new Verifier;
$rows = [];
foreach ($urls as $u) {
    $img = fetch($u);
    if ($img === null) {
        $rows[] = ['url' => $u, 'error' => 'fetch failed'];

        continue;
    }
    $s = fopen('php://memory', 'w+b');
    fwrite($s, $img['body']);
    rewind($s);
    try {
        $r = $verifier->verify($s)->toArray();
        $rows[] = [
            'url' => $u, 'bytes' => strlen($img['body']), 'type' => $img['type'], 'format' => $r['format'] ?? '?',
            'manifest' => $r['has_manifest'] ?? false, 'state' => ($r['has_manifest'] ?? false) ? ($r['validation_state'] ?? '?') : '-',
            'signer' => (static function (array $r): ?string { $m = $r['manifests'][$r['active_manifest'] ?? ''] ?? []; $si = $m['signature_info'] ?? []; return isset($si['common_name']) ? $si['common_name'].' / '.($si['issuer'] ?? '?') : null; })($r),
            'failures' => array_values(array_unique(array_map(static fn (array $f): string => (string) $f['code'], $r['validation_results']['activeManifest']['failure'] ?? []))),
        ];
    } catch (Throwable $e) {
        $rows[] = ['url' => $u, 'error' => get_class($e).': '.$e->getMessage()];
    }
    fclose($s);
    usleep(300000);
}
$with = count(array_filter($rows, static fn (array $r): bool => ($r['manifest'] ?? false) === true));
printf("%s\n%d images, %d with a manifest\n", $got['url'], count($rows), $with);
foreach ($rows as $r) {
    $name = strlen($r['url']) > 90 ? '…'.substr($r['url'], -89) : $r['url'];
    if (isset($r['error'])) {
        printf("  ERR  %s  %s\n", $name, $r['error']);
    } else {
        printf("  %-5s %-8s %-8s %7d  %s%s%s\n", $r['format'], $r['manifest'] ? 'C2PA' : '-', $r['state'], $r['bytes'], $name,
            $r['signer'] ? '  signer: '.$r['signer'] : '', $r['failures'] ? '  ['.implode(',', $r['failures']).']' : '');
    }
}
file_put_contents(__DIR__.'/'.preg_replace('/[^a-z0-9]+/i', '-', parse_url($got['url'], PHP_URL_HOST) ?? 'page').'.json', json_encode($rows, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
