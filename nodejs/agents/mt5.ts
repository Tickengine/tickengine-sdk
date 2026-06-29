import * as net from "net";
import { packMqlSignal } from "../index";
import { ExecutionAgent, OrderDetails } from "./base";

/** Parses tcp_bind strings into { host, port }.
 *  Supports:
 *    "tcp://*:5555"        → { host: "0.0.0.0", port: 5555 }
 *    "tcp://0.0.0.0:5555"  → { host: "0.0.0.0", port: 5555 }
 *    "tcp://localhost:5555" → { host: "localhost", port: 5555 }
 */
function parseTcpBind(raw: string): { host: string; port: number } {
    const addr = raw.replace(/^tcp:\/\//, "").replace("*", "0.0.0.0");
    const lastColon = addr.lastIndexOf(":");
    return {
        host: addr.slice(0, lastColon),
        port: parseInt(addr.slice(lastColon + 1), 10),
    };
}

export class Mt5Agent extends ExecutionAgent {
    private clients: Set<net.Socket> = new Set();
    private server: net.Server;

    constructor(name: string, symbolMap: Record<string, string>, tcpBind: string) {
        super(name, symbolMap);
        const { host, port } = parseTcpBind(tcpBind);

        this.server = net.createServer((socket) => {
            console.log(`MT5 agent '${this.name}': new EA connection from ${socket.remoteAddress}:${socket.remotePort}`);
            this.clients.add(socket);

            socket.on("error", (err) => {
                console.warn(`MT5 agent '${this.name}': socket error (${socket.remoteAddress}): ${err.message}`);
            });

            socket.on("close", () => {
                this.clients.delete(socket);
                console.log(`MT5 agent '${this.name}': EA disconnected (${socket.remoteAddress})`);
            });
        });

        this.server.listen(port, host, () => {
            console.log(`MT5 TCP server for agent '${this.name}' listening on ${host}:${port}`);
        });
    }

    public async execute(event: any, details: OrderDetails): Promise<void> {
        const resolvedSymbol = this.symbolMap[details.symbol];
        if (!resolvedSymbol) return;

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

        console.log(
            `Broadcasting to MT5 agent '${this.name}' → ${resolvedSymbol} (${payload.length} bytes, ${this.clients.size} connected clients)`
        );

        const dead: net.Socket[] = [];
        for (const socket of this.clients) {
            if (!socket.writable) {
                dead.push(socket);
                continue;
            }
            try {
                socket.write(payload);
            } catch (err) {
                console.warn(`MT5 agent '${this.name}': write error, dropping client: ${err}`);
                dead.push(socket);
            }
        }
        for (const s of dead) {
            this.clients.delete(s);
            s.destroy();
        }
    }
}
