mod agents;
mod config;

use agents::{BinanceAgent, ExecutionAgent, MappedOrder, Mt5Agent, OkxAgent};
use anyhow::Result;
use config::{AgentConfig, Config};
use futures::StreamExt;
use rust_decimal::prelude::ToPrimitive;
use std::time::Duration;
use tickengine_sdk::{ClientEvent, EventsClient, OrderSide, OrderType};
use tracing::{error, info, warn};

fn extract_order_details(event: &ClientEvent) -> Option<MappedOrder> {
    match event {
        ClientEvent::Trade(e) => {
            let side = match e.side {
                OrderSide::Buy => "BUY".to_string(),
                OrderSide::Sell => "SELL".to_string(),
            };
            let order_type = match e.type_ {
                OrderType::Market => "MARKET".to_string(),
                OrderType::Limit => "LIMIT".to_string(),
                OrderType::Stop => "LIMIT".to_string(),
            };
            Some(MappedOrder {
                symbol: e.symbol.clone(),
                side,
                order_type,
                quantity: e.size.to_f64().unwrap_or(0.0),
                price: e.price.to_f64(),
                signal_id: e.trade_id,
                timestamp: e.timestamp,
            })
        }
        ClientEvent::Order(e) => {
            let side = match e.side {
                OrderSide::Buy => "BUY".to_string(),
                OrderSide::Sell => "SELL".to_string(),
            };
            let order_type = match e.order_type {
                OrderType::Market => "MARKET".to_string(),
                OrderType::Limit => "LIMIT".to_string(),
                OrderType::Stop => "LIMIT".to_string(),
            };
            Some(MappedOrder {
                symbol: e.symbol.clone(),
                side,
                order_type,
                quantity: e.size.to_f64().unwrap_or(0.0),
                price: e.trigger_price.and_then(|p| p.to_f64()),
                signal_id: e.order_id,
                timestamp: e.timestamp,
            })
        }
        ClientEvent::Alert(v) => {
            let symbol = v["symbol"].as_str().unwrap_or("global").to_string();
            let side = match v["side"].as_str() {
                Some("buy") | Some("Buy") => "BUY".to_string(),
                Some("sell") | Some("Sell") => "SELL".to_string(),
                _ => "BUY".to_string(),
            };
            let order_type = match v["order_type"].as_str() {
                Some("limit") | Some("Limit") => "LIMIT".to_string(),
                _ => "MARKET".to_string(),
            };
            let signal_id = v["id"]
                .as_str()
                .and_then(|s| uuid::Uuid::parse_str(s).ok())
                .unwrap_or_else(uuid::Uuid::new_v4);
            Some(MappedOrder {
                symbol,
                side,
                order_type,
                quantity: v["size"].as_f64().unwrap_or(0.0),
                price: v["price"].as_f64(),
                signal_id,
                timestamp: v["timestamp"].as_i64().unwrap_or(0),
            })
        }
        ClientEvent::Metric(e) => Some(MappedOrder {
            symbol: e.account_id.to_string(),
            side: "BUY".to_string(),
            order_type: "MARKET".to_string(),
            quantity: e.equity.to_f64().unwrap_or(0.0),
            price: e.balance.to_f64(),
            signal_id: e.account_id,
            timestamp: e.timestamp,
        }),
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();

    let config_file =
        std::env::var("TICKENGINE_CONFIG_FILE").unwrap_or_else(|_| "config.json".to_string());

    info!("Loading config from: {}", config_file);
    let config = Config::load_from_file(&config_file)?;

    let http_client = reqwest::Client::new();

    // 1. Initialize trait-based execution agents dynamically
    let mut agents: Vec<Box<dyn ExecutionAgent>> = Vec::new();
    for (name, agent_cfg) in config.agents {
        match agent_cfg {
            AgentConfig::Mt5 {
                zmq_bind,
                symbol_map,
            } => {
                let agent = Mt5Agent::new(&name, &zmq_bind, symbol_map).await?;
                agents.push(Box::new(agent));
            }
            AgentConfig::Binance {
                api_key,
                api_secret,
                api_url,
                symbol_map,
            } => {
                let agent = BinanceAgent::new(
                    &name,
                    http_client.clone(),
                    &api_key,
                    &api_secret,
                    &api_url,
                    symbol_map,
                );
                agents.push(Box::new(agent));
            }
            AgentConfig::Okx {
                api_key,
                api_secret,
                passphrase,
                api_url,
                symbol_map,
            } => {
                let agent = OkxAgent::new(
                    &name,
                    http_client.clone(),
                    &api_key,
                    &api_secret,
                    &passphrase,
                    &api_url,
                    symbol_map,
                );
                agents.push(Box::new(agent));
            }
        }
    }

    // 2. Main Bridge Loop with Auto-Reconnect
    let mut retry_delay = Duration::from_secs(1);
    let max_retry_delay = Duration::from_secs(60);

    loop {
        info!("Connecting to TickEngine Stream...");
        let client = match EventsClient::new(
            &config.stream.url,
            &config.stream.api_key,
            &config.stream.account_id,
        ) {
            Ok(c) => c,
            Err(e) => {
                error!(
                    "Failed to initialize client: {}. Retrying in {:?}...",
                    e, retry_delay
                );
                tokio::time::sleep(retry_delay).await;
                retry_delay = std::cmp::min(retry_delay * 2, max_retry_delay);
                continue;
            }
        };

        let event_stream_res = client.stream().await;
        let mut event_stream = match event_stream_res {
            Ok(s) => Box::pin(s),
            Err(e) => {
                error!(
                    "Failed to connect to stream: {}. Retrying in {:?}...",
                    e, retry_delay
                );
                tokio::time::sleep(retry_delay).await;
                retry_delay = std::cmp::min(retry_delay * 2, max_retry_delay);
                continue;
            }
        };

        info!("Connected! Waiting for signals...");
        retry_delay = Duration::from_secs(1);

        while let Some(res) = event_stream.next().await {
            match res {
                Ok(event) => {
                    let order = match extract_order_details(&event) {
                        Some(o) => o,
                        None => continue,
                    };

                    // Route order dynamically to all matching trait objects
                    for agent in &mut agents {
                        if agent.can_handle(&order.symbol) {
                            let res = agent.execute(&event, &order).await;
                            if let Err(e) = res {
                                error!("Agent '{}' execution error: {}", agent.name(), e);
                            }
                        }
                    }
                }
                Err(e) => {
                    warn!("Stream error: {}. Reconnecting...", e);
                    break;
                }
            }
        }

        error!("Stream disconnected. Retrying in {:?}...", retry_delay);
        tokio::time::sleep(retry_delay).await;
        retry_delay = std::cmp::min(retry_delay * 2, max_retry_delay);
    }
}
