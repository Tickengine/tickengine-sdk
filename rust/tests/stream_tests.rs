use futures::{SinkExt, StreamExt};
use rust_decimal::Decimal;
use std::str::FromStr;
use tickengine_sdk::{
    ClientEvent, EventsClient, OrderSide, OrderStatus, OrderType, TradeExecutedEvent,
};
use tokio::net::TcpListener;
use tokio_tungstenite::accept_async;
use tokio_tungstenite::tungstenite::protocol::Message;
use uuid::Uuid;

#[tokio::test]
async fn test_stream_data_parsing() {
    // 1. Spawn a local ephemeral WebSocket server
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let server_url = format!("ws://127.0.0.1:{}", port);

    // 2. Mock payload: ClientEvent::Trade
    let trade_event = ClientEvent::Trade(TradeExecutedEvent {
        trade_id: Uuid::new_v4(),
        account_id: Uuid::new_v4(),
        strategy_id: Uuid::new_v4(),
        symbol: "BTCUSDT".to_string(),
        side: OrderSide::Buy,
        size: Decimal::from_str("1.5").unwrap(),
        price: Decimal::from_str("95000.0").unwrap(),
        timestamp: 1625097600000,
        entry_price: None,
        entry_time: None,
        type_: OrderType::Market,
        status: OrderStatus::Filled,
        pnl: None,
        commission: None,
        entry_id: None,
        exit_id: None,
        is_backtest: false,
        strategy: None,
    });

    let binary_payload = rmp_serde::to_vec(&trade_event).unwrap();

    // 3. Handle connection in background
    tokio::spawn(async move {
        let (stream, _) = listener.accept().await.unwrap();
        let mut ws_stream = accept_async(stream).await.unwrap();

        // Send binary MessagePack payload to the connected client
        ws_stream
            .send(Message::Binary(binary_payload.into()))
            .await
            .unwrap();
        ws_stream.close(None).await.unwrap();
    });

    // 4. Client connects and streams
    let client = EventsClient::new(&server_url, "test_key", "test_acc").unwrap();
    let stream = client.stream().await.unwrap();
    tokio::pin!(stream);

    if let Some(result) = stream.next().await {
        let event = result.unwrap();
        match event {
            ClientEvent::Trade(trade) => {
                assert_eq!(trade.symbol, "BTCUSDT");
                assert_eq!(trade.side, OrderSide::Buy);
                assert_eq!(trade.size, Decimal::from_str("1.5").unwrap());
                assert_eq!(trade.price, Decimal::from_str("95000.0").unwrap());
            }
            _ => panic!("Expected Trade Event"),
        }
    } else {
        panic!("Stream ended prematurely");
    }
}
