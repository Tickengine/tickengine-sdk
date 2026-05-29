# 🟢 Node.js / TypeScript Client SDK

The Node.js SDK provides a highly concurrent client to connect to the TickEngine stream and decode binary MessagePack WebSocket packets. It also includes the `packMqlSignal` binary buffer utility to format matching 79-byte structs for ZeroMQ/MetaTrader 5 EA integration.

---

## 🛠️ Step 1: Install Dependencies
The client uses the lightweight `ws` WebSocket library and `@msgpack/msgpack` (the official high-speed V8 MessagePack compiler):

```bash
npm install ws @msgpack/msgpack
```

If using TypeScript, install the type definitions:
```bash
npm install --save-dev @types/ws
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

```typescript
import { TickEngineClient, packMqlSignal } from "./index";
import * as fs from "fs";
import * as zmq from "zeromq"; // requires npm install zeromq

async function run() {
    const symbolMap = JSON.parse(fs.readFileSync("symbols.json", "utf8"));
    const client = new TickEngineClient("https://tickengine.com/stream", "YOUR_API_KEY", "YOUR_ACCOUNT_ID");

    // Initialize ZeroMQ PUB socket
    const pubSocket = new zmq.Publisher();
    await pubSocket.bind("tcp://*:5555");
    console.log("ZeroMQ PUB socket bound to tcp://*:5555");

    client.onEvent(async (event) => {
        if (event.type === "alert") {
            const data = event.data;
            const symbol = data.symbol || "global";
            const side = data.side === "buy" ? 0 : 1;
            const size = data.size || 0.1;
            const price = data.price || 0.0;
            const timestamp = data.timestamp || Date.now();
            const signalId = data.id || "00000000-0000-0000-0000-000000000000";

            // 1. Pack 79-byte raw C-struct matching MqlTradeSignal
            const payload = packMqlSignal(
                0x5449434B, // Magic 'TICK'
                2,          // EventType: Alert
                0,          // OrderType: Market
                symbol,
                side,
                size,
                price,
                timestamp,
                signalId,
                symbolMap
            );

            // 2. Resolve mapped symbol name for the ZeroMQ topic
            const resolvedSymbol = symbolMap[symbol] || symbol;
            const topic = `alert.${resolvedSymbol}`;

            console.log(`Broadcasting binary signal: ${topic} (${payload.length} bytes)`);

            // 3. Publish multi-part message (Topic + Binary Struct)
            await pubSocket.send([topic, payload]);
        }
    });
}

run().catch(console.error);
```
