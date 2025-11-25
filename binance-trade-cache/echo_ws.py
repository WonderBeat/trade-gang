#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["websockets", "loguru"]
# ///

import asyncio

import websockets


async def echo(websocket):
    async for message in websocket:
        await websocket.send(message)


async def main():
    async with websockets.serve(echo, "localhost", 8765):
        print("WebSocket echo server started on ws://localhost:8765")
        await asyncio.Future()  # run forever


if __name__ == "__main__":
    metric_configs = [
        {
            "metric": "holders_distribution_delta_1e_3",
            "lower": 0,
            "upper": 0.001,
            "isHolderAmount": False,
        },
        {
            "metric": "holders_distribution_delta_1e_2",
            "lower": 0.001,
            "upper": 0.01,
            "isHolderAmount": False,
        },
        {
            "metric": "holders_distribution_delta_1e_1",
            "lower": 0.01,
            "upper": 0.1,
            "isHolderAmount": False,
        },
        {
            "metric": "holders_distribution_delta_1",
            "lower": 0.1,
            "upper": 1,
            "isHolderAmount": False,
        },
        {
            "metric": "holders_distribution_delta_1e1",
            "lower": 1,
            "upper": 10,
            "isHolderAmount": False,
        },
        {
            "metric": "holders_distribution_delta_1e2",
            "lower": 10,
            "upper": 100,
            "isHolderAmount": False,
        },
        {
            "metric": "holders_distribution_delta_1e3",
            "lower": 100,
            "upper": 1000,
            "isHolderAmount": False,
        },
        {
            "metric": "holders_distribution_delta_1e4",
            "lower": 1000,
            "upper": 10000,
            "isHolderAmount": False,
        },
        {
            "metric": "holders_distribution_delta_1e5",
            "lower": 10000,
            "upper": 100000,
            "isHolderAmount": False,
        },
        {
            "metric": "holders_distribution_delta_1e6",
            "lower": 100000,
            "upper": 1000000,
            "isHolderAmount": False,
        },
        {
            "metric": "holders_distribution_delta_1e7",
            "lower": 1000000,
            "upper": 10000000,
            "isHolderAmount": False,
        },
        {
            "metric": "holders_distribution_delta_1e8",
            "lower": 10000000,
            "upper": 100000000,
            "isHolderAmount": False,
        },
        {
            "metric": "holders_distribution_delta_1e9",
            "lower": 100000000,
            "upper": 1000000000,
            "isHolderAmount": False,
        },
        {
            "metric": "holders_distribution_delta_inf",
            "lower": 1000000000,
            "upper": "null",
            "isHolderAmount": False,
        },
        {
            "metric": "holders_distribution_delta_all",
            "lower": 0,
            "upper": "null",
            "isHolderAmount": False,
        },
        {
            "metric": "holders_distribution_amount_delta_1e_3",
            "lower": 0,
            "upper": 0.001,
            "isHolderAmount": True,
        },
        {
            "metric": "holders_distribution_amount_delta_1e_2",
            "lower": 0.001,
            "upper": 0.01,
            "isHolderAmount": True,
        },
        {
            "metric": "holders_distribution_amount_delta_1e_1",
            "lower": 0.01,
            "upper": 0.1,
            "isHolderAmount": True,
        },
        {
            "metric": "holders_distribution_amount_delta_1",
            "lower": 0.1,
            "upper": 1,
            "isHolderAmount": True,
        },
        {
            "metric": "holders_distribution_amount_delta_1e1",
            "lower": 1,
            "upper": 10,
            "isHolderAmount": True,
        },
        {
            "metric": "holders_distribution_amount_delta_1e2",
            "lower": 10,
            "upper": 100,
            "isHolderAmount": True,
        },
        {
            "metric": "holders_distribution_amount_delta_1e3",
            "lower": 100,
            "upper": 1000,
            "isHolderAmount": True,
        },
        {
            "metric": "holders_distribution_amount_delta_1e4",
            "lower": 1000,
            "upper": 10000,
            "isHolderAmount": True,
        },
        {
            "metric": "holders_distribution_amount_delta_1e5",
            "lower": 10000,
            "upper": 100000,
            "isHolderAmount": True,
        },
        {
            "metric": "holders_distribution_amount_delta_1e6",
            "lower": 100000,
            "upper": 1000000,
            "isHolderAmount": True,
        },
        {
            "metric": "holders_distribution_amount_delta_1e7",
            "lower": 1000000,
            "upper": 10000000,
            "isHolderAmount": True,
        },
        {
            "metric": "holders_distribution_amount_delta_1e8",
            "lower": 10000000,
            "upper": 100000000,
            "isHolderAmount": True,
        },
        {
            "metric": "holders_distribution_amount_delta_1e9",
            "lower": 100000000,
            "upper": 1000000000,
            "isHolderAmount": True,
        },
        {
            "metric": "holders_distribution_amount_delta_inf",
            "lower": 1000000000,
            "upper": "null",
            "isHolderAmount": True,
        },
        {
            "metric": "holders_distribution_amount_delta_all",
            "lower": 0,
            "upper": "null",
            "isHolderAmount": True,
        },
    ]

    select_template = """
    SELECT
        'oreoU2P8bN6jkk3jbaiVxYnG1dCXcYxwhwyK9jSybcp' as TOKEN,
        PUBLIC.GET_METRIC_ID_BY_NAME('{metric}') as METRIC_ID,
        7737 as ASSET_ID,
        {lower} as lowerThreshold,
        {upper} as upperThreshold,
        11,
        {isHolderAmount} as isHolderAmount
    """

    select_statements = [
        select_template.format(
            metric=config["metric"],
            lower=config["lower"],
            upper=config["upper"],
            isHolderAmount=config["isHolderAmount"],
        )
        for config in metric_configs
    ]
    token_distribution_tokens_temp_table = (
        """CREATE OR REPLACE TEMPORARY TABLE TOKENS AS (\nSELECT * FROM ("""
        + "\nUNION ALL\n".join(select_statements)
        + ")\n);"
    )
    print(token_distribution_tokens_temp_table)

    asyncio.run(main())
