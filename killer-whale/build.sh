#!/bin/sh

set -eux -o pipefail

PLATFORM=$1
OUTPUT=$2

if [ "$PLATFORM" = "linux/amd64" ]; then # zig 0.13 bug in cpu detection https://github.com/ziglang/zig/issues/21925
  zig build --release=small -Dtarget=x86_64-linux -p "$OUTPUT"
elif [ "$PLATFORM" = "linux/arm64" ]; then
  zig build --release=small -Dtarget=aarch64-linux -p "$OUTPUT"
else
  echo "Unsupported architecture"
  exit 1
fi
