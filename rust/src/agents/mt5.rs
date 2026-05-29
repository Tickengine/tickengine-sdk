use crate::agents::{ExecutionAgent, MappedOrder};
use std::collections::HashMap;
use tickengine_sdk::{ClientEvent, OrderSide, OrderType};
use tracing::info;
use zeromq::{PubSocket, Socket, SocketSend, ZmqMessage};

pub struct Mt5Agent {
    name: String,
    pub_socket: PubSocket,
    symbol_map: HashMap<String, String>,
}

impl Mt5Agent {
    pub async fn new(
        name: &str,
        zmq_bind: &str,
        symbol_map: HashMap<String, String>,
    ) -> anyhow::Result<Self> {
        let mut pub_socket = PubSocket::new();
        pub_socket.bind(zmq_bind).await?;
        Ok(Self {
            name: name.to_string(),
            pub_socket,
            symbol_map,
        })
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
        ClientEvent::Metric(_) => 3,
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
        ClientEvent::Metric(_) => 0,
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
        ClientEvent::Metric(_) => 0,
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

        let topic = match event {
            ClientEvent::Trade(_) => format!("trade.{}", resolved_symbol),
            ClientEvent::Order(_) => format!("order.{}", resolved_symbol),
            ClientEvent::Alert(_) => format!("alert.{}", resolved_symbol),
            ClientEvent::Metric(_) => format!("metric.{}", resolved_symbol),
        };

        info!(
            "Publishing to MT5 Agent '{}': {} ({} bytes)",
            self.name,
            topic,
            payload.len()
        );
        let mut msg = ZmqMessage::from(topic);
        msg.push_back(payload.into());
        self.pub_socket.send(msg).await?;
        Ok(())
    }
}
