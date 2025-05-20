#!/bin/bash

set -eux -o pipefail

PLATFORM=$1
OUTPUT=$2

if [ "$PLATFORM" = "linux/amd64" ]; then # zig 0.13 bug in cpu detection https://github.com/ziglang/zig/issues/21925
  zig build --search-prefix /usr/lib/ --search-prefix /usr/lib/x86_64-linux-gnu --release=fast -Dtarget=x86_64-linux --maxrss 119430400 -p "$OUTPUT"
elif [ "$PLATFORM" = "linux/arm64" ]; then
  zig build --search-prefix /usr/lib/ --search-prefix /usr/lib/aarch64-linux-gnu --release=fast -Dtarget=aarch64-linux --maxrss 119430400 -p "$OUTPUT"
else
  echo "Unsupported architecture"
  exit 1
fi
rm -rf .zig-cache # avoid caching via buildx cache
