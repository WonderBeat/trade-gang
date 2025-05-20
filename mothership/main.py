#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["prometheus_client",  "ipython", "websockets", "loguru", "protobuf==5.29.4", "cloudscraper", "aiohttp", "dnspython", "requests[socks]"]
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
    if os.environ.get("PROXY_LIST", None):
        from proxy_catcher import server

        server()
