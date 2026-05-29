use crate::agents::{ExecutionAgent, MappedOrder};
use std::collections::HashMap;
use tickengine_sdk::ClientEvent;
use tracing::{error, info};

pub struct OkxAgent {
    name: String,
    client: reqwest::Client,
    api_key: String,
    api_secret: String,
    passphrase: String,
    api_url: String,
    symbol_map: HashMap<String, String>,
}

impl OkxAgent {
    pub fn new(
        name: &str,
        client: reqwest::Client,
        api_key: &str,
        api_secret: &str,
        passphrase: &str,
        api_url: &str,
        symbol_map: HashMap<String, String>,
    ) -> Self {
        Self {
            name: name.to_string(),
            client,
            api_key: api_key.to_string(),
            api_secret: api_secret.to_string(),
            passphrase: passphrase.to_string(),
            api_url: api_url.to_string(),
            symbol_map,
        }
    }
}

fn sign_hmac_sha256(secret: &str, data: &str) -> String {
    use hmac::{Hmac, Mac};
    use sha2::Sha256;
    type HmacSha256 = Hmac<Sha256>;

    let mut mac = HmacSha256::new_from_slice(secret.as_bytes()).expect("HMAC keys can be any size");
    mac.update(data.as_bytes());
    hex::encode(mac.finalize().into_bytes())
}

#[async_trait::async_trait]
impl ExecutionAgent for OkxAgent {
    fn name(&self) -> &str {
        &self.name
    }

    fn can_handle(&self, symbol: &str) -> bool {
        self.symbol_map.contains_key(symbol)
    }

    async fn execute(&mut self, _event: &ClientEvent, order: &MappedOrder) -> anyhow::Result<()> {
        let resolved_symbol = self
            .symbol_map
            .get(&order.symbol)
            .ok_or_else(|| anyhow::anyhow!("Symbol not mapped for OKX agent"))?;

        if order.quantity <= 0.0 {
            return Ok(());
        }

        let timestamp = chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true);
        let path = "/api/v5/trade/order";
        let url = format!("{}{}", self.api_url, path);

        let mut body_map = serde_json::Map::new();
        body_map.insert(
            "instId".to_string(),
            serde_json::Value::String(resolved_symbol.clone()),
        );
        body_map.insert(
            "tdMode".to_string(),
            serde_json::Value::String("cash".to_string()),
        );
        body_map.insert(
            "side".to_string(),
            serde_json::Value::String(order.side.to_lowercase()),
        );
        body_map.insert(
            "ordType".to_string(),
            serde_json::Value::String(order.order_type.to_lowercase()),
        );
        body_map.insert(
            "sz".to_string(),
            serde_json::Value::String(order.quantity.to_string()),
        );

        if order.order_type == "LIMIT" {
            if let Some(p) = order.price {
                body_map.insert("px".to_string(), serde_json::Value::String(p.to_string()));
            } else {
                return Err(anyhow::anyhow!("Price required for OKX LIMIT orders"));
            }
        }

        let body_str = serde_json::to_string(&serde_json::Value::Object(body_map))?;
        let sign_payload = format!("{}{}{}{}", timestamp, "POST", path, body_str);
        let signature = sign_hmac_sha256(&self.api_secret, &sign_payload);

        info!(
            "Placing OKX order via Agent '{}': {} {} (qty: {})",
            self.name, order.side, resolved_symbol, order.quantity
        );

        let res = self
            .client
            .post(&url)
            .header("OK-ACCESS-KEY", &self.api_key)
            .header("OK-ACCESS-SIGN", signature)
            .header("OK-ACCESS-TIMESTAMP", timestamp)
            .header("OK-ACCESS-PASSPHRASE", &self.passphrase)
            .header("Content-Type", "application/json")
            .body(body_str)
            .send()
            .await?;

        let status = res.status();
        let body = res.text().await?;

        if status.is_success() {
            info!("OKX Order via Agent '{}' Succeeded: {}", self.name, body);
        } else {
            error!(
                "OKX Order via Agent '{}' Failed (HTTP {}): {}",
                self.name, status, body
            );
        }

        Ok(())
    }
}
