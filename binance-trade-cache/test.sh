#!/bin/sh

set -eux

zig build test
zig build --release=fast
