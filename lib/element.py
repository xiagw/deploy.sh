#!/usr/bin/env python3
# coding=utf-8

# poljar/matrix-nio: A Python Matrix client library, designed according to sans I/O (http://sans-io.readthedocs.io/) principles
# https://github.com/poljar/matrix-nio

# python3 -m pip install matrix-nio

# sudo apt install -y libolm-dev
# python3 -m pip install "matrix-nio[e2e]"

import sys
import asyncio
from nio import AsyncClient, AsyncClientConfig, RoomMessageText

async def main(homeserver, user_id, password, room_id, message):
    store_path = "./nio_store"          # 本地存储密钥和状态
    device_id = "MYDEVICE"             # 可选，建议固定
    config = AsyncClientConfig(encryption_enabled=True)
    client = AsyncClient(
        homeserver,
        user_id,
        device_id=device_id,
        store_path=store_path,
        config=config,
    )

    await client.login(password)

    # 先同步一次，获取房间和加密状态
    await client.sync(30000)

    await client.room_send(
        room_id=room_id,
        message_type="m.room.message",
        content={
            "msgtype": "m.text",
            "body": message,
        },
    )

    await client.close()

if __name__ == "__main__":
    if len(sys.argv) != 5:
        print("Usage: echo message | python3 script.py <homeserver> <user_id> <password> <room_id>")
        sys.exit(1)

    homeserver = sys.argv[1]  # https://matrix.example.com
    user_id = sys.argv[2]  # @bot:example.com
    password = sys.argv[3]  # your_password
    room_id = sys.argv[4]  # !xXxXxXxXxXxXxXxXxX:example.com

    # Read message from stdin
    message = sys.stdin.read().strip()
    asyncio.get_event_loop().run_until_complete(
        main(homeserver, user_id, password, room_id, message)
    )
