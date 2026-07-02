# 🐍 Python Client SDK

The Python SDK provides an asynchronous client to connect to the TickEngine stream and decode binary MessagePack WebSocket packets. It also includes the `pack_mql_signal` binary packer utility to format matching 79-byte structs for raw TCP/MetaTrader 5 EA integration.

---

## 🛠️ Step 1: Install Dependencies
The client uses the `websockets` library and `msgpack` (the official high-speed Python compiler with C-extensions):

```bash
pip install websockets msgpack
```

---

## ⚙️ Step 2: Configure Symbol Mapping (`symbols.json`)
Provide a `symbols.json` in the client directory to map exchange symbol names to broker-specific symbols:

```json
{
  "EURUSD": "EURUSDc",
  "GBPUSD": "GBPUSDc",
  "XAUUSD": "GOLD"
}
```

---

## 💻 Step 3: Example Integration Code
Here is a complete, copy-pasteable example of how to connect to the stream and broadcast raw binary 79-byte structs to your MetaTrader 5 EA over raw TCP sockets:

```python
import asyncio
import json
from tickengine_sdk import TickEngineClient, pack_mql_signal

async def run():
    # 1. Load Symbol Mapping Rules
    with open("symbols.json", "r") as f:
        symbol_map = json.load(f)

    # Track active EA connections
    writers = []

    async def handle_client(reader, writer):
        peer = writer.get_extra_info("peername")
        print(f"New MT5 EA connected: {peer}")
        writers.append(writer)
        try:
            await reader.read(-1)
        except Exception:
            pass
        finally:
            writers.remove(writer)
            writer.close()
            print(f"MT5 EA disconnected: {peer}")

    # 2. Start TCP Socket Server
    server = await asyncio.start_server(handle_client, "0.0.0.0", 5555)
    print("TCP server listening on 0.0.0.0:5555")
    asyncio.get_event_loop().create_task(server.serve_forever())

    # 3. Connect to TickEngine Stream
    client = TickEngineClient("https://tickengine.com/stream", "YOUR_API_KEY", "YOUR_ACCOUNT_ID")

    print("Connected! Listening for stream events...")
    async for event in client.stream_events():
        if event.get("type") == "alert":
            data = event.get("data", {})
            symbol = data.get("symbol", "global")
            side = 0 if data.get("side") == "buy" else 1
            size = data.get("size", 0.1)
            price = data.get("price", 0.0)
            timestamp = data.get("timestamp", 0)
            signal_id = data.get("id", "00000000-0000-0000-0000-000000000000")

            # Resolve mapped symbol name
            resolved_symbol = symbol_map.get(symbol, symbol)

            # 4. Pack 79-byte raw packed C-struct
            payload = pack_mql_signal(
                magic=0x5449434B, # Magic 'TICK'
                event_type=2,      # EventType: Alert
                order_type=0,      # OrderType: Market
                symbol=resolved_symbol,
                side=side,
                size=size,
                price=price,
                timestamp=timestamp,
                signal_id=signal_id
            )

            print(f"Broadcasting binary signal: {resolved_symbol} ({len(payload)} bytes) to {len(writers)} connected EAs")

            # 5. Broadcast payload to all connected MT5 EAs
            dead = []
            for writer in list(writers):
                try:
                    writer.write(payload)
                    await writer.drain()
                except Exception as e:
                    print(f"Write error, dropping client: {e}")
                    dead.append(writer)
            for w in dead:
                if w in writers:
                    writers.remove(w)
                try:
                    w.close()
                except Exception:
                    pass

if __name__ == "__main__":
    asyncio.run(run())
```
