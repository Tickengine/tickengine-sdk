import asyncio
import os
import json
from tickengine_sdk import TickEngineClient
from agents import Mt5Agent, BinanceAgent, OkxAgent

def extract_order_details(event: dict) -> dict:
    etype = event.get("type")
    data = event.get("data", {})
    if etype == "trade":
        return {
            "symbol": data.get("symbol"),
            "side": "BUY" if data.get("side") in [0, "Buy", "buy"] else "SELL",
            "order_type": "LIMIT" if data.get("type") in [1, "Limit", "limit"] else "MARKET",
            "quantity": float(data.get("size", 0)),
            "price": float(data.get("price", 0)),
            "signal_id": data.get("trade_id"),
            "timestamp": int(data.get("timestamp", 0)),
            "event_type": 0,
            "order_type_raw": 1 if data.get("type") in [1, "Limit", "limit"] else 0,
            "side_raw": 0 if data.get("side") in [0, "Buy", "buy"] else 1
        }
    elif etype == "order":
        return {
            "symbol": data.get("symbol"),
            "side": "BUY" if data.get("side") in [0, "Buy", "buy"] else "SELL",
            "order_type": "LIMIT" if data.get("order_type") in [1, "Limit", "limit"] else "MARKET",
            "quantity": float(data.get("size", 0)),
            "price": float(data.get("trigger_price") or 0),
            "signal_id": data.get("order_id"),
            "timestamp": int(data.get("timestamp", 0)),
            "event_type": 1,
            "order_type_raw": 1 if data.get("order_type") in [1, "Limit", "limit"] else 0,
            "side_raw": 0 if data.get("side") in [0, "Buy", "buy"] else 1
        }
    elif etype == "alert":
        order_type_str = data.get("order_type", "market").lower()
        side_str = data.get("side", "buy").lower()
        return {
            "symbol": data.get("symbol", "global"),
            "side": "BUY" if side_str in ["buy", "0"] else "SELL",
            "order_type": "LIMIT" if order_type_str in ["limit", "1"] else "MARKET",
            "quantity": float(data.get("size", 0)),
            "price": float(data.get("price", 0)),
            "signal_id": data.get("id"),
            "timestamp": int(data.get("timestamp", 0)),
            "event_type": 2,
            "order_type_raw": 1 if order_type_str in ["limit", "1"] else 0,
            "side_raw": 0 if side_str in ["buy", "0"] else 1
        }
    elif etype == "metric":
        return {
            "symbol": data.get("account_id"),
            "side": "BUY",
            "order_type": "MARKET",
            "quantity": float(data.get("equity", 0)),
            "price": float(data.get("balance", 0)),
            "signal_id": data.get("account_id"),
            "timestamp": int(data.get("timestamp", 0)),
            "event_type": 3,
            "order_type_raw": 0,
            "side_raw": 0
        }
    return None

async def main():
    config_file = os.getenv("TICKENGINE_CONFIG_FILE", "config.json")
    print(f"Loading config from: {config_file}")
    with open(config_file, "r") as f:
        config = json.load(f)
        
    import zmq
    zmq_context = zmq.Context.instance()
    
    # 1. Initialize agents based on config
    agents = []
    for agent_name, agent_cfg in config.get("agents", {}).items():
        atype = agent_cfg.get("type")
        symbol_map = agent_cfg.get("symbol_map", {})
        
        if atype == "mt5_ea":
            bind_addr = agent_cfg.get("zmq_bind")
            try:
                agent = Mt5Agent(agent_name, symbol_map, bind_addr, zmq_context)
                agents.append(agent)
            except Exception as e:
                print(f"Failed to initialize MT5 Agent '{agent_name}': {e}")
        elif atype == "binance_spot":
            agent = BinanceAgent(
                name=agent_name,
                symbol_map=symbol_map,
                api_key=agent_cfg.get("api_key"),
                api_secret=agent_cfg.get("api_secret"),
                api_url=agent_cfg.get("api_url", "https://api.binance.com")
            )
            agents.append(agent)
        elif atype == "okx_spot":
            agent = OkxAgent(
                name=agent_name,
                symbol_map=symbol_map,
                api_key=agent_cfg.get("api_key"),
                api_secret=agent_cfg.get("api_secret"),
                passphrase=agent_cfg.get("passphrase"),
                api_url=agent_cfg.get("api_url", "https://www.okx.com")
            )
            agents.append(agent)
            
    client = TickEngineClient(
        base_url=config["stream"]["url"],
        api_key=config["stream"]["api_key"],
        account_id=config["stream"]["account_id"]
    )
    
    print("Connecting to TickEngine stream...")
    async for event in client.stream_events():
        details = extract_order_details(event)
        if not details:
            continue
            
        for agent in agents:
            if agent.can_handle(details["symbol"]):
                try:
                    await agent.execute(event, details)
                except Exception as e:
                    print(f"Error executing event via Agent '{agent.name}': {e}")

if __name__ == "__main__":
    asyncio.run(main())
