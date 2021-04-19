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
