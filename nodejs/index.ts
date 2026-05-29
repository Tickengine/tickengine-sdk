import WebSocket from "ws";
import { decode } from "@msgpack/msgpack";

export interface TickEngineEvent {
    type: "trade" | "order" | "metric" | "alert";
    data: any;
}

export class TickEngineClient {
    private url: string;

    constructor(baseUrl: string, apiKey: string, accountId: string) {
        // Ensure baseUrl uses ws/wss
        let wsUrl = baseUrl.replace("http://", "ws://").replace("https://", "wss://");
        if (wsUrl.includes("/stream") && !wsUrl.endsWith("/ws")) {
            wsUrl = wsUrl.replace("/stream", "/stream/ws");
        } else if (!wsUrl.endsWith("/ws")) {
            wsUrl = `${wsUrl}/ws`;
        }
        this.url = `${wsUrl}?api_key=${apiKey}&account_id=${accountId}`;
    }

    public onEvent(callback: (event: TickEngineEvent) => void): () => void {
        let ws: WebSocket;
        let retryDelay = 1000;
        let closed = false;

        const connect = () => {
            if (closed) return;
            
            ws = new WebSocket(this.url);

            ws.on("open", () => {
                retryDelay = 1000; // Reset on success
            });

            ws.on("message", (data) => {
                try {
                    // Decode high-performance MessagePack binary frame
                    const event = decode(data as Uint8Array) as TickEngineEvent;
                    callback(event);
                } catch (err) {
                    console.error("Failed to parse MessagePack binary event", err);
                }
            });

            ws.on("error", (err) => {
                console.error("WebSocket Error:", err.message);
            });

            ws.on("close", () => {
                if (!closed) {
                    console.error("WebSocket connection closed, reconnecting in " + retryDelay + "ms...");
                    setTimeout(connect, retryDelay);
                    retryDelay = Math.min(retryDelay * 2, 60000);
                }
            });
        };

        connect();

        return () => {
            closed = true;
            if (ws) ws.close();
        };
    }
}

export function packMqlSignal(
    magic: number,       // uint32 (e.g. 0x5449434B / 'TICK')
    eventType: number,   // uint8  (0=Trade, 1=Order, 2=Alert, 3=Metric)
    orderType: number,   // uint8  (0=Market, 1=Limit, 2=Stop)
    symbol: string,      // char[32] (fixed size null-padded)
    side: number,        // uint8  (0=Buy, 1=Sell)
    size: number,        // double (8 bytes)
    price: number,       // double (8 bytes)
    timestamp: number,   // int64  (8 bytes)
    signalId: string,    // hex or standard UUID string
    symbolMap?: Record<string, string> // optional symbol map parameter
): Buffer {
    const resolvedSymbol = symbolMap && symbolMap[symbol] ? symbolMap[symbol] : symbol;
    const buffer = Buffer.alloc(79);

    buffer.writeUInt32LE(magic, 0);          // 4 bytes (offset 0)
    buffer.writeUInt8(eventType, 4);         // 1 byte  (offset 4)
    buffer.writeUInt8(orderType, 5);         // 1 byte  (offset 5)
    buffer.writeUInt8(side, 6);              // 1 byte  (offset 6)
    
    // Write symbol (32-byte fixed size, null-padded)
    const symbolBuf = Buffer.alloc(32);
    symbolBuf.write(resolvedSymbol.slice(0, 31), "utf8");
    symbolBuf.copy(buffer, 7);               // 32 bytes (offset 7 to 38)

    // Write signal ID (16-byte UUID bytes)
    const cleanUuid = signalId.replace(/-/g, "");
    const signalIdBuf = Buffer.from(cleanUuid, "hex");
    if (signalIdBuf.length === 16) {
        signalIdBuf.copy(buffer, 39);        // 16 bytes (offset 39 to 54)
    } else {
        // Fallback: fill with zeros if invalid length
        Buffer.alloc(16).copy(buffer, 39);
    }

    buffer.writeDoubleLE(size, 55);          // 8 bytes (offset 55)
    buffer.writeDoubleLE(price, 63);         // 8 bytes (offset 63)
    buffer.writeBigInt64LE(BigInt(timestamp), 71); // 8 bytes (offset 71)

    return buffer; // exactly 79 bytes matching MqlTradeSignal packed struct
}
