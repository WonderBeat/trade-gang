#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["prometheus_client",  "ipython", "websockets", "loguru", "protobuf==5.29.4", "cloudscraper", "aiohttp", "dnspython", "requests[socks]"]
# ///
from loguru import logger
import os
import asyncio

def print_build_date():
    try:
        with open("build_date.txt", "r") as f:
            build_date = f.read().strip()
            logger.info(f"Build date: {build_date}")
    except FileNotFoundError:
        logger.warning("build_date.txt not found")

if __name__ == "__main__":
    print_build_date()
    if os.environ.get("RELAY", None):
        from relay import relay

        asyncio.run(relay())
    if os.environ.get("CLOUDFLARE", None):
        from cloudflare import cloudflare

        asyncio.run(cloudflare())
    if os.environ.get("PROXY_LIST", None):
        from proxy_catcher import server

        server()
