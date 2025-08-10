import asyncio
from enum import Enum
import json
import os
import socket
from abc import ABCMeta
from dataclasses import asdict, dataclass, field
from typing import List, Set
import re

import websockets
from all_pb2 import Announcement
from loguru import logger

WEBSOCKET_SERVER_URI = os.environ.get("WEBSOCKET_SERVER_URI", "ws://localhost:8080")
UDP_HOST = os.environ.get("UDP_HOST", "0.0.0.0")
UDP_PORT = int(os.environ.get("UDP_PORT", 8081))
DRY_RUN = int(os.environ.get("DRY_RUN", 1)) > 0


class SetEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, set):
            return list(obj)  # Convert set to list
        return super().default(obj)


@dataclass
class BaseMessage(metaclass=ABCMeta):
    def to_json_str(self):
        return json.dumps(asdict(self), cls=SetEncoder)


class PageEntryCEX(Enum):
    BINANCE = "binance"
    UPBIT = "upbit"


@dataclass
class PageEntry:
    title: str
    ts: int
    tokens: Set[str]
    catalog_id: int
    cex: str


@dataclass
class NewAnnounces(BaseMessage):
    type: str = field(init=False, default="new_announces")
    client_id: str
    entries: List[PageEntry]
    dry_run: bool = False


async def run_udp_server():
    """Runs the UDP server and forwards data to the WebSocket server."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((UDP_HOST, UDP_PORT))
    logger.info(f"UDP server listening on {UDP_HOST}:{UDP_PORT}, DRYRUN: {DRY_RUN}")

    while True:
        data, addr = sock.recvfrom(1300)
        message = Announcement()
        message.ParseFromString(data)  # .decode("utf-8")
        cex = PageEntryCEX.BINANCE.value
        dry_run = False
        decoded_tokens = None
        if message.catalog == 777 or message.catalog == 888:  # upbit announce
            decoded_tokens = parse_upbit_listing_tokens(message.title)
            message.catalog = 48  # listing
            cex = PageEntryCEX.UPBIT.value
            dry_run = True
        if message.catalog == 777:
            dry_run = False
        dry_run = dry_run or DRY_RUN

        json_forward_announce = NewAnnounces(
            "bombardino coccodrillo",
            [
                PageEntry(
                    title=message.title,
                    ts=message.ts,
                    tokens=decoded_tokens or set(message.tokens),
                    catalog_id=message.catalog,
                    cex=cex,
                )
            ],
            dry_run=dry_run,
        )
        json_str = json_forward_announce.to_json_str()
        logger.info(f"Received {json_forward_announce} from {addr}")
        if cex == PageEntryCEX.BINANCE.value and not message.call_to_action:
            logger.debug("No need to relay")
            continue
        try:
            async with websockets.connect(WEBSOCKET_SERVER_URI) as websocket:
                await websocket.send(json_str)
                logger.info("Successfully sent to WebSocket server")
        except Exception:
            logger.exception("Error sending to WebSocket server")


async def relay():
    await asyncio.gather(run_udp_server())


def parse_upbit_listing_tokens(message) -> Set[str]:
    TOKENS_BLACKLIST = {
        "BNB",
        "USD",
        "COIN",
        "FD",
        "USDC",
        "BTC",
        "ETH",
        "SOL",
        "KRW",
        "LISTING",
        "UPBIT",
    }

    tokens = re.findall(r"\b[A-Z0-9]+\b", message)
    if not tokens:
        return set()

    # filter and clean tokens
    cleaned_tokens = set()
    for token in tokens:
        token = token.removesuffix("USD").removesuffix("USDT")
        if (
            not all(x.isdigit() for x in token)
            and len(token) > 1
            and token not in TOKENS_BLACKLIST
        ):
            cleaned_tokens.add(token)

    return cleaned_tokens


if __name__ == "__main__":
    if os.environ.get("RELAY", None):
        asyncio.run(relay())
    if os.environ.get("CLOUDFLARE", None):
        asyncio.run(cloudflare())
