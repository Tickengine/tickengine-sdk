import asyncio
import struct
import websockets
import msgpack
import uuid
from typing import AsyncGenerator

class TickEngineClient:
    def __init__(self, base_url: str, api_key: str, account_id: str):
        # Ensure base_url uses ws/wss
        ws_url = base_url.replace("http://", "ws://").replace("https://", "wss://")
        if "/stream" in ws_url:
            ws_url = ws_url.replace("/stream", "/stream/ws")
        elif not ws_url.endswith("/ws"):
             ws_url = f"{ws_url}/ws"
             
        self.url = f"{ws_url}?api_key={api_key}&account_id={account_id}"
        self.api_key = api_key

    async def stream_events(self) -> AsyncGenerator[dict, None]:
        retry_delay = 1
        while True:
            try:
                async with websockets.connect(self.url) as websocket:
                    retry_delay = 1 # Reset on success
                    while True:
                        try:
                            # Receive high-performance MessagePack binary frame
                            message = await websocket.recv()
                            yield msgpack.unpackb(message, raw=False)
                        except websockets.ConnectionClosed:
                            break
            except Exception as e:
                print(f"WebSocket error: {e}. Retrying in {retry_delay}s...")
                await asyncio.sleep(retry_delay)
                retry_delay = min(retry_delay * 2, 60)

def pack_mql_signal(
    magic: int,          # uint32 (e.g. 0x5449434B / 'TICK')
    event_type: int,     # uint8  (0=Trade, 1=Order, 2=Alert, 3=Metric)
    order_type: int,     # uint8  (0=Market, 1=Limit, 2=Stop)
    symbol: str,         # char[32] (fixed size null-padded)
    side: int,           # uint8  (0=Buy, 1=Sell)
    size: float,         # double (8 bytes)
    price: float,        # double (8 bytes)
    timestamp: int,      # int64  (8 bytes)
    signal_id: str,      # hex or standard UUID string
    symbol_map: dict = None # optional symbol map dictionary
) -> bytes:
    """
    Packs trade signals into a 79-byte raw packed C-struct matching MqlTradeSignal perfectly.
    Layout definition: Little-Endian (<)
    I   = uint32 (4 bytes)   (offset 0)
    B   = uint8  (1 byte)    (offset 4)
    B   = uint8  (1 byte)    (offset 5)
    B   = uint8  (1 byte)    (offset 6)
    32s = char[32] (32 bytes) (offset 7)
    16s = char[16] (16 bytes) (offset 39)
    d   = double (8 bytes)   (offset 55)
    d   = double (8 bytes)   (offset 63)
    q   = int64  (8 bytes)   (offset 71)
    Total = 79 bytes.
    """
    resolved_symbol = symbol_map.get(symbol, symbol) if symbol_map else symbol
    symbol_bytes = resolved_symbol.encode('utf-8')[:31].ljust(32, b'\x00')
    
    # Parse signal_id UUID into 16-byte buffer
    try:
        signal_id_bytes = uuid.UUID(signal_id).bytes
    except Exception:
        # Fallback to zero-filled 16 bytes
        signal_id_bytes = b'\x00' * 16

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
        timestamp
    )
