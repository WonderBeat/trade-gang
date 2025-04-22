import asyncio
import json
import os
import socket
from abc import ABCMeta
from dataclasses import asdict, dataclass, field
from typing import List, Set

import websockets
from all_pb2 import Announcement
from loguru import logger

WEBSOCKET_SERVER_URI = os.environ.get("WEBSOCKET_SERVER_URI", "ws://localhost:8080")
UDP_HOST = os.environ.get("UDP_HOST", "0.0.0.0")
UDP_PORT = int(os.environ.get("UDP_PORT", 8081))
DRY_RUN = int(os.environ.get("DRY_RUN", 1))


class SetEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, set):
            return list(obj)  # Convert set to list
        return super().default(obj)


@dataclass
class BaseMessage(metaclass=ABCMeta):
    def to_json_str(self):
        return json.dumps(asdict(self), cls=SetEncoder)


@dataclass
class PageEntry:
    title: str
    ts: int
    tokens: Set[str]
    catalog_id: int


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
        data, addr = sock.recvfrom(1380)
        message = Announcement()
        message.ParseFromString(data)  # .decode("utf-8")
        json_forward_announce = NewAnnounces(
            "bombardino coccodrillo",
            [
                PageEntry(
                    message.title, message.ts, list(message.tokens), message.catalog
                )
            ],
            dry_run=DRY_RUN,
        )
        json_str = json_forward_announce.to_json_str()
        logger.info(f"Received {message} from {addr}")
        if not message.call_to_action:
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


if __name__ == "__main__":
    if os.environ.get("RELAY", None):
        asyncio.run(relay())
    if os.environ.get("CLOUDFLARE", None):
        asyncio.run(cloudflare())
