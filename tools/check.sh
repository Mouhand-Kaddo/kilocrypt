#!/bin/bash
R=$(cd "$(dirname "$0")/.." && pwd); B=${1:-build}
cd "$R" || exit 1
lin=$(stat -c %s "$B/kilocrypt" 2>/dev/null); win=$(stat -c %s "$B/kilocrypt.exe" 2>/dev/null)
{ [ -n "$lin" ] && echo "linux $lin"; [ -n "$win" ] && echo "windows $win"; } > sizes.txt
old=$(git show HEAD:sizes.txt 2>/dev/null)
fail=0
for p in linux windows; do
    new=$(awk -v p=$p '$1 == p { print $2 }' sizes.txt)
    prev=$(echo "$old" | awk -v p=$p '$1 == p { print $2 }')
    if [ -z "$new" ]; then echo "FAIL $p: no packed size in sizes.txt (build failed?)"; fail=1; continue; fi
    change=${prev:+, $((new - prev)) B since the last commit}
    if [ "$new" -gt 16384 ]; then echo "FAIL $p: $new B is over 16384 B$change"; fail=1; else echo "ok   $p: $new B, $((16384 - new)) B left$change"; fi
done
python3 tools/linux-test/scenarios.py --report "$B/scenarios.txt" || fail=1
exit $fail
