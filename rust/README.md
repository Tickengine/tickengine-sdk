# 🦀 Rust High-Speed Client Bridge (`tickbridge`)

The Rust Client is the **highly recommended** entry point for production trading setups. It connects to the TickEngine WebSocket stream, decodes binary MessagePack payloads, performs dynamic local symbol mapping, and publishes raw 79-byte packed C-struct signals to MetaTrader 5 via TCP.

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

## 💻 Step 3: Configure the `config.json` File
Modify the `config.json` file in the root of the SDK directory (or specify its location via the `TICKENGINE_CONFIG_FILE` environment variable).

Example `config.json`:
```json
{
  "stream": {
    "url": "wss://tickengine.com/stream/ws",
    "api_key": "YOUR_TICKENGINE_API_KEY",
    "account_id": "YOUR_TICKENGINE_ACCOUNT_ID"
  },
  "agents": {
    "mt5_ea": {
      "type": "mt5_ea",
      "tcp_bind": "tcp://127.0.0.1:5555",
      "symbol_map": {
        "EURUSD": "EURUSD"
      }
    }
  }
}
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
You should see logging output showing successful connection to the stream, loaded symbol maps, and bound TCP sockets, waiting to broadcast signals to your MetaTrader 5 EA!
