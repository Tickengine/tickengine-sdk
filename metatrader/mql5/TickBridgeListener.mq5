#property copyright "TickEngine"
#property link      "https://pasifi.app"
#property version   "2.00"
#property strict

// --- ZeroMQ Library Includes (Requires mql-zmq) ---
#include <Zmq/Zmq.mqh>

input string InpZmqAddress    = "tcp://localhost:5555"; // TickBridge ZeroMQ Address
input uint   InpMaxSlippage   = 30;                     // Max Allowed Slippage (in points/pipettes)
input uint   InpMaxRetries    = 3;                      // Max Order Submission Re-attempts
input uint   InpRetryDelayMs  = 200;                    // Retry Backoff Multiplier (in ms)
input uint   InpEAMagic       = 999123;                 // Expert Advisor Magic Number

Context context;
Socket subSocket(context, ZMQ_SUB);

// --- High-Performance C-Compatible Binary Layout (Exactly 79 Bytes) ---
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
      // Shift array left to evict oldest element
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
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Connecting to TickBridge at ", InpZmqAddress);
   if(!subSocket.connect(InpZmqAddress)) {
      Print("Error: Failed to connect to ZeroMQ Bridge");
      return(INIT_FAILED);
   }
   
   // Subscribe to empty string "" wildcard to receive all published signals
   subSocket.subscribe("");
   Print("ZeroMQ Wildcard Subscription Enabled. Subscribed to all topics.");
   
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
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
   
   // 2. Setup Price (Market orders require Ask/Bid, Pending orders use the signal's price)
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
         
         // Refresh prices for market orders on retry loop
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
//| Timer function - Core Signal receiver & routing                  |
//+------------------------------------------------------------------+
void OnTimer()
{
   ZmqMsg msg;
   // Check for new ZeroMQ messages (non-blocking)
   if(subSocket.recv(msg, ZMQ_DONTWAIT) > 0) {
      string topic = msg.getData();
      
      // Receive binary payload
      if(subSocket.recv(msg, ZMQ_DONTWAIT) > 0) {
         uchar bytes[];
         msg.getData(bytes);
         
         int size = ArraySize(bytes);
         if(size == 79) {
            MqlTradeSignalUnion u;
            
            // Memory cast raw bytes into structure
            for(int i = 0; i < 79; i++) {
               u.bytes[i] = bytes[i];
            }
            
            // 1. Verify Magic Signature
            if(u.signal.magic != 0x5449434B) {
               Print("Error: Invalid magic signature in received binary signal");
               return;
            }
            
            // 2. Perform Signal Deduplication Check
            if(IsSignalDuplicate(u.signal.signal_id)) {
               // Discard duplicate immediately
               return;
            }
            
            // Register signal ID to block future duplicates
            AddSignalToHistory(u.signal.signal_id);
            
            string symbolStr = CharArrayToString(u.signal.symbol);
            string uuidHex = SignalIdToHex(u.signal.signal_id);
            
            Print("Signal Accepted -> Symbol: ", symbolStr, 
                  ", ID: ", uuidHex,
                  ", EventType: ", u.signal.event_type,
                  ", OrderType: ", u.signal.order_type,
                  ", Side: ", u.signal.side,
                  ", Size: ", DoubleToString(u.signal.size, 5),
                  ", Price: ", DoubleToString(u.signal.price, 5));
            
            // 3. Automate order execution (Ignore metric update events)
            if(u.signal.event_type != 3) {
               ExecuteOrder(u.signal);
            }
         } else {
            Print("Warning: Received binary frame with unexpected size: ", size, " (expected 79)");
         }
      }
   }
}
