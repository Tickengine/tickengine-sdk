import hmac
import hashlib
import json
import urllib.request
import urllib.error
import asyncio
from datetime import datetime
from .base import ExecutionAgent

def sign_hmac_sha256(secret: str, data: str) -> str:
    mac = hmac.new(secret.encode('utf-8'), data.encode('utf-8'), digestmod=hashlib.sha256)
    return mac.hexdigest()

class OkxAgent(ExecutionAgent):
    def __init__(self, name: str, symbol_map: dict, api_key: str, api_secret: str, passphrase: str, api_url: str):
        super().__init__(name, symbol_map)
        self.api_key = api_key
        self.api_secret = api_secret
        self.passphrase = passphrase
        self.api_url = api_url

    async def execute(self, event: dict, details: dict) -> None:
        if details["quantity"] <= 0:
            return
            
        resolved_symbol = self.symbol_map[details["symbol"]]
        timestamp = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
        path = "/api/v5/trade/order"
        url = f"{self.api_url}{path}"
        
        body_data = {
            "instId": resolved_symbol,
            "tdMode": "cash",
            "side": details["side"].lower(),
            "ordType": details["order_type"].lower(),
            "sz": str(details["quantity"])
        }
        if details["order_type"].upper() == "LIMIT":
            price = details.get("price")
            if price is not None:
                body_data["px"] = str(price)
            else:
                print(f"Error [OKX Agent '{self.name}']: Price required for LIMIT orders")
                return
                
        body_str = json.dumps(body_data)
        sign_payload = f"{timestamp}POST{path}{body_str}"
        signature = sign_hmac_sha256(self.api_secret, sign_payload)
        
        req = urllib.request.Request(url, data=body_str.encode('utf-8'), method="POST")
        req.add_header("OK-ACCESS-KEY", self.api_key)
        req.add_header("OK-ACCESS-SIGN", signature)
        req.add_header("OK-ACCESS-TIMESTAMP", timestamp)
        req.add_header("OK-ACCESS-PASSPHRASE", self.passphrase)
        req.add_header("Content-Type", "application/json")
        
        print(f"Placing OKX order via Agent '{self.name}': {details['side']} {resolved_symbol} (qty: {details['quantity']})")
        
        try:
            loop = asyncio.get_running_loop()
            await loop.run_in_executor(None, self._send_request, req)
        except Exception as e:
            print(f"OKX Connection Error in Agent '{self.name}': {e}")

    def _send_request(self, req):
        try:
            with urllib.request.urlopen(req) as response:
                body = response.read().decode('utf-8')
                print(f"OKX Order via Agent '{self.name}' Succeeded: {body}")
        except urllib.error.HTTPError as e:
            print(f"OKX Order via Agent '{self.name}' Failed: {e.code} - {e.read().decode('utf-8')}")
        except Exception as e:
            print(f"OKX Connection Error via Agent '{self.name}': {e}")
