import * as crypto from "crypto";
import { ExecutionAgent, OrderDetails } from "./base";

function signHmacSha256(secret: string, data: string): string {
    return crypto.createHmac("sha256", secret).update(data).digest("hex");
}

export class BinanceAgent extends ExecutionAgent {
    private apiKey: string;
    private apiSecret: string;
    private apiUrl: string;

    constructor(name: string, symbolMap: Record<string, string>, apiKey: string, apiSecret: string, apiUrl: string) {
        super(name, symbolMap);
        this.apiKey = apiKey;
        this.apiSecret = apiSecret;
        this.apiUrl = apiUrl;
    }

    public async execute(event: any, details: OrderDetails): Promise<void> {
        if (details.quantity <= 0) {
            return;
        }

        const resolvedSymbol = this.symbolMap[details.symbol];
        const timestamp = Date.now();
        let queryParams = `symbol=${resolvedSymbol}&side=${details.side}&type=${details.orderType.toUpperCase()}&quantity=${details.quantity}&timestamp=${timestamp}`;
        
        if (details.orderType.toUpperCase() === "LIMIT") {
            if (details.price !== undefined && details.price > 0) {
                queryParams += `&price=${details.price}&timeInForce=GTC`;
            } else {
                console.error(`Error [Binance Agent '${this.name}']: Price required for LIMIT orders`);
                return;
            }
        }
        
        const signature = signHmacSha256(this.apiSecret, queryParams);
        const url = `${this.apiUrl}/api/v3/order?${queryParams}&signature=${signature}`;
        
        console.log(`Placing Binance order via Agent '${this.name}': ${details.side} ${resolvedSymbol} (qty: ${details.quantity})`);
        
        try {
            const res = await fetch(url, {
                method: "POST",
                headers: {
                    "X-MBX-APIKEY": this.apiKey
                }
            });
            const body = await res.text();
            if (res.ok) {
                console.log(`Binance Order via Agent '${this.name}' Succeeded:`, body);
            } else {
                console.error(`Binance Order via Agent '${this.name}' Failed (HTTP ${res.status}):`, body);
            }
        } catch (err) {
            console.error(`Binance Connection Error via Agent '${this.name}':`, err);
        }
    }
}
