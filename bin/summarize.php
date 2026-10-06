<?php
// results/<date> -> a Markdown table: per configuration and image, what happened
// to the signed original and what a visitor is served.
$dir = rtrim($argv[1] ?? '', '/');
$rows = [];
foreach (glob("$dir/*/*/config.txt") as $config) {
    $run = dirname($config);
    [$label, $image] = array_slice(explode('/', $run), -2);
    $cfg = file_get_contents($config);
    preg_match('/^plugin: (.*)$/m', $cfg, $p);
    preg_match('/^fixture: (\S+)/m', $cfg, $f);
    $base = pathinfo($f[1], PATHINFO_FILENAME);
    $ext = pathinfo($f[1], PATHINFO_EXTENSION);
    $lines = array_slice(file("$run/files.txt", FILE_IGNORE_NEW_LINES), 1);
    $original = '?'; $kept = []; $derivatives = 0; $derivativesWith = 0;
    foreach ($lines as $l) {
        $c = preg_split('/\s+/', trim($l));
        $name = basename($c[0]);
        if (preg_match('/^'.preg_quote($base, '/').'(-\d+)?\.'.$ext.'$/', $name)) {
            $original = ($c[3] === 'yes' ? 'C2PA '.$c[4] : 'no C2PA').' ('.$c[1].' B)';
        } elseif (preg_match('/-\d+x\d+\.|-scaled\./', $name)) {
            $derivatives++; $derivativesWith += $c[3] === 'yes' ? 1 : 0;
        } elseif ($c[3] === 'yes') {
            $kept[] = $name.' ('.$c[4].')';
        }
    }
    $served = [];
    foreach (array_slice(file("$run/served.txt", FILE_IGNORE_NEW_LINES), 1) as $l) {
        $c = preg_split('/\s+/', trim($l));
        $key = $c[2].' '.($c[3] === 'yes' ? 'C2PA '.$c[4].($c[5] !== '-' ? ' '.$c[5] : '') : 'no C2PA');
        $served[$key] = ($served[$key] ?? 0) + 1;
    }
    $rows[] = sprintf('| %s | %s | %s | %s | %d of %d | %s | %s |', $label, trim($p[1]), $image, $original, $derivativesWith, $derivatives,
        $kept === [] ? '—' : implode(', ', $kept),
        implode('; ', array_map(fn ($k, $n) => "{$n}× {$k}", array_keys($served), $served)) ?: '—');
}
echo "# Results ", basename($dir), "\n\n";
echo "| config | plugin | image | upload as stored | sizes with C2PA | other files with C2PA | served to a visitor |\n|---|---|---|---|---|---|---|\n";
echo implode("\n", $rows), "\n";
