# 🐍 Python Client SDK

The Python SDK provides an asynchronous client to connect to the TickEngine stream and decode binary MessagePack WebSocket packets. It also includes the `pack_mql_signal` binary packer utility to format matching 79-byte structs for ZeroMQ/MetaTrader 5 EA integration.

---

## 🛠️ Step 1: Install Dependencies
The client uses the `websockets` library and `msgpack` (the official high-speed Python compiler with C-extensions):

```bash
pip install websockets msgpack
```

If you wish to run the ZeroMQ publisher example below, you must also install `pyzmq`:
```bash
pip install pyzmq
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
Here is a complete, copy-pasteable example of how to connect to the stream and broadcast raw binary 79-byte structs to your MetaTrader 5 EA over ZeroMQ:

```python
import asyncio
import json
import zmq
from tickengine_sdk import TickEngineClient, pack_mql_signal

async def run():
    # 1. Load Symbol Mapping Rules
    with open("symbols.json", "r") as f:
        symbol_map = json.load(f)

    # 2. Initialize ZeroMQ PUB socket
    context = zmq.Context()
    pub_socket = context.socket(zmq.PUB)
    pub_socket.bind("tcp://*:5555")
    print("ZeroMQ PUB socket bound to tcp://*:5555")

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

            # 4. Pack 79-byte raw packed C-struct
            payload = pack_mql_signal(
                magic=0x5449434B, # Magic 'TICK'
                event_type=2,      # EventType: Alert
                order_type=0,      # OrderType: Market
                symbol=symbol,
                side=side,
                size=size,
                price=price,
                timestamp=timestamp,
                signal_id=signal_id,
                symbol_map=symbol_map
            )

            # 5. Resolve mapped symbol name for ZeroMQ topic
            resolved_symbol = symbol_map.get(symbol, symbol)
            topic = f"alert.{resolved_symbol}"

            print(f"Broadcasting binary signal: {topic} ({len(payload)} bytes)")

            # 6. Publish multi-part message (Topic + Binary Struct)
            pub_socket.send_multipart([topic.encode("utf-8"), payload])

if __name__ == "__main__":
    asyncio.run(run())
```
