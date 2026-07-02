use crate::agents::{ExecutionAgent, MappedOrder};
use std::collections::HashMap;
use tickengine_sdk::{ClientEvent, OrderSide, OrderType};
use tokio::io::AsyncWriteExt;
use tokio::net::TcpListener;
use tokio::sync::broadcast;
use tracing::{error, info, warn};

/// Number of signals that can be queued per connected client before drops occur.
const CHANNEL_CAPACITY: usize = 256;

pub struct Mt5Agent {
    name: String,
    tx: broadcast::Sender<Vec<u8>>,
    symbol_map: HashMap<String, String>,
}

impl Mt5Agent {
    pub async fn new(
        name: &str,
        tcp_bind: &str,
        symbol_map: HashMap<String, String>,
    ) -> anyhow::Result<Self> {
        // Strip "tcp://*:" or "tcp://0.0.0.0:" prefix → keep just "0.0.0.0:PORT"
        let addr = parse_tcp_addr(tcp_bind)?;

        let listener = TcpListener::bind(&addr).await?;
        let (tx, _) = broadcast::channel::<Vec<u8>>(CHANNEL_CAPACITY);
        let tx_clone = tx.clone();
        let agent_name = name.to_string();

        info!(
            "MT5 TCP server for agent '{}' listening on {}",
            agent_name, addr
        );

        // Accept loop — runs forever in background
        tokio::spawn(async move {
            loop {
                match listener.accept().await {
                    Ok((stream, peer)) => {
                        info!(
                            "MT5 agent '{}': new EA connection from {}",
                            agent_name, peer
                        );
                        let mut rx = tx_clone.subscribe();
                        tokio::spawn(async move {
                            let (_, mut writer) = tokio::io::split(stream);
                            loop {
                                match rx.recv().await {
                                    Ok(payload) => {
                                        if let Err(e) = writer.write_all(&payload).await {
                                            warn!(
                                                "MT5 TCP write error (peer {}): {}. Dropping connection.",
                                                peer, e
                                            );
                                            break;
                                        }
                                    }
                                    Err(broadcast::error::RecvError::Lagged(n)) => {
                                        warn!("MT5 TCP client {} lagged by {} messages", peer, n);
                                    }
                                    Err(broadcast::error::RecvError::Closed) => {
                                        break;
                                    }
                                }
                            }
                        });
                    }
                    Err(e) => {
                        error!("MT5 TCP accept error: {}", e);
                    }
                }
            }
        });

        Ok(Self {
            name: name.to_string(),
            tx,
            symbol_map,
        })
    }
}

/// Parses ZMQ-style address strings into a standard TCP bind address.
/// Examples:
///   "tcp://*:5555"        → "0.0.0.0:5555"
///   "tcp://0.0.0.0:5555"  → "0.0.0.0:5555"
///   "tcp://localhost:5555" → "localhost:5555"
///   "0.0.0.0:5555"        → "0.0.0.0:5555"  (pass-through)
fn parse_tcp_addr(raw: &str) -> anyhow::Result<String> {
    let stripped = raw
        .strip_prefix("tcp://")
        .unwrap_or(raw)
        .replace("*:", "0.0.0.0:");
    if stripped.contains(':') {
        Ok(stripped)
    } else {
        anyhow::bail!("Invalid tcp_bind address '{}': must include a port", raw)
    }
}

fn mql_signal_to_bytes(signal: &tickengine_sdk::MqlTradeSignal) -> Vec<u8> {
    let size = std::mem::size_of::<tickengine_sdk::MqlTradeSignal>();
    let mut bytes = vec![0u8; size];
    unsafe {
        std::ptr::copy_nonoverlapping(
            signal as *const tickengine_sdk::MqlTradeSignal as *const u8,
            bytes.as_mut_ptr(),
            size,
        );
    }
    bytes
}

fn map_event_to_mql(
    event: &ClientEvent,
    resolved_symbol: &str,
    signal_id: uuid::Uuid,
    size: f64,
    price: f64,
    timestamp: i64,
) -> tickengine_sdk::MqlTradeSignal {
    let magic = 0x5449434B; // 'TICK'

    let mut symbol_bytes = [0u8; 32];
    let bytes = resolved_symbol.as_bytes();
    let len = std::cmp::min(bytes.len(), 31);
    symbol_bytes[..len].copy_from_slice(&bytes[..len]);

    let event_type = match event {
        ClientEvent::Trade(_) => 0,
        ClientEvent::Order(_) => 1,
        ClientEvent::Alert(_) => 2,
    };

    let order_type = match event {
        ClientEvent::Trade(e) => match e.type_ {
            OrderType::Market => 0,
            OrderType::Limit => 1,
            OrderType::Stop => 2,
        },
        ClientEvent::Order(e) => match e.order_type {
            OrderType::Market => 0,
            OrderType::Limit => 1,
            OrderType::Stop => 2,
        },
        ClientEvent::Alert(v) => match v["order_type"].as_str() {
            Some("market") | Some("Market") => 0,
            Some("limit") | Some("Limit") => 1,
            Some("stop") | Some("Stop") => 2,
            _ => 0,
        },
    };

    let side = match event {
        ClientEvent::Trade(e) => match e.side {
            OrderSide::Buy => 0,
            OrderSide::Sell => 1,
        },
        ClientEvent::Order(e) => match e.side {
            OrderSide::Buy => 0,
            OrderSide::Sell => 1,
        },
        ClientEvent::Alert(v) => match v["side"].as_str() {
            Some("buy") | Some("Buy") => 0,
            Some("sell") | Some("Sell") => 1,
            _ => 0,
        },
    };

    tickengine_sdk::MqlTradeSignal {
        magic,
        event_type,
        order_type,
        side,
        symbol: symbol_bytes,
        signal_id: *signal_id.as_bytes(),
        size,
        price,
        timestamp,
    }
}

#[async_trait::async_trait]
impl ExecutionAgent for Mt5Agent {
    fn name(&self) -> &str {
        &self.name
    }

    fn can_handle(&self, symbol: &str) -> bool {
        self.symbol_map.contains_key(symbol)
    }

    async fn execute(&mut self, event: &ClientEvent, order: &MappedOrder) -> anyhow::Result<()> {
        let resolved_symbol = self
            .symbol_map
            .get(&order.symbol)
            .ok_or_else(|| anyhow::anyhow!("Symbol not mapped for MT5 agent"))?;

        let signal = map_event_to_mql(
            event,
            resolved_symbol,
            order.signal_id,
            order.quantity,
            order.price.unwrap_or(0.0),
            order.timestamp,
        );
        let payload = mql_signal_to_bytes(&signal);

        info!(
            "Broadcasting to MT5 agent '{}' → {} ({} bytes, {} connected clients)",
            self.name,
            resolved_symbol,
            payload.len(),
            self.tx.receiver_count()
        );

        // send() only errors when there are zero receivers — that's fine, signals will
        // be delivered once an EA connects. We ignore the error intentionally.
        let _ = self.tx.send(payload);
        Ok(())
    }
}
