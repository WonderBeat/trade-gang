import asyncio
import logging
import random
import re
import time
from concurrent.futures import ThreadPoolExecutor
import os
import json


import dns.resolver
import requests
from aiohttp import ClientError, ClientSession, ClientTimeout, web
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Gauge,
    generate_latest,
)

proxies = []
self_managed_proxies = []
last_updated = 0

# Prometheus metrics
PROXY_COUNT = Gauge("proxy_catcher_proxy_count", "Number of available proxies")
LAST_UPDATE_TIMESTAMP = Gauge(
    "proxy_catcher_last_update_timestamp", "Timestamp of last proxy list update"
)
PROXY_CHECKS_TOTAL = Counter(
    "proxy_catcher_proxy_checks_total", "Total number of proxy checks performed"
)
PROXY_CHECKS_SUCCESS = Counter(
    "proxy_catcher_proxy_checks_success", "Number of successful proxy checks"
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

requests.packages.urllib3.disable_warnings()

URL_CHECK = os.environ.get(
    "URL_CHECK",
    "https://www.binance.com/bapi/apex/v1/public/apex/cms/article/list/query?type=1&pageNo=1&pageSize=2",
)


def verify_proxy(proxy):
    """
    Verifies if a proxy is working using the requests library.

    Args:
        proxy (str): The proxy address.

    Returns:
        str or None: The proxy if it's working, otherwise None.
    """
    try:
        proxies = {"http": proxy, "https": proxy}
        headers = {"Range": "bytes=0-9"}
        response = requests.get(
            URL_CHECK, proxies=proxies, timeout=8, verify=False, headers=headers
        )
        if response.status_code >= 200 and response.status_code < 300:
            logger.info(f"Proxy {proxy} OK: {response.status_code}")
            return proxy
        else:
            logger.warning(f"Proxy {proxy} failed with status: {response.status_code}")
            return None
    except Exception as e:
        logger.warning(f"Proxy {proxy} failed with {e.__class__.__qualname__}")
        return None


async def filter_working_proxies(proxies, concurrency_limit=3):
    """
    Filters a list of proxies, returning only the working ones,
    while limiting the number of concurrent requests using a thread pool.

    Args:
        proxies (list): A list of proxy addresses.
        concurrency_limit (int): The maximum number of concurrent requests.

    Returns:
        list: A list of working proxy addresses.
    """
    working_proxies = []
    semaphore = asyncio.Semaphore(concurrency_limit)

    async def sem_verify_proxy(proxy):
        async with semaphore:
            return verify_proxy(proxy)

    with ThreadPoolExecutor(max_workers=concurrency_limit) as executor:
        loop = asyncio.get_event_loop()
        tasks = [
            loop.run_in_executor(
                executor, lambda p: asyncio.run(sem_verify_proxy(p)), proxy
            )
            for proxy in proxies
        ]
        results = await asyncio.gather(*tasks)
        for proxy in results:
            if proxy:
                working_proxies.append(proxy)
    return working_proxies


def custom_proxies():
    return [
        "socks5://10.88.101.13:1080",  # nasduck
        "socks5://10.88.101.77:1080",  # montenegro
        # "socks5://10.88.101.101:1080",  # sofia
        "socks5://10.88.101.78:1080",  # HongKong
    ]


def proxy6net():
    return [
        "socks5://FEfJQQ:ffKaKz@186.179.62.211:9116",
        "socks5://FEfJQQ:ffKaKz@38.170.243.59:9460",
        "socks5://FEfJQQ:ffKaKz@38.170.243.26:9281",
        "socks5://FEfJQQ:ffKaKz@45.237.85.228:9754",
        "socks5://FEfJQQ:ffKaKz@191.102.156.132:9193",
        "socks5://FEfJQQ:ffKaKz@38.152.245.126:9871",
        "socks5://FEfJQQ:ffKaKz@38.152.247.5:9333",
    ]


def data_impulse():
    return [
        "socks5://b7ae203cd4b047b96de5__cr.us:cb25e7c83fca24fc@gw.dataimpulse.com:824"
    ]


def resolve_k8s_proxies():
    socks_domain = "socks-proxy-socks-proxy-server.trading.svc.cluster.local"
    dns_server_ip = "10.46.0.10"
    ips = []
    try:
        resolver = dns.resolver.Resolver()
        resolver.nameservers = [dns_server_ip]
        answers = resolver.resolve(socks_domain, "A")
        for rdata in answers:
            ips.append(f"socks5://{rdata.address}:1080")
    except dns.resolver.NXDOMAIN:
        print(f"Domain not found: {socks_domain}")
    except dns.exception.Timeout:
        print(f"Timeout resolving {socks_domain}")
    except Exception as e:
        print(f"An error occurred: {e}")
    logger.info(f"Downloaded {len(ips)} items from k8s")
    return ips


async def download_proxies():
    """Download proxies from multiple sources and format them"""
    global proxies, self_managed_proxies, last_updated

    # Sources with their transformation patterns
    sources = [
        {
            "url": "https://proxy.webshare.io/api/v2/proxy/list/download/ojepfofzjjasrgwppcznvbecqlxmxoxtkhtcdznu/-/any/username/direct/",
            "pattern": r"([0-9.]+):([0-9]+):([^:]+):([a-z0-9]+)",
            "replacement": r"socks5://\3:\4@\1:\2",
        },
        {
            # santiment
            "url": "https://proxy.webshare.io/api/v2/proxy/list/download/qatpuawqcuhsigmsedblqzgcofisvdenujjyirwj/-/any/username/direct/",
            "pattern": r"([0-9.]+):([0-9]+):([^:]+):([a-z0-9]+)",
            "replacement": r"socks5://\3:\4@\1:\2",
        },
        {
            "url": "https://raw.githubusercontent.com/ErcinDedeoglu/proxies/refs/heads/main/proxies/socks4.txt",
            "pattern": r"(.+)",
            "replacement": r"socks4://\1",
        },
        {
            "url": "https://raw.githubusercontent.com/monosans/proxy-list/refs/heads/main/proxies/socks5.txt",
            "pattern": r"(.+)",
            "replacement": r"socks5://\1",
        },
        {
            "url": "https://raw.githubusercontent.com/monosans/proxy-list/refs/heads/main/proxies/socks4.txt",
            "pattern": r"(.+)",
            "replacement": r"socks4://\1",
        },
        {
            "url": "https://raw.githubusercontent.com/dpangestuw/Free-Proxy/refs/heads/main/socks5_proxies.txt",
            "pattern": r"(.+)",
            "replacement": r"socks5://\1",
        },
        {
            "url": "https://api.best-proxies.ru/proxylist.txt?key=4660317f00a7da7d037b2b0d50d2f135&limit=1100&type=socks4,socks5&includeType",
            "pattern": r"(.+)",
            "replacement": r"\1",
        },
        # {
        #     "url": "https://api.best-proxies.ru/proxylist.txt?key=4660317f00a7da7d037b2b0d50d2f135&limit=600&type=https&includeType",
        #     "pattern": r"(.+)",
        #     "replacement": r"\1",
        # },
    ]

    new_proxies = []
    timeout = ClientTimeout(total=10)

    async with ClientSession(timeout=timeout) as session:
        for source in sources:
            try:
                async with session.get(source["url"]) as response:
                    if response.status == 200:
                        text = await response.text()

                        # Split by spaces and newlines, similar to tr ' ' '\n'
                        lines = re.sub(r"\s+", "\n", text).strip().split("\n")

                        for line in lines:
                            if line.strip():
                                # Apply the regex transformation
                                transformed = re.sub(
                                    source["pattern"],
                                    source["replacement"],
                                    line.strip(),
                                )
                                new_proxies.append(transformed)

                        logger.info(
                            f"Downloaded {len(lines)} items from {source['url']}"
                        )
                    else:
                        logger.error(
                            f"Failed to download from {source['url']}, status: {response.status}"
                        )
            except (ClientError, asyncio.TimeoutError) as e:
                logger.error(f"Error downloading from {source['url']}: {e}")

    # Update self_managed_proxies
    temp_self_managed = []
    # temp_self_managed = resolve_k8s_proxies()
    temp_self_managed.extend(custom_proxies())
    temp_self_managed.extend(proxy6net())
    temp_self_managed.extend(data_impulse())
    smp_count = len(temp_self_managed)
    # temp_self_managed = await filter_working_proxies(temp_self_managed)  # python ssl errors
    self_managed_proxies = temp_self_managed
    logger.info(
        f"{len(self_managed_proxies)} out of {smp_count} self managed proxies left"
    )
    random.shuffle(new_proxies)
    start_time = time.time()
    timeout_seconds = 200
    for chunk in chunk_list(new_proxies, 100):
        elapsed_time = time.time() - start_time
        if elapsed_time >= timeout_seconds:
            break
        chunk_working_proxies = await filter_working_proxies(chunk, 3)
        proxies.extend(chunk_working_proxies)
        PROXY_COUNT.set(len(proxies))
        last_updated = time.time()
        LAST_UPDATE_TIMESTAMP.set(last_updated)

    proxies = list(dict.fromkeys(proxies))
    if len(proxies) > 300:
        proxies = proxies[:250]
    proxies.extend(self_managed_proxies)
    proxies = list(dict.fromkeys(proxies))
    logger.info(f"Proxy list updated with {len(proxies)} unique proxies")


def chunk_list(data: list[str], chunk_size: int) -> list[list[str]]:
    """Splits a list into smaller chunks of the specified size."""
    return [data[i : i + chunk_size] for i in range(0, len(data), chunk_size)]


async def refresh_proxies_periodically(refresh_seconds=900):
    """Refresh the proxy list every N seconds"""
    while True:
        try:
            await download_proxies()
        except Exception as e:
            logger.error(f"Error in proxy refresh task: {e}")

        await asyncio.sleep(refresh_seconds)


async def get_proxies(request):
    """HTTP handler to serve the proxy list"""
    response_text = "\n".join(proxies)
    return web.Response(text=response_text)


async def get_random_proxies(request):
    """HTTP handler to serve a random subset of the proxy list
    Query parameter 'count' determines how many proxies to return
    """
    prefix = str(request.query.get("prefix", ""))
    try:
        count = int(request.query.get("count", "1"))
        count = max(1, count)
        count = min(count, len(proxies))
    except ValueError:
        count = 1
    available_proxies = proxies
    if prefix:
        available_proxies = [proxy for proxy in proxies if proxy.startswith(prefix)]

    shuffled_proxies = random.sample(
        available_proxies, min(count, len(available_proxies))
    )
    response_text = "\n".join(shuffled_proxies)
    return web.Response(text=response_text)


async def get_random_self_managed_proxies(request):
    """HTTP handler to serve a random subset of self-managed proxy list
    Query parameter 'count' determines how many proxies to return
    """
    prefix = str(request.query.get("prefix", ""))
    try:
        count = int(request.query.get("count", "1"))
        count = max(1, count)
        count = min(count, len(self_managed_proxies))
    except ValueError:
        count = 1
    available_proxies = self_managed_proxies
    if prefix:
        available_proxies = [
            proxy for proxy in self_managed_proxies if proxy.startswith(prefix)
        ]

    shuffled_proxies = random.sample(
        available_proxies, min(count, len(available_proxies))
    )
    response_text = "\n".join(shuffled_proxies)
    return web.Response(text=response_text)


async def get_stats(request):
    """HTTP handler to show statistics"""
    stats = {
        "proxy_count": len(proxies),
        "last_updated": last_updated,
        "last_updated_formatted": time.strftime(
            "%Y-%m-%d %H:%M:%S", time.localtime(last_updated)
        )
        if last_updated
        else "Never",
    }
    return web.Response(text=json.dumps(stats))


async def health(request):
    if len(proxies) > 10:
        return web.Response(text="OK", status=200)
    else:
        return web.Response(text="NEP", status=500)


async def metrics(request):
    """Expose Prometheus metrics"""
    resp = web.Response(body=generate_latest())
    resp.content_type = CONTENT_TYPE_LATEST
    return resp


async def start_background_tasks(app):
    """Start the background task to refresh proxies periodically"""
    app["proxy_refresh_task"] = asyncio.create_task(refresh_proxies_periodically())


async def cleanup_background_tasks(app):
    """Clean up the background task when the application is shutting down"""
    app["proxy_refresh_task"].cancel()
    try:
        await app["proxy_refresh_task"]
    except asyncio.CancelledError:
        logger.info("Proxy refresh task cancelled")


def server():
    # Create the web application
    app = web.Application()

    # Set up routes
    app.router.add_get("/proxies", get_proxies)
    app.router.add_get("/health", health)
    app.router.add_get("/stats", get_stats)
    app.router.add_get("/metrics", metrics)
    app.router.add_get("/random-proxies", get_random_proxies)
    app.router.add_get("/random-self-managed-proxies", get_random_self_managed_proxies)

    # Register startup and cleanup signals
    app.on_startup.append(start_background_tasks)
    app.on_cleanup.append(cleanup_background_tasks)

    # Run the application
    logger.info("Starting proxy server on http://0.0.0.0:8880")

    web.run_app(app, host="0.0.0.0", port=8880, access_log=None)
