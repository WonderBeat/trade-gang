import asyncio
import os
import random

import aiohttp
import cloudscraper
from aiohttp import web, ClientTimeout
from loguru import logger

PORT = int(os.environ.get("PORT", 8880))
EXIT_ON_ERR = os.environ.get("EXIT_ON_ERR", "False").lower() in ("true", "1", "t")
PROXY_GET_URL = os.environ.get("PROXY_GET_URL", "http://127.0.0.1:8881/random-proxies")
TEST_URLS = os.environ.get(
    "TEST_URLS",
    "https://www.binance.me/bapi/apex/v1/public/apex/cms/article/list/query?type=1&pageNo=1&pageSize=1",
).split(",")

scrapers = []

error_count = 0
success_req_count = 0

lock = asyncio.Lock()


async def cloudflare_scrape(request):
    global scrapers
    if not scrapers:
        return web.Response(status=500)
    scraper = random.choice(scrapers)
    url = await request.text()
    if not url:
        return web.Response(
            text="Error: 'url' parameter is missing in the request body", status=400
        )
    headers = {}
    if "Range" in request.headers:
        headers["Range"] = request.headers["Range"]
    try:
        response = await asyncio.to_thread(scraper.get, url, timeout=3, headers=headers)
    except Exception as ex:
        logger.warning(f"CF request err {ex}")
        await register_err(scraper)
        return web.Response(text="Async err", content_type="text", status=500)
    body = response.text
    status = response.status_code
    response.close()
    global success_req_count
    global error_count
    if "cf-alert" in body or status < 200 or status >= 400:
        await register_err(scraper)
        return web.Response(text="Status code ERR", content_type="text", status=500)
    else:
        success_req_count += 1
    if success_req_count > 10 and success_req_count % 47 == 0:
        logger.info(f"{success_req_count} successfull requests")
    return web.Response(text=body, content_type="application/json", status=status)


async def register_err(misbehaving_scraper):
    global error_count
    global success_req_count
    error_count = error_count + 1
    success_req_count = 0
    if error_count > 10 and EXIT_ON_ERR:
        logger.debug("Exiting")
        exit(1)
    if error_count > 1 and len(scrapers) > 1:
        scrapers.remove(misbehaving_scraper)
        logger.info(f"{len(scrapers)} proxies left")
        error_count = 0


async def health(request):
    global scrapers
    if scrapers:
        return web.Response(text="OK", status=200)
    else:
        return web.Response(text="ERR", status=500)


async def refresh_scraper_periodically():
    while True:
        while len(scrapers) < 10:
            try:
                await bootstrap_scraper()
            except Exception as e:
                logger.error(f"Error in proxy refresh task: {e.__qualname__}")

            await asyncio.sleep(2)
        await asyncio.sleep(10)


async def bootstrap_scraper():
    for i in range(0, 25):
        # for browser in ["chrome", "firefox"]:
        #     for platform in ["linux", "windows", "darwin", "android"]:
        proxy = await fetch_proxy()
        if not proxy:
            await asyncio.sleep(1)
            continue
        # proxy = "socks5://10.88.101.77:1080"
        # proxy = "socks5://12.88.101.77:1080"
        proxies = {"http": proxy, "https": proxy}
        local_scraper = cloudscraper.create_scraper(
            delay=4,
            # browser={"browser": browser, "platform": platform},
        )
        local_scraper.proxies = proxies
        is_ok = False
        try:
            for url in TEST_URLS:
                await asyncio.sleep(0.1)
                response = await asyncio.to_thread(local_scraper.get, url, timeout=5)
                is_ok = (
                    response.status_code >= 200
                    and response.status_code < 300
                    and response.text
                )
                response.close()
                if not is_ok:
                    logger.debug(f"Failed with {proxy}, {response.status_code}, {url}")
                    local_scraper.close()
                    break
        except Exception as ex:
            logger.debug(f"Failed with {ex}")
            local_scraper.close()
            await asyncio.sleep(1)
            continue
        if not is_ok:
            continue
        global scrapers
        scrapers.append(local_scraper)
        logger.info(f"CF surrendered after {i} attempts. total {len(scrapers)}")
        return True
    return False


async def fetch_proxy():
    """Fetches a proxy from the proxy aggregator service."""
    timeout = aiohttp.ClientTimeout(total=None, sock_connect=3, sock_read=3)
    try:
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.get(PROXY_GET_URL) as response:
                if response.status == 200:
                    return await response.text()
                else:
                    raise Exception(f"Failed to fetch proxy. Status: {response.status}")
    except Exception as e:
        logger.error(f"Error fetching proxy: {e}")
        return None


async def start_background_tasks(app):
    """Start the background task to refresh proxies periodically"""
    app["proxy_refresh_task"] = asyncio.create_task(refresh_scraper_periodically())


async def cleanup_background_tasks(app):
    """Clean up the background task when the application is shutting down"""
    app["proxy_refresh_task"].cancel()
    try:
        await app["proxy_refresh_task"]
    except asyncio.CancelledError:
        logger.info("Proxy refresh task cancelled")


async def cloudflare():
    app = web.Application()

    app.router.add_post("/scrape", cloudflare_scrape)
    app.router.add_get("/health", health)
    app.on_startup.append(start_background_tasks)
    app.on_cleanup.append(cleanup_background_tasks)

    runner = web.AppRunner(app)
    await runner.setup()

    # Bind the server to localhost on port 8080
    site = web.TCPSite(runner, "0.0.0.0", PORT)
    await site.start()

    logger.debug(f"Server started at http://0.0.0.0:{PORT}")

    while True:
        await asyncio.sleep(7777777)
