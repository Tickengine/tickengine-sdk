# 📈 MetaTrader 5 Expert Advisor (EA) Reference Guide

The MetaTrader 5 Expert Advisor `TickBridgeListener.mq5` acts as the execution terminal in this automated binary data pipeline. It binds to the client ZeroMQ publisher socket, accepts raw binary packed structures, deduplicates signals, and places trades instantly.

---

## ⚙️ EA Input Configurations

When dragging the `TickBridgeListener` onto your MetaTrader 5 chart, you can configure the following parameters in the **Inputs** tab:

| Parameter | Type | Default Value | Description |
| :--- | :---: | :---: | :--- |
| **InpZmqAddress** | `string` | `tcp://localhost:5555` | The socket address of the client bridge running locally or in your network. |
| **InpMaxSlippage** | `uint` | `30` | The maximum allowed price deviation in points/pipettes. Prevents executions during extreme spreads. |
| **InpMaxRetries** | `uint` | `3` | Maximum re-attempts to send a trade order if the server returns a temporary requote or failure. |
| **InpRetryDelayMs** | `uint` | `200` | Backoff delay multiplier in milliseconds. Delay between retries will be `InpRetryDelayMs * retry_count`. |
| **InpEAMagic** | `uint` | `999123` | The Magic Identifier assigned to the orders. Useful for tracking trades placed specifically by this EA. |

---

## 🚀 Key Architectural Guards

### 1. ZeroMQ Wildcard Subscription
The EA subscribes to the empty string wildcard (`subSocket.subscribe("")`). This allows it to receive **all** published trade signals and alerts from the broker regardless of their ZeroMQ topic (e.g. `trade.EURUSD`, `alert.GBPUSD`, etc.). 

The EA reads the resolved `symbol` field directly inside the received 79-byte structure to determine what chart/instrument to place the trade on, making your automated execution 100% dynamic.

### 2. Native Automated Order Routing (Market/Limit/Stop)
The EA decodes the binary parameters and maps them directly to native MetaTrader trade requests (`ORDER_TYPE_BUY`, `ORDER_TYPE_SELL_LIMIT`, etc.) and executes using native `OrderSend()`.

For market orders, the Bid/Ask price is refreshed dynamically inside the retry loop to avoid "invalid price" rejections during volatile market conditions.

### 3. Signal Deduplication (UUID Cache)
The EA maintains an in-memory sliding history cache of recently processed signal UUIDs:
1. When a new 79-byte payload arrives, the EA immediately extracts the 16-byte `signal_id` and formats it as a string.
2. If the UUID is already present in the history list, the signal is **discarded immediately**, ensuring a signal is never double-executed.
3. This protects you against network packet duplications or bridge restarts.
