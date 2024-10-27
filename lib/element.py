#!/usr/bin/env python3
# coding=utf-8

# poljar/matrix-nio: A Python Matrix client library, designed according to sans I/O (http://sans-io.readthedocs.io/) principles
# https://github.com/poljar/matrix-nio

# python3 -m pip install matrix-nio

# sudo apt install -y libolm-dev
# python3 -m pip install "matrix-nio[e2e]"

import sys
import asyncio
from nio import AsyncClient, MatrixRoom, RoomMessageText


async def main(homeserver, user_id, password, room_id, message):
    client = AsyncClient(homeserver, user_id)
    await client.login(password)
    await client.room_send(
        room_id=room_id,
        message_type="m.room.message",
        content={
            "msgtype": "m.text",
            "body": message
        }
    )
    await client.close()

if __name__ == "__main__":
    if len(sys.argv) != 5:
        print("Usage: python script.py <homeserver> <user_id> <password> <room_id>")
        sys.exit(1)

    homeserver = sys.argv[1]  # https://matrix.example.com
    user_id = sys.argv[2]  # @bot:example.com
    password = sys.argv[3]  # your_password
    room_id = sys.argv[4]  # !xXxXxXxXxXxXxXxXxX:example.com

    # Read message from stdin
    message = sys.stdin.read().strip()

    asyncio.get_event_loop().run_until_complete(
        main(homeserver, user_id, password, room_id, message))
