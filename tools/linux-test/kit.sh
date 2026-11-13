#!/bin/bash
[ $# -ge 1 ] || { echo "usage: kit.sh ROUND [BASE]    (BASE for ab.txt: a git rev, default the last commit that changed src/game.glsl; JOBS renders at once, default 4)"; exit 1; }
S=$(cd "$(dirname "$0")" && pwd); R=$(git -C "$S" rev-parse --show-toplevel)
K=$R/build/review/r$1; T=$R/build/review/work; JOBS=${JOBS:-4}
case $JOBS in '' | *[!0-9]* | 0) echo "JOBS must be a positive integer"; exit 1 ;; esac
mkdir -p $K $T && rm -f $K/*
(cd $R && nice make --no-print-directory linux windows > $T/make.log 2>&1) &
start() { while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n; done; "$@" > /dev/null 2>&1 & }
shot() { $S/shot.sh "$@"; }
listen() { $S/shot.sh $T/$1 $2 0 0 1 "$3" && python3 $R/tools/audio_report.py $T/$1/audio.wav $4 > $T/$1/stats.txt; }
start env JOBS=2 python3 $S/scenarios.py --report $R/build/scenarios.txt
start listen sound 4200 "BOT SOUNDTEST" --soundtest
start listen play 3600 "BOT LEVEL=1.0"
for L in 1 3 5 6; do start shot $T/l$L 3600 300 300 0 "BOT LEVEL=$L.0"; done
start shot $T/stand 1800 0 0 0 "BOT STAND LEVEL=2.0"
start shot $T/tour 330 20 19 0 "BOT TOUR LEVEL=2.0"
start shot $T/sc 60 59 0 0 "BOT SHOWCASE"
start shot $T/end 40 39 0 0 "BOT ENDING"
for G in 0 1 2 3; do start shot $T/gun$G 40 39 0 0 "BOT SHOWCASE GUN=$G.0"; done
for C in 0 1 2 3; do start shot $T/cu$C 46 45 0 0 "BOT SHOWCASE CLOSE=$C.0"; done
wait
for L in 1 3 5 6; do
  cp $T/l$L/sheet.png $K/level$L-sheet.png
  cp $T/l$L/f1800.png $K/level$L-f1800.png
  grep "^frame" $T/l$L/log.txt > $K/level$L-bot.log
done
cp $T/sc/f0059.png $K/showcase.png
cp $T/end/f0039.png $K/ending.png
for G in 0 1 2 3; do cp $T/gun$G/f0039.png $K/gun$G.png; done
for C in 0 1 2 3; do cp $T/cu$C/f0045.png $K/closeup$C.png; done
cp $T/tour/sheet.png $K/tour-level2-sheet.png
cp $T/sound/audio.wav $K/soundtest.wav && cp $T/sound/stats.txt $K/soundtest-stats.txt
cp $T/play/audio.wav $K/gameplay-level1.wav && cp $T/play/stats.txt $K/gameplay-stats.txt
grep "^frame" $T/stand/log.txt > $K/standing-level2.log
BASE=${2:-$(git -C $R diff --quiet HEAD -- src/game.glsl && git -C $R log -2 --format=%h -- src/game.glsl | tail -1 || echo HEAD)}
$R/tools/ab.sh "$BASE" $R/src/game.glsl > $K/ab.txt 2>&1
(cd $R && make --no-print-directory check) > $K/check.txt 2>&1
cp $R/sizes.txt $K/sizes.txt; cp $R/build/scenarios.txt $K/scenarios.txt
grep -E "^(ok|FAIL)" $K/check.txt
ls $K
