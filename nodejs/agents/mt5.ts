import { packMqlSignal } from "../index";
import { ExecutionAgent, OrderDetails } from "./base";

export class Mt5Agent extends ExecutionAgent {
    private socket: any;

    constructor(name: string, symbolMap: Record<string, string>, socket: any) {
        super(name, symbolMap);
        this.socket = socket;
    }

    public async execute(event: any, details: OrderDetails): Promise<void> {
        const resolvedSymbol = this.symbolMap[details.symbol];
        if (!this.socket) {
            console.warn(`MT5 Socket not active for Agent '${this.name}'`);
            return;
        }

        const payload = packMqlSignal(
            0x5449434B,
            details.eventType,
            details.orderTypeRaw,
            resolvedSymbol,
            details.sideRaw,
            details.quantity,
            details.price,
            details.timestamp,
            details.signalId
        );
        const topic = `${event.type}.${resolvedSymbol}`;
        console.log(`Publishing to MT5 Agent '${this.name}': ${topic} (${payload.length} bytes)`);
        await this.socket.send([topic, payload]);
    }
}
