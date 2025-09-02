#!/bin/sh

set -eux

./test.sh

docker buildx build --platform linux/amd64,linux/arm64 --push \
  --cache-from=type=registry,ref=harbor.gladiators.dev/library/mothership:buildcache \
  --cache-to=type=registry,ref=harbor.gladiators.dev/library/mothership:buildcache,image-manifest=true \
  --progress=plain \
  -t harbor.gladiators.dev/library/mothership:latest .
