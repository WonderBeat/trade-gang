#!/bin/bash

set -eux -o pipefail

PLATFORM=$1
OUTPUT=$2

if [ "$PLATFORM" = "linux/amd64" ]; then
  zig build --release=fast -Dbackend=epoll -Dtarget=x86_64-linux -Dcpu=x86_64+avx+pclmul --maxrss 119430400 -p "$OUTPUT"
elif [ "$PLATFORM" = "linux/arm64" ]; then
  zig build --release=fast -Dbackend=epoll -Dtarget=aarch64-linux --maxrss 119430400 -p "$OUTPUT"
else
  echo "Unsupported architecture"
  exit 1
fi
