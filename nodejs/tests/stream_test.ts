import { WebSocketServer } from "ws";
import { encode } from "@msgpack/msgpack";
import { TickEngineClient, TickEngineEvent } from "../index";
import * as assert from "assert";

async function runTest() {
    console.log("Starting Node.js stream test...");
    
    // 1. Start mock ws server
    const wss = new WebSocketServer({ port: 0 });
    
    const port = await new Promise<number>((resolve) => {
        wss.on("listening", () => {
            const addr = wss.address();
            if (typeof addr === "object" && addr !== null) {
                resolve(addr.port);
            }
        });
    });

    wss.on("connection", (ws) => {
        const mockEvent: TickEngineEvent = {
            type: "order",
            data: {
                orderId: "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
                symbol: "SOLUSDT",
                side: 1, // Sell
                size: 15.0,
                triggerPrice: 145.2,
                timestamp: 1625097600000,
                orderType: 1, // Limit
            }
        };
        
        // Encode binary messagepack payload
        const binaryPayload = encode(mockEvent);
        ws.send(binaryPayload);
        
        // Wait a bit for client to read then close
        setTimeout(() => ws.close(), 100);
    });

    // 2. Run client
    const client = new TickEngineClient(`ws://127.0.0.1:${port}`, "test_key", "test_acc");
    
    const promise = new Promise<void>((resolve, reject) => {
        const disconnect = client.onEvent((event) => {
            try {
                console.log("Received event in Node.js test:", JSON.stringify(event));
                assert.strictEqual(event.type, "order");
                assert.strictEqual(event.data.symbol, "SOLUSDT");
                assert.strictEqual(event.data.side, 1);
                assert.strictEqual(event.data.size, 15.0);
                assert.strictEqual(event.data.triggerPrice, 145.2);
                
                disconnect();
                resolve();
            } catch (err) {
                disconnect();
                reject(err);
            }
        });
    });

    try {
        await promise;
        console.log("Node.js stream test passed successfully!");
    } finally {
        wss.close();
    }
}

runTest().catch((err) => {
    console.error("Node.js stream test failed:", err);
    process.exit(1);
});
