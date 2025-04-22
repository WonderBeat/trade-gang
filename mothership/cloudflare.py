#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["ipython", "loguru", "cloudscraper", "aiohttp"]
# ///
from loguru import logger
import asyncio
import os
import cloudscraper
from aiohttp import web

PORT = int(os.environ.get("PORT", 8880))
EXIT_ON_ERR = os.environ.get("EXIT_ON_ERR", False)

scraper = cloudscraper.create_scraper(delay=8)


def create_scraper():
    global scraper
    scraper = cloudscraper.create_scraper(delay=8)


error_count = 0
success_req_count = 0

lock = asyncio.Lock()


async def cloudflare_scrape(request):
    url = await request.text()
    headers = dict(request.headers)
    headers.pop("Host", None)
    headers.pop("User-Agent", None)
    headers.pop("Accept", None)
    headers.pop("Accept-Encoding", None)
    headers.pop("Content-Length", None)
    headers.pop("Content-Type", None)
    if not url:
        return web.Response(
            text="Error: 'url' parameter is missing in the request body", status=400
        )
    try:
        response = await asyncio.to_thread(scraper.get, url)
    except Exception as ex:
        logger.warning(f"CF request err {ex}")
        return web.Response(text="Async err", content_type="text", status=500)
    body = response.text
    status = response.status_code
    global error_count
    global success_req_count
    response.close()
    if "cf-alert" in body or status < 200 or status >= 400:
        error_count = error_count + 1
        prewiev_len = min(80, len(body))
        preview = body[0:prewiev_len].replace("\n", "")
        logger.warning(
            f"Blocked by CF after {success_req_count} requests {status}: {preview}"
        )
        body = "Blocked"
        if error_count % 11 == 0:
            if EXIT_ON_ERR:
                exit(1)
            async with lock:
                if error_count % 11 == 0:
                    scraper.close()
                    logger.warning(
                        f"Too many errors: {error_count}. Dropping old client. Query: {url[0:40]}"
                    )
                    create_scraper()
                    error_count = 0

        success_req_count = 0
    else:
        error_count = 0
        success_req_count += 1
    if success_req_count > 10 and success_req_count % 47 == 0:
        logger.info(f"{success_req_count} successfull requests")
    return web.Response(text=body, content_type="application/json", status=status)


async def cloudflare():
    app = web.Application()

    app.router.add_post("/scrape", cloudflare_scrape)

    runner = web.AppRunner(app)
    await runner.setup()

    # Bind the server to localhost on port 8080
    site = web.TCPSite(runner, "0.0.0.0", PORT)
    await site.start()

    logger.debug(f"Server started at http://0.0.0.0:{PORT}")

    while True:
        await asyncio.sleep(7777777)
