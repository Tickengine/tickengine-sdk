# 🦀 Rust High-Speed Client Bridge (`tickbridge`)

The Rust Client is the **highly recommended** entry point for production trading setups. It connects to the TickEngine WebSocket stream, decodes binary MessagePack payloads, performs dynamic local symbol mapping, and publishes raw 79-byte packed C-struct signals to MetaTrader 5 via ZeroMQ.

---

## 🚀 Step 1: Install Rust Natively
To compile and run `tickbridge` with maximum optimizations, you must install the Rust toolchain:

### macOS / Linux
Install Rust via `rustup` by running:
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```
Follow the on-screen prompts (choose default installation). Once complete, restart your shell or run:
```bash
source "$HOME/.cargo/env"
```

### Windows
1. Download and run the `rustup-init.exe` installer from [rustup.rs](https://rustup.rs/).
2. Ensure you have the Visual Studio C++ Build Tools installed (the installer will prompt you if they are missing).

---

## ⚙️ Step 2: Configure Symbols Mapping (`symbols.json`)
Brokers often append Micro/ECN/Pro suffixes (e.g. `EURUSDc` or `EURUSD.pro`) to symbols. You can map the server's standard symbol names to your broker's specific naming in `symbols.json` located in the `rust/` folder:

```json
{
  "EURUSD": "EURUSDc",
  "GBPUSD": "GBPUSDc",
  "USDJPY": "USDJPY.pro",
  "XAUUSD": "GOLD"
}
```
* **How it works**: When `tickbridge` receives `EURUSD` from the server, it automatically resolves it to `EURUSDc` before packing it and broadcasting it to MetaTrader. If a symbol is missing in the map, it defaults to the exchange symbol seamlessly.

---

## 💻 Step 3: Configure Environment Variables
Create a file named `.env` in the `rust/` directory or export these variables in your terminal:

```ini
TICKENGINE_STREAM_URL=wss://tickengine.com/stream/ws
TICKENGINE_API_KEY=your_secured_api_key_here
TICKENGINE_ACCOUNT_ID=your_sim_or_live_account_uuid
TICKENGINE_ZMQ_BIND=tcp://*:5555
TICKENGINE_SYMBOL_MAP_FILE=symbols.json
```

---

## 🛠️ Step 4: Build & Run in Production Mode

### 1. Compile with Peak Optimizations
Run the compiler with the `--release` flag to strip debug assertions and enable full Level-3 optimizations (`opt-level = 3`, LTO):
```bash
cargo build --release
```

### 2. Run the High-Speed Bridge Binary
Launch the optimized binary:
```bash
./target/release/tickbridge
```
You should see logging output showing successful connection to the stream, loaded symbol maps, and bound ZeroMQ sockets, waiting to broadcast signals to your MetaTrader 5 EA!
