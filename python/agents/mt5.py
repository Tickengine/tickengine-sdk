import asyncio
import struct
import uuid
from .base import ExecutionAgent


class Mt5Agent(ExecutionAgent):
    def __init__(self, name: str, symbol_map: dict, tcp_bind: str):
        super().__init__(name, symbol_map)
        self._tcp_bind = tcp_bind
        self._writers: list[asyncio.StreamWriter] = []

    async def start(self) -> None:
        """Start the TCP server. Call once before the main event loop."""
        host, port = _parse_tcp_addr(self._tcp_bind)
        server = await asyncio.start_server(self._handle_client, host, port)
        print(f"MT5 TCP server for agent '{self.name}' listening on {host}:{port}")
        # Keep server running in background — no need to await
        asyncio.get_event_loop().create_task(server.serve_forever())

    async def _handle_client(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        peer = writer.get_extra_info("peername")
        print(f"MT5 agent '{self.name}': new EA connection from {peer}")
        self._writers.append(writer)
        try:
            # Keep connection open; client just receives — it never sends data back
            await reader.read(-1)
        except Exception:
            pass
        finally:
            self._writers.remove(writer)
            writer.close()
            print(f"MT5 agent '{self.name}': EA disconnected ({peer})")

    async def execute(self, event: dict, details: dict) -> None:
        resolved_symbol = self.symbol_map[details["symbol"]]
        payload = _pack_mql_signal(
            magic=0x5449434B,
            event_type=details["event_type"],
            order_type=details["order_type_raw"],
            symbol=resolved_symbol,
            side=details["side_raw"],
            size=details["quantity"],
            price=details["price"],
            timestamp=details["timestamp"],
            signal_id=details["signal_id"],
        )
        print(
            f"Broadcasting to MT5 agent '{self.name}' → {resolved_symbol} "
            f"({len(payload)} bytes, {len(self._writers)} connected clients)"
        )
        dead: list[asyncio.StreamWriter] = []
        for writer in list(self._writers):
            try:
                writer.write(payload)
                await writer.drain()
            except Exception as e:
                print(f"MT5 agent '{self.name}': write error, dropping client: {e}")
                dead.append(writer)
        for w in dead:
            if w in self._writers:
                self._writers.remove(w)
            try:
                w.close()
            except Exception:
                pass


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _parse_tcp_addr(raw: str) -> tuple[str, int]:
    """
    Parses tcp_bind strings into (host, port).
    Supports:
      "tcp://*:5555"        → ("0.0.0.0", 5555)
      "tcp://0.0.0.0:5555"  → ("0.0.0.0", 5555)
      "tcp://localhost:5555" → ("localhost", 5555)
      "0.0.0.0:5555"        → ("0.0.0.0", 5555)
    """
    addr = raw.removeprefix("tcp://").replace("*", "0.0.0.0")
    host, port_str = addr.rsplit(":", 1)
    return host, int(port_str)


def _pack_mql_signal(
    magic: int,
    event_type: int,
    order_type: int,
    symbol: str,
    side: int,
    size: float,
    price: float,
    timestamp: int,
    signal_id: str,
) -> bytes:
    """
    Packs trade signals into a 79-byte C-struct matching MqlTradeSignal.
    Layout (little-endian):
      I   uint32  4 bytes  offset 0   magic
      B   uint8   1 byte   offset 4   event_type
      B   uint8   1 byte   offset 5   order_type
      B   uint8   1 byte   offset 6   side
      32s char[]  32 bytes offset 7   symbol (null-padded)
      16s char[]  16 bytes offset 39  signal_id (UUID bytes)
      d   double  8 bytes  offset 55  size
      d   double  8 bytes  offset 63  price
      q   int64   8 bytes  offset 71  timestamp
    Total = 79 bytes
    """
    symbol_bytes = symbol.encode("utf-8")[:31].ljust(32, b"\x00")
    try:
        signal_id_bytes = uuid.UUID(signal_id).bytes
    except Exception:
        signal_id_bytes = b"\x00" * 16

    return struct.pack(
        "<IBB32s16sddq",
        magic,
        event_type,
        order_type,
        side,
        symbol_bytes,
        signal_id_bytes,
        size,
        price,
        timestamp,
    )
