#!/bin/sh
set -eu
dir=$(dirname "$0")/crinkler
url=https://github.com/runestubbe/Crinkler/releases/download/v3.0b/crinkler30b.zip
sum=14017536cf7bbc908f607260d5be30f56d8df182a0fd8fcead750e771f40888a
[ -f "$dir/Crinkler.exe" ] && exit 0
mkdir -p "$dir"
curl -sL "$url" -o "$dir/crinkler.zip"
echo "$sum  $dir/crinkler.zip" | sha256sum -c -
python3 -I -c 'import sys,zipfile; z=zipfile.ZipFile(sys.argv[1]); open(sys.argv[2],"wb").write(z.read("crinkler30b/Win32/Crinkler.exe"))' "$dir/crinkler.zip" "$dir/Crinkler.exe"
rm "$dir/crinkler.zip"
