import { WebSocketServer } from "ws";
import { encode } from "@msgpack/msgpack";
import { TickEngineClient, TickEngineEvent } from "../index";
import * as assert from "assert";

async function runTest() {
    console.log("Starting Node.js stream test...");
    const testUrl = process.env.TICKENGINE_TEST_URL;
    let wss: WebSocketServer | undefined;
    let url: string;

    if (testUrl) {
        console.log(`Connecting to integration test server at: ${testUrl}`);
        url = testUrl;
    } else {
        // 1. Start mock ws server
        wss = new WebSocketServer({ port: 0 });
        const port = await new Promise<number>((resolve) => {
            wss!.on("listening", () => {
                const addr = wss!.address();
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
            
            const binaryPayload = encode(mockEvent);
            ws.send(binaryPayload);
            setTimeout(() => ws.close(), 100);
        });

        url = `ws://127.0.0.1:${port}`;
    }

    // 2. Run client
    const client = new TickEngineClient(url, "test_key", "test_acc");
    
    const promise = new Promise<void>((resolve, reject) => {
        const disconnect = client.onEvent((event) => {
            try {
                console.log("Received event in Node.js test:", JSON.stringify(event));
                assert.ok(event.type === "order" || event.type === "trade");
                assert.ok(event.data.symbol);
                assert.ok(Number(event.data.size) > 0);
                
                disconnect();
                resolve();
            } catch (err) {
                disconnect();
                reject(err);
            }
        });

        // Set timeout for integration server
        if (testUrl) {
            setTimeout(() => reject(new Error("Timeout waiting for integration server event")), 5000);
        }
    });

    try {
        await promise;
        console.log("Node.js stream test passed successfully!");
    } finally {
        if (wss) wss.close();
    }
}

runTest().catch((err) => {
    console.error("Node.js stream test failed:", err);
    process.exit(1);
});
