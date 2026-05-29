import * as fs from "fs";
import { TickEngineClient } from "./index";
import { Mt5Agent, BinanceAgent, OkxAgent, OrderDetails, ExecutionAgent } from "./agents";

function extractOrderDetails(event: any): OrderDetails | null {
    const etype = event.type;
    const data = event.data || {};
    
    if (etype === "trade") {
        const sideIsBuy = data.side === 0 || data.side === "Buy" || data.side === "buy";
        const orderTypeIsLimit = data.type === 1 || data.type === "Limit" || data.type === "limit";
        return {
            symbol: data.symbol,
            side: sideIsBuy ? "BUY" : "SELL",
            orderType: orderTypeIsLimit ? "LIMIT" : "MARKET",
            quantity: Number(data.size || 0),
            price: Number(data.price || 0),
            signalId: data.trade_id,
            timestamp: Number(data.timestamp || 0),
            eventType: 0,
            orderTypeRaw: orderTypeIsLimit ? 1 : 0,
            sideRaw: sideIsBuy ? 0 : 1
        };
    } else if (etype === "order") {
        const sideIsBuy = data.side === 0 || data.side === "Buy" || data.side === "buy";
        const orderTypeIsLimit = data.order_type === 1 || data.order_type === "Limit" || data.order_type === "limit";
        return {
            symbol: data.symbol,
            side: sideIsBuy ? "BUY" : "SELL",
            orderType: orderTypeIsLimit ? "LIMIT" : "MARKET",
            quantity: Number(data.size || 0),
            price: Number(data.trigger_price || 0),
            signalId: data.order_id,
            timestamp: Number(data.timestamp || 0),
            eventType: 1,
            orderTypeRaw: orderTypeIsLimit ? 1 : 0,
            sideRaw: sideIsBuy ? 0 : 1
        };
    } else if (etype === "alert") {
        const orderTypeStr = String(data.order_type || "market").toLowerCase();
        const sideStr = String(data.side || "buy").toLowerCase();
        const sideIsBuy = sideStr === "buy" || sideStr === "0";
        const orderTypeIsLimit = orderTypeStr === "limit" || orderTypeStr === "1";
        return {
            symbol: data.symbol || "global",
            side: sideIsBuy ? "BUY" : "SELL",
            orderType: orderTypeIsLimit ? "LIMIT" : "MARKET",
            quantity: Number(data.size || 0),
            price: Number(data.price || 0),
            signalId: data.id,
            timestamp: Number(data.timestamp || 0),
            eventType: 2,
            orderTypeRaw: orderTypeIsLimit ? 1 : 0,
            sideRaw: sideIsBuy ? 0 : 1
        };
    } else if (etype === "metric") {
        return {
            symbol: String(data.account_id),
            side: "BUY",
            orderType: "MARKET",
            quantity: Number(data.equity || 0),
            price: Number(data.balance || 0),
            signalId: data.account_id,
            timestamp: Number(data.timestamp || 0),
            eventType: 3,
            orderTypeRaw: 0,
            sideRaw: 0
        };
    }
    return null;
}

async function main() {
    const configFile = process.env.TICKENGINE_CONFIG_FILE || "config.json";
    console.log(`Loading config from: ${configFile}`);
    const config = JSON.parse(fs.readFileSync(configFile, "utf8"));
    
    // Lazy load and setup ZeroMQ
    let zmq: any = null;
    const agents: ExecutionAgent[] = [];
    
    for (const [agentName, agentCfg] of Object.entries<any>(config.agents || {})) {
        const atype = agentCfg.type;
        const symbolMap = agentCfg.symbol_map || {};
        
        if (atype === "mt5_ea") {
            if (!zmq) {
                try {
                    zmq = require("zeromq");
                } catch (e) {
                    console.error("Warning: 'zeromq' package not installed. MT5 agent cannot be initialized.");
                    continue;
                }
            }
            const bindAddr = agentCfg.zmq_bind;
            const sock = new zmq.Publisher();
            await sock.bind(bindAddr);
            console.log(`ZeroMQ PUB socket for agent '${agentName}' bound to {bindAddr}`);
            agents.push(new Mt5Agent(agentName, symbolMap, sock));
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
