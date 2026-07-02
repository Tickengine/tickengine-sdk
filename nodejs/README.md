# 🟢 Node.js / TypeScript Client SDK

The Node.js SDK provides a highly concurrent client to connect to the TickEngine stream and decode binary MessagePack WebSocket packets. It also includes the `packMqlSignal` binary buffer utility to format matching 79-byte structs for raw TCP/MetaTrader 5 EA integration.

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
Here is a complete, copy-pasteable example of how to connect to the stream and broadcast raw binary 79-byte structs to your MetaTrader 5 EA over raw TCP sockets:

```typescript
import { TickEngineClient, packMqlSignal } from "./index";
import * as fs from "fs";
import * as net from "net";

async function run() {
    const symbolMap = JSON.parse(fs.readFileSync("symbols.json", "utf8"));
    const client = new TickEngineClient("https://tickengine.com/stream", "YOUR_API_KEY", "YOUR_ACCOUNT_ID");

    // Track active EA socket connections
    const clients: Set<net.Socket> = new Set();

    // Start TCP Socket Server
    const server = net.createServer((socket) => {
        console.log(`New MT5 EA connected: ${socket.remoteAddress}:${socket.remotePort}`);
        clients.add(socket);

        socket.on("error", (err) => {
            console.warn(`Socket error: ${err.message}`);
        });

        socket.on("close", () => {
            clients.delete(socket);
            console.log(`MT5 EA disconnected`);
        });
    });

    server.listen(5555, "0.0.0.0", () => {
        console.log("TCP server listening on 0.0.0.0:5555");
    });

    client.onEvent(async (event) => {
        if (event.type === "alert") {
            const data = event.data;
            const symbol = data.symbol || "global";
            const side = data.side === "buy" ? 0 : 1;
            const size = data.size || 0.1;
            const price = data.price || 0.0;
            const timestamp = data.timestamp || Date.now();
            const signalId = data.id || "00000000-0000-0000-0000-000000000000";

            // Resolve mapped symbol name
            const resolvedSymbol = symbolMap[symbol] || symbol;

            // 1. Pack 79-byte raw C-struct matching MqlTradeSignal
            const payload = packMqlSignal(
                0x5449434B, // Magic 'TICK'
                2,          // EventType: Alert
                0,          // OrderType: Market
                resolvedSymbol,
                side,
                size,
                price,
                timestamp,
                signalId
            );

            console.log(`Broadcasting binary signal: ${resolvedSymbol} (${payload.length} bytes) to ${clients.size} connected EAs`);

            // 2. Broadcast raw payload to all connected MT5 EAs
            const dead: net.Socket[] = [];
            for (const socket of clients) {
                if (!socket.writable) {
                    dead.push(socket);
                    continue;
                }
                try {
                    socket.write(payload);
                } catch (err) {
                    console.warn(`Write error, dropping client: ${err}`);
                    dead.push(socket);
                }
            }
            for (const s of dead) {
                clients.delete(s);
                s.destroy();
            }
        }
    });
}

run().catch(console.error);
```
