pub mod binance;
pub mod mt5;
pub mod okx;

pub use binance::BinanceAgent;
pub use mt5::Mt5Agent;
pub use okx::OkxAgent;

#[derive(Debug, Clone)]
pub struct MappedOrder {
    pub symbol: String,
    pub side: String,
    pub order_type: String,
    pub quantity: f64,
    pub price: Option<f64>,
    pub signal_id: uuid::Uuid,
    pub timestamp: i64,
}

#[async_trait::async_trait]
pub trait ExecutionAgent: Send + Sync {
    fn name(&self) -> &str;
    fn can_handle(&self, symbol: &str) -> bool;
    async fn execute(
        &mut self,
        event: &tickengine_sdk::ClientEvent,
        order: &MappedOrder,
    ) -> anyhow::Result<()>;
}
