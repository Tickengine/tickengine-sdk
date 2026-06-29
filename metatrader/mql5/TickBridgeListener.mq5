#property copyright "TickEngine"
#property link      "https://pasifi.app"
#property version   "3.00"
#property strict

// ─── Configuration Inputs ────────────────────────────────────────────────────
input string InpTcpHost      = "localhost";  // TickBridge TCP Host / IP
input uint   InpTcpPort      = 5555;         // TickBridge TCP Port
input uint   InpConnTimeout  = 5000;         // Connection Timeout (ms)
input uint   InpMaxSlippage  = 30;           // Max Allowed Slippage (in points/pipettes)
input uint   InpMaxRetries   = 3;            // Max Order Submission Re-attempts
input uint   InpRetryDelayMs = 200;          // Retry Backoff Multiplier (in ms)
input uint   InpEAMagic      = 999123;       // Expert Advisor Magic Number

// ─── TCP Socket Handle ───────────────────────────────────────────────────────
int g_socket = INVALID_HANDLE;

// ─── High-Performance C-Compatible Binary Layout (Exactly 79 Bytes) ──────────
struct MqlTradeSignal {
   uint magic;          // 4 bytes: Magic check signature (0x5449434B / 'TICK')
   uchar event_type;    // 1 byte:  0=Trade, 1=Order, 2=Alert, 3=Metric
   uchar order_type;    // 1 byte:  0=Market, 1=Limit, 2=Stop
   uchar side;          // 1 byte:  0=Buy, 1=Sell
   char symbol[32];     // 32 bytes: Fixed-size null-padded symbol string
   uchar signal_id[16]; // 16 bytes: Unique UUID bytes of the signal
   double size;         // 8 bytes: Order size (lots)
   double price;        // 8 bytes: Execution/Trigger price
   long timestamp;      // 8 bytes: Unix timestamp in milliseconds
};

// Union for zero-copy memory-casting
union MqlTradeSignalUnion {
   MqlTradeSignal signal;
   uchar bytes[79];     // Exactly 79 bytes
};

// Signal deduplication tracking history
string ProcessedSignals[];
int MaxProcessedHistory = 1000;

//+------------------------------------------------------------------+
//| Convert 16-byte UUID array to hex string                        |
//+------------------------------------------------------------------+
string SignalIdToHex(const uchar &sig_id[])
{
   string res = "";
   for(int i = 0; i < 16; i++) {
      res += StringFormat("%02X", sig_id[i]);
   }
   return res;
}

//+------------------------------------------------------------------+
//| Verify if signal ID is already processed (deduplication check)    |
//+------------------------------------------------------------------+
bool IsSignalDuplicate(const uchar &sig_id[])
{
   string hex = SignalIdToHex(sig_id);
   int total = ArraySize(ProcessedSignals);
   for(int i = 0; i < total; i++) {
      if(ProcessedSignals[i] == hex) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Add signal ID to history to prevent future duplicates           |
//+------------------------------------------------------------------+
void AddSignalToHistory(const uchar &sig_id[])
{
   string hex = SignalIdToHex(sig_id);
   int total = ArraySize(ProcessedSignals);

   if(total >= MaxProcessedHistory) {
      for(int i = 1; i < total; i++) {
         ProcessedSignals[i-1] = ProcessedSignals[i];
      }
      ProcessedSignals[total-1] = hex;
   } else {
      ArrayResize(ProcessedSignals, total + 1);
      ProcessedSignals[total] = hex;
   }
}

//+------------------------------------------------------------------+
//| Try to (re)connect to the TCP bridge                            |
//+------------------------------------------------------------------+
bool ConnectToBridge()
{
   if(g_socket != INVALID_HANDLE) {
      SocketClose(g_socket);
      g_socket = INVALID_HANDLE;
   }

   g_socket = SocketCreate();
   if(g_socket == INVALID_HANDLE) {
      Print("Error: SocketCreate failed. Error code: ", GetLastError());
      return false;
   }

   if(!SocketConnect(g_socket, InpTcpHost, InpTcpPort, InpConnTimeout)) {
      Print("Error: Cannot connect to TickBridge at ",
            InpTcpHost, ":", InpTcpPort,
            "  Error code: ", GetLastError());
      SocketClose(g_socket);
      g_socket = INVALID_HANDLE;
      return false;
   }

   Print("Connected to TickBridge at ", InpTcpHost, ":", InpTcpPort);
   return true;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Connecting to TickBridge at ", InpTcpHost, ":", InpTcpPort, " ...");
   if(!ConnectToBridge()) {
      // Non-fatal: timer will retry
      Print("Warning: Initial connection failed — will retry on timer.");
   }
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_socket != INVALID_HANDLE) {
      SocketClose(g_socket);
      g_socket = INVALID_HANDLE;
   }
}

//+------------------------------------------------------------------+
//| Automated Order Submission with Slippage & Retries               |
//+------------------------------------------------------------------+
bool ExecuteOrder(const MqlTradeSignal &sig)
{
   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   string symbolStr = CharArrayToString(sig.symbol);

   ENUM_ORDER_TYPE orderType;
   ENUM_TRADE_ACTION action = TRADE_ACTION_DEAL;

   // 1. Map event variables to ENUM_ORDER_TYPE
   if(sig.order_type == 0) { // Market Order
      orderType = (sig.side == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   } else if(sig.order_type == 1) { // Limit Order
      orderType = (sig.side == 0) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
      action = TRADE_ACTION_PENDING;
   } else if(sig.order_type == 2) { // Stop Order
      orderType = (sig.side == 0) ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP;
      action = TRADE_ACTION_PENDING;
   } else {
      Print("Error: Unsupported order type: ", sig.order_type);
      return false;
   }

   request.action       = action;
   request.symbol       = symbolStr;
   request.volume       = sig.size;
   request.type         = orderType;
   request.deviation    = InpMaxSlippage;
   request.magic        = InpEAMagic;

   // 2. Setup Price
   if(sig.order_type == 0) {
      if(sig.side == 0) {
         request.price = SymbolInfoDouble(symbolStr, SYMBOL_ASK);
      } else {
         request.price = SymbolInfoDouble(symbolStr, SYMBOL_BID);
      }
   } else {
      request.price = sig.price;
   }

   // 3. Perform execution with exponential backoff retries
   uint retries = 0;
   bool success = false;

   while(retries < InpMaxRetries) {
      if(OrderSend(request, result)) {
         if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED) {
            Print("Success: Order executed! Ticket: ", result.order,
                  ", Symbol: ", symbolStr, ", Lots: ", sig.size, ", Price: ", request.price);
            success = true;
            break;
         } else {
            Print("Warning: Order rejected by server. Retcode: ", result.retcode);
         }
      } else {
         Print("Error: OrderSend failed. Error code: ", GetLastError());
      }

      retries++;
      if(retries < InpMaxRetries) {
         int backoff = (int)InpRetryDelayMs * retries;
         Print("Liquidity or execution failure. Retry attempt ", retries, " in ", backoff, " ms...");
         Sleep(backoff);

         if(sig.order_type == 0) {
            if(sig.side == 0) {
               request.price = SymbolInfoDouble(symbolStr, SYMBOL_ASK);
            } else {
               request.price = SymbolInfoDouble(symbolStr, SYMBOL_BID);
            }
         }
      }
   }

   return success;
}

//+------------------------------------------------------------------+
//| Read exactly N bytes from the TCP socket into buf               |
//| Returns true only when exactly N bytes have been read.          |
//+------------------------------------------------------------------+
bool ReadExactly(int socket, uchar &buf[], uint n)
{
   uint total = 0;
   uchar chunk[];
   while(total < n) {
      uint readable = SocketIsReadable(socket);
      if(readable == 0) return false; // no data yet — non-blocking bail
      uint want  = MathMin(n - total, readable);
      uint got   = SocketRead(socket, chunk, want, 100);
      if(got == 0) return false;
      for(uint i = 0; i < got; i++) {
         buf[total + i] = chunk[i];
      }
      total += got;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Timer function — Core signal receiver & routing                  |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Reconnect if socket is gone
   if(g_socket == INVALID_HANDLE) {
      Print("TCP socket lost — attempting reconnect...");
      ConnectToBridge();
      return;
   }

   // Drain all available complete 79-byte frames in one timer tick
   while(SocketIsReadable(g_socket) > 0) {
      uchar buf[];
      ArrayResize(buf, 79);

      if(!ReadExactly(g_socket, buf, 79)) {
         // Partial read or nothing available — try again next tick
         break;
      }

      MqlTradeSignalUnion u;
      for(int i = 0; i < 79; i++) {
         u.bytes[i] = buf[i];
      }

      // 1. Verify Magic Signature
      if(u.signal.magic != 0x5449434B) {
         Print("Error: Invalid magic signature in received signal — possible stream corruption");
         // Close and reconnect to resync
         SocketClose(g_socket);
         g_socket = INVALID_HANDLE;
         break;
      }

      // 2. Signal Deduplication
      if(IsSignalDuplicate(u.signal.signal_id)) {
         continue;
      }
      AddSignalToHistory(u.signal.signal_id);

      string symbolStr = CharArrayToString(u.signal.symbol);
      string uuidHex   = SignalIdToHex(u.signal.signal_id);

      Print("Signal Accepted -> Symbol: ", symbolStr,
            ", ID: ", uuidHex,
            ", EventType: ", u.signal.event_type,
            ", OrderType: ", u.signal.order_type,
            ", Side: ", u.signal.side,
            ", Size: ", DoubleToString(u.signal.size, 5),
            ", Price: ", DoubleToString(u.signal.price, 5));

      // 3. Execute order (skip metric update events)
      if(u.signal.event_type != 3) {
         ExecuteOrder(u.signal);
      }
   }
}
