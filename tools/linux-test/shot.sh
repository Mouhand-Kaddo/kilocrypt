#!/bin/bash
[ $# -ge 6 ] || { echo "usage: shot.sh OUTDIR FRAMES EVERY FROM AUDIO \"DEFINES\" [glsl]"; exit 1; }
S=$(cd "$(dirname "$0")" && pwd); R=$(git -C "$S" rev-parse --show-toplevel)
OUT=$1; FR=$2; EV=$3; FROM=$4; AU=$5; DEF=$6; SRC=${7:-$R/src/game.glsl}
BIN=$R/build/linux-shot
if [ ! -x $BIN ] || [ $S/shot.c -nt $BIN ]; then
  mkdir -p $R/build && cc -O2 $S/shot.c -o $BIN.$$ -lEGL && mv $BIN.$$ $BIN || exit 1
fi
mkdir -p $OUT && rm -f $OUT/*
if [ -n "$RAW" ]; then cp $SRC $OUT/shader.glsl; else python3 $R/tools/minify_glsl.py $SRC $OUT/shader.h $OUT/shader.glsl >/dev/null || exit 1; fi
timeout ${TIMEOUT:-300} nice $BIN $OUT/shader.glsl $OUT $FR $EV $FROM $AU "$DEF" > $OUT/log.txt 2>&1
echo "exit $?" >> $OUT/log.txt
grep -v "^frame" $OUT/log.txt | head -40
grep "^frame" $OUT/log.txt | tail -3
python3 $S/sheet.py $OUT
