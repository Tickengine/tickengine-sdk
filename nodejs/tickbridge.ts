import * as fs from "fs";
import { TickEngineClient } from "./index";
import { Mt5Agent, BinanceAgent, OkxAgent, OrderDetails, ExecutionAgent } from "./agents";

// ---------------------------------------------------------------------------
// Order type helpers
// ---------------------------------------------------------------------------

/** Maps stream order type value → MQL5 raw int. 0=Market, 1=Limit, 2=Stop */
function orderTypeRaw(val: any): number {
    if (val === 1 || val === "Limit" || val === "limit") return 1;
    if (val === 2 || val === "Stop"  || val === "stop")  return 2;
    return 0; // Market (default)
}

function orderTypeLabel(raw: number): string {
    if (raw === 1) return "LIMIT";
    if (raw === 2) return "STOP";
    return "MARKET";
}

// ---------------------------------------------------------------------------
// Event parsing  (stream serialises all DTOs with rename_all = "camelCase")
// ---------------------------------------------------------------------------

function extractOrderDetails(event: any): OrderDetails | null {
    const etype = event.type;
    const data = event.data || {};

    if (etype === "trade") {
        // TradeExecutedEventDto: type_ → wire key "type", value "Market"/"Limit"/"Stop"
        const sideIsBuy = data.side === 0 || data.side === "Buy" || data.side === "buy";
        const otRaw = orderTypeRaw(data.type);
        return {
            symbol: data.symbol,
            side: sideIsBuy ? "BUY" : "SELL",
            orderType: orderTypeLabel(otRaw),
            quantity: Number(data.size || 0),
            price: Number(data.price || 0),
            signalId: data.status === "closed" && data.entryId ? data.entryId : data.tradeId,
            timestamp: Number(data.timestamp || 0),
            eventType: 0,
            orderTypeRaw: otRaw,
            sideRaw: sideIsBuy ? 0 : 1,
        };
    }

    if (etype === "order") {
        // OrderEventDto keys: orderId, orderType, triggerPrice, side, size, timestamp
        const sideIsBuy = data.side === 0 || data.side === "Buy" || data.side === "buy";
        const otRaw = orderTypeRaw(data.orderType ?? data.order_type);
        return {
            symbol: data.symbol,
            side: sideIsBuy ? "BUY" : "SELL",
            orderType: orderTypeLabel(otRaw),
            quantity: Number(data.size || 0),
            price: Number(data.triggerPrice ?? data.trigger_price ?? 0),  // camelCase key
            signalId: data.orderId ?? data.order_id,                      // camelCase key
            timestamp: Number(data.timestamp || 0),
            eventType: 1,
            orderTypeRaw: otRaw,
            sideRaw: sideIsBuy ? 0 : 1,
        };
    }

    if (etype === "alert") {
        // WatchAlert has no side/order_type — defaults to MARKET BUY
        const orderTypeStr = String(data.order_type || data.orderType || "market").toLowerCase();
        const sideStr = String(data.side || "buy").toLowerCase();
        const sideIsBuy = sideStr === "buy" || sideStr === "0";
        const otRaw = orderTypeRaw(orderTypeStr === "limit" ? "Limit" : orderTypeStr === "stop" ? "Stop" : "Market");
        return {
            symbol: data.symbol || "global",
            side: sideIsBuy ? "BUY" : "SELL",
            orderType: orderTypeLabel(otRaw),
            quantity: Number(data.size || 0),
            price: Number(data.price || 0),
            signalId: data.id,
            timestamp: Number(data.timestamp || 0),
            eventType: 2,
            orderTypeRaw: otRaw,
            sideRaw: sideIsBuy ? 0 : 1,
        };
    }

    return null;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
    const configFile = process.env.TICKENGINE_CONFIG_FILE || "config.json";
    console.log(`Loading config from: ${configFile}`);
    const config = JSON.parse(fs.readFileSync(configFile, "utf8"));

    const agents: ExecutionAgent[] = [];

    for (const [agentName, agentCfg] of Object.entries<any>(config.agents || {})) {
        const atype = agentCfg.type;
        const symbolMap = agentCfg.symbol_map || {};

        if (atype === "mt5_ea") {
            const tcpBind = agentCfg.tcp_bind;          // renamed from zmq_bind
            agents.push(new Mt5Agent(agentName, symbolMap, tcpBind));
        } else if (atype === "binance_spot") {
            agents.push(new BinanceAgent(
                agentName,
                symbolMap,
                agentCfg.api_key,
                agentCfg.api_secret,
                agentCfg.api_url || "https://api.binance.com"
            ));
        } else if (atype === "okx_spot") {
            agents.push(new OkxAgent(
                agentName,
                symbolMap,
                agentCfg.api_key,
                agentCfg.api_secret,
                agentCfg.passphrase,
                agentCfg.api_url || "https://www.okx.com"
            ));
        }
    }

    const client = new TickEngineClient(
        config.stream.url,
        config.stream.apiKey || config.stream.api_key,
        config.stream.accountId || config.stream.account_id
    );

    console.log("Connecting to TickEngine stream...");
    client.onEvent(async (event) => {
        const details = extractOrderDetails(event);
        if (!details) return;

        for (const agent of agents) {
            if (agent.canHandle(details.symbol)) {
                try {
                    await agent.execute(event, details);
                } catch (err) {
                    console.error(`Error executing event via Agent '${agent.name}':`, err);
                }
            }
        }
    });
}

main().catch(console.error);
