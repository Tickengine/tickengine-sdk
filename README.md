# TickEngine Clients & MetaTrader 5 Expert Advisor Integration SDK

Welcome to the official, ultra-low latency integration SDK for **TickEngine**. 

This repository provides highly optimized client libraries in multiple programming languages to consume real-time MessagePack binary events from the TickEngine stream and execute them instantly in MetaTrader 5 using raw C-compatible memory-cast packed structures over TCP.

---

## ⚡ High-Speed Recommendation
For production algorithmic trading, **we strongly recommend using the Rust Client (`tickbridge`)** located in the `rust/` directory.
* **Why**: The Rust client operates natively on MessagePack binary frames and packed structs. It has zero garbage collection overhead and provides microsecond-level serialization, resulting in the lowest execution latency and jitter for your MetaTrader EA.
* **Setup Guide**: Go to the [Rust Client Guide](file:///Users/dongnguyen/Projects/TickNexus/tickengine-sdk/rust/README.md) to install Rust and build the high-speed production binary.

---

## 📈 Step 1: Install and Configure the MetaTrader 5 EA
The MetaTrader 5 Expert Advisor script `TickBridgeListener.mq5` resides under `metatrader/mql5/`. It acts as a TCP client listener, receiving 79-byte binary structures, deduplicating them using UUID caches, and placing trades instantly.

### Installation Instructions:
1. Open your **MetaTrader 5 terminal**.
2. Go to **File** -> **Open Data Folder**.
3. Navigate to `MQL5` -> `Experts` and paste the file `TickBridgeListener.mq5` inside this folder (or create a sub-folder).
4. Double-click the file to open it in **MetaEditor**, then click **Compile** in the top toolbar. Ensure there are zero errors.
5. In your MetaTrader 5 Navigator pane, expand the **Expert Advisors** list, find `TickBridgeListener`, and drag it onto your target chart.

### Crucial Expert Advisor Configuration:
For the EA to place trades automatically:
1. In the EA input settings dialog:
   * **InpTcpHost**: Address of the client bridge (default: `"127.0.0.1"`).
   * **InpTcpPort**: Port of the client bridge (default: `5555`).
   * **InpMaxSlippage**: Maximum allowed slippage deviation in points (default: `30` points/pipettes).
   * **InpMaxRetries**: Re-attempts for order execution if server returns requote (default: `3`).
2. Go to **Tools** -> **Options** -> **Expert Advisors**:
   * Check **"Allow algorithmic trading"**.

---

## 📂 Language-Specific Client Guides

Click the links below to view detailed configuration, installation, and run instructions for each language:

* 🦀 **[Rust Client Guide (`tickbridge`)](file:///Users/dongnguyen/Projects/TickNexus/tickengine-sdk/rust/README.md) (Recommended)**
* 🟢 **[Node.js / TypeScript Client Guide](file:///Users/dongnguyen/Projects/TickNexus/tickengine-sdk/nodejs/README.md)**
* 🐍 **[Python Client Guide](file:///Users/dongnguyen/Projects/TickNexus/tickengine-sdk/python/README.md)**
* 📈 **[MetaTrader 5 EA Reference Guide](file:///Users/dongnguyen/Projects/TickNexus/tickengine-sdk/metatrader/README.md)**
