import asyncio
import websockets
import msgpack
from typing import AsyncGenerator

class TickEngineClient:
    def __init__(self, base_url: str, api_key: str, account_id: str):
        # Ensure base_url uses ws/wss
        ws_url = base_url.replace("http://", "ws://").replace("https://", "wss://")
        if "/stream" in ws_url:
            ws_url = ws_url.replace("/stream", "/stream/ws")
        elif not ws_url.endswith("/ws"):
             ws_url = f"{ws_url}/ws"
             
        self.url = f"{ws_url}?api_key={api_key}&account_id={account_id}"
        self.api_key = api_key

    async def stream_events(self) -> AsyncGenerator[dict, None]:
        retry_delay = 1
        while True:
            try:
                async with websockets.connect(self.url) as websocket:
                    retry_delay = 1 # Reset on success
                    while True:
                        try:
                            # Receive high-performance MessagePack binary frame
                            message = await websocket.recv()
                            yield msgpack.unpackb(message, raw=False)
                        except websockets.ConnectionClosed:
                            break
            except Exception as e:
                print(f"WebSocket error: {e}. Retrying in {retry_delay}s...")
                await asyncio.sleep(retry_delay)
                retry_delay = min(retry_delay * 2, 60)


