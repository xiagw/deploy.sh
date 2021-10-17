#!/usr/bin/env python3
# coding=utf-8

# poljar/matrix-nio: A Python Matrix client library, designed according to sans I/O (http://sans-io.readthedocs.io/) principles
# https://github.com/poljar/matrix-nio

# pip install matrix-nio

# sudo apt install -y libolm-dev
# pip install "matrix-nio[e2e]"

import sys
import asyncio
from nio import AsyncClient, MatrixRoom, RoomMessageText

async def main(*args):
    client = AsyncClient("https://matrix.example.com", "@bot:example.com")

    await client.login("your_password")
    await client.room_send(
        room_id="!xXxXxXxXxXxXxXxXxX:example.com",
        message_type="m.room.message",
        content={
            "msgtype": "m.text",
            "body": str(sys.argv[1])
        }
    )
    await client.close()

asyncio.get_event_loop().run_until_complete(main())
