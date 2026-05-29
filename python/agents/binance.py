import hmac
import hashlib
import urllib.request
import urllib.error
import asyncio
from datetime import datetime
from .base import ExecutionAgent

def sign_hmac_sha256(secret: str, data: str) -> str:
    mac = hmac.new(secret.encode('utf-8'), data.encode('utf-8'), digestmod=hashlib.sha256)
    return mac.hexdigest()

class BinanceAgent(ExecutionAgent):
    def __init__(self, name: str, symbol_map: dict, api_key: str, api_secret: str, api_url: str):
        super().__init__(name, symbol_map)
        self.api_key = api_key
        self.api_secret = api_secret
        self.api_url = api_url

    async def execute(self, event: dict, details: dict) -> None:
        if details["quantity"] <= 0:
            return
            
        resolved_symbol = self.symbol_map[details["symbol"]]
        timestamp = int(datetime.utcnow().timestamp() * 1000)
        
        query_params = f"symbol={resolved_symbol}&side={details['side']}&type={details['order_type'].upper()}&quantity={details['quantity']}&timestamp={timestamp}"
        
        if details['order_type'].upper() == "LIMIT":
            price = details.get("price")
            if price is not None:
                query_params += f"&price={price}&timeInForce=GTC"
            else:
                print(f"Error [Binance Agent '{self.name}']: Price required for LIMIT orders")
                return
                
        signature = sign_hmac_sha256(self.api_secret, query_params)
        url = f"{self.api_url}/api/v3/order?{query_params}&signature={signature}"
        
        req = urllib.request.Request(url, method="POST")
        req.add_header("X-MBX-APIKEY", self.api_key)
        
        print(f"Placing Binance order via Agent '{self.name}': {details['side']} {resolved_symbol} (qty: {details['quantity']})")
        
        try:
            loop = asyncio.get_running_loop()
            await loop.run_in_executor(None, self._send_request, req)
        except Exception as e:
            print(f"Binance Connection Error in Agent '{self.name}': {e}")

    def _send_request(self, req):
        try:
            with urllib.request.urlopen(req) as response:
                body = response.read().decode('utf-8')
                print(f"Binance Order via Agent '{self.name}' Succeeded: {body}")
        except urllib.error.HTTPError as e:
            print(f"Binance Order via Agent '{self.name}' Failed: {e.code} - {e.read().decode('utf-8')}")
        except Exception as e:
            print(f"Binance Connection Error via Agent '{self.name}': {e}")
