use crate::agents::{ExecutionAgent, MappedOrder};
use std::collections::HashMap;
use tickengine_sdk::ClientEvent;
use tracing::{error, info};

pub struct BinanceAgent {
    name: String,
    client: reqwest::Client,
    api_key: String,
    api_secret: String,
    api_url: String,
    symbol_map: HashMap<String, String>,
}

impl BinanceAgent {
    pub fn new(
        name: &str,
        client: reqwest::Client,
        api_key: &str,
        api_secret: &str,
        api_url: &str,
        symbol_map: HashMap<String, String>,
    ) -> Self {
        Self {
            name: name.to_string(),
            client,
            api_key: api_key.to_string(),
            api_secret: api_secret.to_string(),
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
impl ExecutionAgent for BinanceAgent {
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
            .ok_or_else(|| anyhow::anyhow!("Symbol not mapped for Binance agent"))?;

        if order.quantity <= 0.0 {
            return Ok(());
        }

        let timestamp = chrono::Utc::now().timestamp_millis();

        let mut query_params = format!(
            "symbol={}&side={}&type={}&quantity={}&timestamp={}",
            resolved_symbol, order.side, order.order_type, order.quantity, timestamp
        );

        if order.order_type == "LIMIT" {
            if let Some(p) = order.price {
                query_params = format!("{}&price={}&timeInForce=GTC", query_params, p);
            } else {
                return Err(anyhow::anyhow!("Price required for LIMIT orders"));
            }
        }

        let signature = sign_hmac_sha256(&self.api_secret, &query_params);
        let url = format!(
            "{}/api/v3/order?{}&signature={}",
            self.api_url, query_params, signature
        );

        info!(
            "Placing Binance order via Agent '{}': {} {} (qty: {})",
            self.name, order.side, resolved_symbol, order.quantity
        );

        let res = self
            .client
            .post(&url)
            .header("X-MBX-APIKEY", &self.api_key)
            .send()
            .await?;

        let status = res.status();
        let body = res.text().await?;

        if status.is_success() {
            info!(
                "Binance Order via Agent '{}' Succeeded: {}",
                self.name, body
            );
        } else {
            error!(
                "Binance Order via Agent '{}' Failed (HTTP {}): {}",
                self.name, status, body
            );
        }

        Ok(())
    }
}
