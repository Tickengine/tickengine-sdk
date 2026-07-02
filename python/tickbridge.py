import asyncio
import os
import json
from tickengine_sdk import TickEngineClient
from agents import Mt5Agent, BinanceAgent, OkxAgent


def _order_type_raw(val) -> int:
    """Map stream ClientOrderType string to MQL5 int. 0=Market 1=Limit 2=Stop."""
    if val in (1, "Limit", "limit"): return 1
    if val in (2, "Stop",  "stop"):  return 2
    return 0


def _order_type_label(raw: int) -> str:
    return ["MARKET", "LIMIT", "STOP"][raw]


def _side(val) -> tuple[str, int]:
    is_buy = val in (0, "Buy", "buy")
    return ("BUY" if is_buy else "SELL", 0 if is_buy else 1)


def extract_order_details(event: dict) -> dict | None:
    etype = event.get("type")
    data  = event.get("data", {})

    if etype == "trade":
        # TradeExecutedEventDto (camelCase): type → "Market"/"Limit"/"Stop", tradeId, side, size, price
        ot = _order_type_raw(data.get("type"))
        sd, sd_raw = _side(data.get("side"))
        signal_id = data.get("entryId") if data.get("status") == "closed" and data.get("entryId") else data.get("tradeId")
        return {
            "symbol":         data.get("symbol"),
            "side":           sd,
            "order_type":     _order_type_label(ot),
            "quantity":       float(data.get("size", 0)),
            "price":          float(data.get("price", 0)),
            "signal_id":      signal_id,
            "timestamp":      int(data.get("timestamp", 0)),
            "event_type":     0,
            "order_type_raw": ot,
            "side_raw":       sd_raw,
        }

    if etype == "order":
        # OrderEventDto (camelCase): orderType, triggerPrice, orderId, side, size
        ot = _order_type_raw(data.get("orderType"))
        sd, sd_raw = _side(data.get("side"))
        return {
            "symbol":         data.get("symbol"),
            "side":           sd,
            "order_type":     _order_type_label(ot),
            "quantity":       float(data.get("size", 0)),
            "price":          float(data.get("triggerPrice") or 0),
            "signal_id":      data.get("orderId"),
            "timestamp":      int(data.get("timestamp", 0)),
            "event_type":     1,
            "order_type_raw": ot,
            "side_raw":       sd_raw,
        }

    if etype == "alert":
        # WatchAlert: no side/orderType by default — fields are optional user extensions
        ot = _order_type_raw(data.get("orderType") or data.get("order_type", "Market"))
        sd, sd_raw = _side(data.get("side", "buy"))
        return {
            "symbol":         data.get("symbol", "global"),
            "side":           sd,
            "order_type":     _order_type_label(ot),
            "quantity":       float(data.get("size", 0)),
            "price":          float(data.get("price", 0)),
            "signal_id":      data.get("id"),
            "timestamp":      int(data.get("timestamp", 0)),
            "event_type":     2,
            "order_type_raw": ot,
            "side_raw":       sd_raw,
        }

    return None


async def main():
    config_file = os.getenv("TICKENGINE_CONFIG_FILE", "config.json")
    print(f"Loading config from: {config_file}")
    with open(config_file, "r") as f:
        config = json.load(f)

    agents = []
    for agent_name, agent_cfg in config.get("agents", {}).items():
        atype      = agent_cfg.get("type")
        symbol_map = agent_cfg.get("symbol_map", {})

        if atype == "mt5_ea":
            try:
                agent = Mt5Agent(agent_name, symbol_map, agent_cfg.get("tcp_bind"))
                await agent.start()
                agents.append(agent)
            except Exception as e:
                print(f"Failed to initialize MT5 Agent '{agent_name}': {e}")
        elif atype == "binance_spot":
            agents.append(BinanceAgent(
                name=agent_name, symbol_map=symbol_map,
                api_key=agent_cfg.get("api_key"), api_secret=agent_cfg.get("api_secret"),
                api_url=agent_cfg.get("api_url", "https://api.binance.com"),
            ))
        elif atype == "okx_spot":
            agents.append(OkxAgent(
                name=agent_name, symbol_map=symbol_map,
                api_key=agent_cfg.get("api_key"), api_secret=agent_cfg.get("api_secret"),
                passphrase=agent_cfg.get("passphrase"),
                api_url=agent_cfg.get("api_url", "https://www.okx.com"),
            ))

    client = TickEngineClient(
        base_url=config["stream"]["url"],
        api_key=config["stream"]["api_key"],
        account_id=config["stream"]["account_id"],
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
