#!/bin/sh

set -eux

./test.sh

#docker buildx build --platform linux/amd64 --push \
docker buildx use k8s
time docker buildx build --platform linux/amd64,linux/arm64 --push \
  --cache-from=type=registry,ref=harbor.gladiators.dev/library/trade-cache:buildcache \
  --cache-to=type=registry,ref=harbor.gladiators.dev/library/trade-cache:buildcache,image-manifest=true \
  --progress=plain \
  -t harbor.gladiators.dev/library/trade-cache:latest .
