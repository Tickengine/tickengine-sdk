export interface OrderDetails {
    symbol: string;
    side: string;
    orderType: string;
    quantity: number;
    price: number;
    signalId: string;
    timestamp: number;
    eventType: number;
    orderTypeRaw: number;
    sideRaw: number;
}

export abstract class ExecutionAgent {
    public name: string;
    public symbolMap: Record<string, string>;

    constructor(name: string, symbolMap: Record<string, string>) {
        this.name = name;
        this.symbolMap = symbolMap;
    }

    public canHandle(symbol: string): boolean {
        return symbol in this.symbolMap;
    }

    public abstract execute(event: any, details: OrderDetails): Promise<void>;
}
