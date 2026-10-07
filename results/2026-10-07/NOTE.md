# Notes on 2026-10-07

The second measurement day: `bin/run-all.sh` and `bin/cdn-jetpack.sh` on an
arm64 Mac (here), and the x86 workflow on GitHub (`../2026-10-07-x86/`, run
37577779179). WordPress was 7.1.3 today, 7.1.2 on 2026-10-06.

Compared with 2026-10-06:

- Jetpack's CDN (`jetpack-cdn.txt`): every row the same.
- x86 (`../2026-10-07-x86/SUMMARY.md`): every row the same.
- arm64 (`SUMMARY.md`): every row the same except one, EWWW Image
  Optimizer 8.8.0 with the OpenAI PNG.

## EWWW and the PNG on arm64

On 2026-10-06 EWWW left the PNG as it was (2,210,928 bytes, C2PA `Valid`).
Today it rewrote it (2,128,496 bytes) without its C2PA chunk, and every
sub-size came out a few hundred bytes smaller.

The cause is the optipng EWWW finds. EWWW ships its own tools for x86 only,
so on arm64 it can only use a system optipng. `bin/prepare.sh` installs
Debian's, which is 0.7.8 in today's container. EWWW 8.8.0 passes
`-strip all` when optipng's version matches 0.7, and that removes the chunk
(nosilver4u/ewww-image-optimizer issue 389).

Checked by removing the system optipng from the container and measuring EWWW
with the PNG once more (`ewww-without-system-optipng/`): the PNG kept its
C2PA (`Valid`, 2,210,928 bytes) and every file had the same size as on
2026-10-06. So on 2026-10-06 the arm64 run had no optipng in the container;
why is not known (most likely the container was rebuilt after
`bin/prepare.sh`). That row of `../2026-10-06/SUMMARY.md` measures EWWW
without a PNG tool, not EWWW as a server with optipng installed runs it.

What EWWW 8.8.0 does to a signed PNG therefore depends on the optipng it uses:

| optipng | where | result |
|---|---|---|
| EWWW's own | x86 | chunk kept, pixels recompressed: `Invalid`, `assertion.dataHash.mismatch` |
| system 0.7.x | e.g. Debian/Ubuntu with optipng installed | chunk removed: no C2PA |
| none | arm64 without optipng | PNG untouched: `Valid` |
