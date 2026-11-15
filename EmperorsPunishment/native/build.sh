#!/bin/sh
cd "$(dirname "$0")" || exit 1
mkdir -p ../bin
"${ZIG:-zig}" cc -target x86_64-windows-gnu -shared -O2 -s -o ../bin/ep_native.dll ep_native.c -lwinhttp
rm -f ../bin/ep_native.lib ../bin/ep_native.pdb
