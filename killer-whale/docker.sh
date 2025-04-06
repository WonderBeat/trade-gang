#!/bin/sh

set -eux

#docker buildx build --platform linux/amd64 --push \
docker buildx build --platform linux/amd64,linux/arm64 --push \
  --cache-from=type=registry,ref=harbor.gladiators.dev/library/b-crawl:buildcache \
  --cache-to=type=registry,ref=harbor.gladiators.dev/library/b-crawl:buildcache,image-manifest=true \
  --progress=plain \
  -t harbor.gladiators.dev/library/b-crawl:latest .
