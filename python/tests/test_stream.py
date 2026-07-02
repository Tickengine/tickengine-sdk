import asyncio
import unittest
import websockets
import msgpack
import sys
import os

# Ensure the parent directory is in python path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from tickengine_sdk import TickEngineClient

class TestStreamClient(unittest.IsolatedAsyncioTestCase):
    async def test_python_stream_parsing(self):
        received_events = []
        test_url = os.getenv("TICKENGINE_TEST_URL")

        if test_url:
            print(f"Connecting to integration test server at: {test_url}")
            client = TickEngineClient(test_url, "test_key", "test_acc")
            # Wait up to 5 seconds for events
            try:
                async for event in client.stream_events():
                    received_events.append(event)
                    break
            except Exception as e:
                self.fail(f"Failed to stream from integration server: {e}")
        else:
            # 1. Setup mock WebSocket server
            async def mock_ws_server(websocket):
                try:
                    mock_event = {
                        "type": "trade",
                        "data": {
                            "tradeId": "550e8400-e29b-41d4-a716-446655440000",
                            "symbol": "ETHUSDT",
                            "side": 0,  # Buy
                            "size": 2.5,
                            "price": 3100.5,
                            "timestamp": 1625097600000,
                            "type": 0,  # Market
                        }
                    }
                    # Pack to MessagePack binary format
                    binary_payload = msgpack.packb(mock_event)
                    await websocket.send(binary_payload)
                    await asyncio.sleep(0.1)
                except Exception as e:
                    print(f"Server error: {e}")
                finally:
                    await websocket.close()

            # Bind to localhost on ephemeral port
            async with websockets.serve(mock_ws_server, "127.0.0.1", 0) as server:
                port = list(server.sockets)[0].getsockname()[1]
                base_url = f"ws://127.0.0.1:{port}"
                client = TickEngineClient(base_url, "test_key", "test_acc")
                async for event in client.stream_events():
                    received_events.append(event)
                    break

        # 3. Assertions
        self.assertEqual(len(received_events), 1)
        event = received_events[0]
        self.assertEqual(event["type"], "trade")
        self.assertIsNotNone(event["data"].get("symbol"))
        # Verify sizes and price parse correctly as floats/nums
        self.assertTrue(float(event["data"]["size"]) > 0)
        self.assertTrue(float(event["data"]["price"]) > 0)

if __name__ == "__main__":
    unittest.main()
