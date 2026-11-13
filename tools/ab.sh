#!/bin/bash
[ $# -eq 2 ] || { echo "usage: ab.sh BASE VARIANT    (each a git rev or a .glsl path; WIN=1 adds Windows sizes, ROUNDS and FRAMES tune the timing, SERIAL=1 builds and renders one at a time)"; exit 1; }
S=$(cd "$(dirname "$0")" && pwd); R=$(git -C "$S" rev-parse --show-toplevel); cd "$R" || exit 1
O=build/ab; ROUNDS=${ROUNDS:-3}; FRAMES=${FRAMES:-300}; T=tools/linux-test
rm -rf $O && mkdir -p $O/a $O/b
for v in a b; do
    src=$([ $v = a ] && echo "$1" || echo "$2")
    if [ -f "$src" ]; then cp "$src" $O/$v/game.glsl
    elif ! git show "$src:src/game.glsl" > $O/$v/game.glsl 2>/dev/null; then echo "$src: not a file or a git rev with src/game.glsl"; exit 1; fi
done
targets=linux
if [ -n "$WIN" ]; then
    targets="linux windows"
    main=$(git worktree list --porcelain | awk 'NR == 1 { print $2 }')
    [ -e tools/crinkler ] || [ ! -e "$main/tools/crinkler" ] || ln -s "$main/tools/crinkler" tools/crinkler
fi
bg() { if [ -n "$SERIAL" ]; then "$@"; else "$@" & fi; }
build() { LINT=$([ $1 = a ] && echo warn) make --no-print-directory BUILD=$O/$1/build SHADER=$O/$1/game.glsl PACK_FLAGS="--search 0" CRINKLE_MODE=/COMPMODE:FAST $targets > $O/$1/make.log 2>&1; }
for v in a b; do bg build $v; done
wait
for v in a b; do [ -s $O/$v/build/kilocrypt ] || { echo "build failed"; tail -n 5 $O/$v/make.log; exit 1; }; done
size() { stat -c %s $O/$1/build/$2 2>/dev/null; }
row() { [ -n "$2" ] && [ -n "$3" ] && printf "  %-34s %6s -> %6s  (%+d B)\n" "$1" "$2" "$3" $(($3 - $2)); }
echo "Size:"
row "minified release shader" "$(size a shader.min.glsl)" "$(size b shader.min.glsl)"
row "Linux packed (--search 0)" "$(size a kilocrypt)" "$(size b kilocrypt)"
[ -n "$WIN" ] && row "Windows packed (Crinkler FAST)" "$(size a kilocrypt.exe)" "$(size b kilocrypt.exe)"

scene() { [ $1 = dark ] && echo "BOT LEVEL=3.0" || echo "BOT TOUR LEVEL=2.0"; }
for k in $(seq "$ROUNDS"); do
    for s in dark lit; do
        for v in a b; do TIMING=1 SIZE=2560x1440 $T/shot.sh $O/$v/$s$k "$FRAMES" 0 0 0 "$(scene $s)" $O/$v/game.glsl > /dev/null 2>&1; done
    done
done
median() { for k in $(seq "$ROUNDS"); do awk -v f="$3" '/^avg game us/ { print $f }' $O/$1/$2$k/log.txt; done | sort -n | awk '{ a[NR] = $1 } END { print a[int((NR + 1) / 2)] }'; }
echo "GPU time per frame at 2560x1440, $FRAMES frames, median of $ROUNDS interleaved runs (dark: BOT LEVEL=3.0, 0 fuses; lit: BOT TOUR LEVEL=2.0, 3 fuses; compute differences under 10% are noise):"
for s in dark lit; do
    for f in "compute 4" "fragment 7"; do
        set -- $f; a=$(median a $s $2); b=$(median b $s $2)
        [ -n "$a" ] && [ -n "$b" ] && awk -v n="$s $1" -v a="$a" -v b="$b" 'BEGIN { printf "  %-34s %6d -> %6d us  (%+.1f%%)\n", n, a, b, (b - a) * 100 / a }'
    done
done

for v in a b; do
    bg $T/shot.sh $O/$v/level 601 600 600 0 "BOT LEVEL=3.0" $O/$v/game.glsl > /dev/null 2>&1
    bg $T/shot.sh $O/$v/showcase 60 59 59 0 "BOT SHOWCASE" $O/$v/game.glsl > /dev/null 2>&1
done
wait
echo "Pixels (diff images in $O/):"
printf "  floor 3 bot frame 600: "; python3 $T/pixdiff.py $O/a/level/f0600.png $O/b/level/f0600.png $O/diff-level3.png
printf "  showcase frame 59:     "; python3 $T/pixdiff.py $O/a/showcase/f0059.png $O/b/showcase/f0059.png $O/diff-showcase.png

for v in a b; do
    MESA_SHADER_CACHE_DISABLE=true AMD_DEBUG=cs,ps,stats RAW=1 SIZE=320x180 $T/shot.sh $O/$v/stats 1 0 0 0 "" $O/$v/build/shader.min.glsl > /dev/null 2>&1
    grep "^Shader Stats" $O/$v/stats/log.txt | awk '
        function get(key) { return match($0, key " [0-9]+") ? substr($0, RSTART + length(key) + 1, RLENGTH - length(key) - 1) : "?" }
        get("Code Size:") + 0 > 1000 { match($0, /\((CS|PS)/); print substr($0, RSTART + 1, 2), get("VGPRS:"), get("SGPRS:"), get("Code Size:"), get("Max Waves:"), get("Spilled VGPRs:"), get("PrivMem VGPRs:"), get("Scratch:") }' > $O/$v/stats.txt
done
echo "radeonsi stats of the release shaders (VGPRs, SGPRs, code bytes, max waves, spilled VGPRs, private-memory VGPRs, scratch bytes):"
join <(sort $O/a/stats.txt) <(sort $O/b/stats.txt) | awk '{ printf "  %s  %s %s %s %s %s %s %s  ->  %s %s %s %s %s %s %s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15
    if ($11 > $4 * 1.05) printf "  WARNING: %s code grew %.0f%%; check for a loop the compiler unrolled (a loop indexing an array from a constant start is bounded by the array size, so put dynamicZero in its start)\n", $1, ($11 - $4) * 100 / $4 }'
