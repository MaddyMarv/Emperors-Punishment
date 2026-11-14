#!/bin/sh
cd "$(dirname "$0")" || exit 1
mkdir -p ../bin
"${ZIG:-zig}" cc -target x86_64-windows-gnu -shared -O2 -s -o ../bin/ps_native.dll ps_native.c -lwinhttp
rm -f ../bin/ps_native.lib ../bin/ps_native.pdb
