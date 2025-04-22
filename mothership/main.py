#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["ipython", "websockets", "loguru", "protobuf==5.29.4", "cloudscraper", "aiohttp"]
# ///
from loguru import logger
import os
import asyncio

if __name__ == "__main__":
    if os.environ.get("RELAY", None):
        from relay import relay

        asyncio.run(relay())
    if os.environ.get("CLOUDFLARE", None):
        from cloudflare import cloudflare

        asyncio.run(cloudflare())
