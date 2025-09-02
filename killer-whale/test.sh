#!/bin/sh

set -eux

zig build test
zig build test -Dapp=upbit
zig build --release=fast
zig build -Dapp=upbit --release=fast
