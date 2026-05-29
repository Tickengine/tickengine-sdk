import zmq
from tickengine_sdk import pack_mql_signal
from .base import ExecutionAgent

class Mt5Agent(ExecutionAgent):
    def __init__(self, name: str, symbol_map: dict, zmq_bind: str, zmq_context: zmq.Context = None):
        super().__init__(name, symbol_map)
        context = zmq_context or zmq.Context.instance()
        self.pub_socket = context.socket(zmq.PUB)
        self.pub_socket.bind(zmq_bind)
        print(f"ZeroMQ PUB socket for agent '{name}' bound to {zmq_bind}")

    async def execute(self, event: dict, details: dict) -> None:
        resolved_symbol = self.symbol_map[details["symbol"]]
        payload = pack_mql_signal(
            magic=0x5449434B,
            event_type=details["event_type"],
            order_type=details["order_type_raw"],
            symbol=resolved_symbol,
            side=details["side_raw"],
            size=details["quantity"],
            price=details["price"],
            timestamp=details["timestamp"],
            signal_id=details["signal_id"]
        )
        event_name = event.get("type", "trade")
        topic = f"{event_name}.{resolved_symbol}"
        print(f"Publishing to MT5 Agent '{self.name}': {topic} ({len(payload)} bytes)")
        # Run ZeroMQ blocking sends in standard mode
        self.pub_socket.send_multipart([topic.encode('utf-8'), payload])
