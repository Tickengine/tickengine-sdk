import * as crypto from "crypto";
import { ExecutionAgent, OrderDetails } from "./base";

function signHmacSha256(secret: string, data: string): string {
    return crypto.createHmac("sha256", secret).update(data).digest("hex");
}

export class OkxAgent extends ExecutionAgent {
    private apiKey: string;
    private apiSecret: string;
    private passphrase: string;
    private apiUrl: string;

    constructor(
        name: string,
        symbolMap: Record<string, string>,
        apiKey: string,
        apiSecret: string,
        passphrase: string,
        apiUrl: string
    ) {
        super(name, symbolMap);
        this.apiKey = apiKey;
        this.apiSecret = apiSecret;
        this.passphrase = passphrase;
        this.apiUrl = apiUrl;
    }

    public async execute(event: any, details: OrderDetails): Promise<void> {
        if (details.quantity <= 0) {
            return;
        }

        const resolvedSymbol = this.symbolMap[details.symbol];
        const timestamp = new Date().toISOString();
        const path = "/api/v5/trade/order";
        const url = `${this.apiUrl}${path}`;
        
        const bodyData: Record<string, any> = {
            instId: resolvedSymbol,
            tdMode: "cash",
            side: details.side.toLowerCase(),
            ordType: details.orderType.toLowerCase(),
            sz: String(details.quantity)
        };
        
        if (details.orderType.toUpperCase() === "LIMIT") {
            if (details.price !== undefined && details.price > 0) {
                bodyData.px = String(details.price);
            } else {
                console.error(`Error [OKX Agent '${this.name}']: Price required for LIMIT orders`);
                return;
            }
        }
        
        const bodyStr = JSON.stringify(bodyData);
        const signPayload = `${timestamp}POST${path}${bodyStr}`;
        const signature = signHmacSha256(this.apiSecret, signPayload);
        
        console.log(`Placing OKX order via Agent '${this.name}': ${details.side} ${resolvedSymbol} (qty: ${details.quantity})`);
        
        try {
            const res = await fetch(url, {
                method: "POST",
                headers: {
                    "OK-ACCESS-KEY": this.apiKey,
                    "OK-ACCESS-SIGN": signature,
                    "OK-ACCESS-TIMESTAMP": timestamp,
                    "OK-ACCESS-PASSPHRASE": this.passphrase,
                    "Content-Type": "application/json"
                },
                body: bodyStr
            });
            const body = await res.text();
            if (res.ok) {
                console.log(`OKX Order via Agent '${this.name}' Succeeded:`, body);
            } else {
                console.error(`OKX Order via Agent '${this.name}' Failed (HTTP ${res.status}):`, body);
            }
        } catch (err) {
            console.error(`OKX Connection Error via Agent '${this.name}':`, err);
        }
    }
}
