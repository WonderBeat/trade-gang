#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["ipython", "websockets", "loguru", "protobuf==5.29.4"]
# ///
from loguru import logger
import asyncio
import socket
from abc import ABCMeta
import websockets
from dataclasses import dataclass, field, asdict
from typing import List, Dict, Union, Optional, Set
import json
from all_pb2 import Announcement
import os

WEBSOCKET_SERVER_URI = os.environ.get("WEBSOCKET_SERVER_URI", "ws://localhost:8080")
UDP_HOST = os.environ.get("UDP_HOST", "0.0.0.0")
UDP_PORT = int(os.environ.get("UDP_PORT", 8081))
TEST_MODE = int(os.environ.get("TEST_MODE", False))


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
class PageEntry(BaseMessage):
    title: str
    ts: int
    tokens: Set[str]


@dataclass
class NewAnnounces(BaseMessage):
    type: str = field(init=False, default="new_announces")
    client_id: str
    entries: List[PageEntry]
    test: bool = False


async def run_udp_server():
    """Runs the UDP server and forwards data to the WebSocket server."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((UDP_HOST, UDP_PORT))
    logger.info(f"UDP server listening on {UDP_HOST}:{UDP_PORT}")

    while True:
        data, addr = sock.recvfrom(1380)
        message = Announcement()
        message.ParseFromString(data)  # .decode("utf-8")
        json_forward_announce = NewAnnounces(
            "bombardino coccodrillo",
            [PageEntry("No INFO", message.ts, list(message.tokens))],
            test=TEST_MODE,
        )
        logger.info(f"Received {json_forward_announce.to_json_str()} from {addr}")

        try:
            async with websockets.connect(WEBSOCKET_SERVER_URI) as websocket:
                await websocket.send(json_forward_announce)
                logger.info(f"Sent to WebSocket server: {message}")
        except Exception as e:
            logger.exception("Error sending to WebSocket server")


async def main():
    await asyncio.gather(run_udp_server())


if __name__ == "__main__":
    asyncio.run(main())
