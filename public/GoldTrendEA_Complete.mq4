//+------------------------------------------------------------------+
//| GoldTrendEA_Complete.mq4                                         |
//| COMPLETE CONSOLIDATED EXPERT ADVISOR                             |
//| Version: 1.0 | Date: 2026-01-01                                  |
//| 2-Candle EMA Crossover with ADX Confirmation Strategy            |
//+------------------------------------------------------------------+
//| STRATEGY SUMMARY:                                                |
//| BUY: EMA50 crossed above, candle 4-6$ body, 2nd confirms, ADX>20 |
//| SELL: EMA50 crossed below, candle 4-6$ body, 2nd confirms, ADX>20|
//| TP=2000 pips | Trailing=1000 pips | SL=Opposite Signal           |
//| Averaging: +0.03 lots at -800 pips drawdown                      |
//| Partial Close: 50% when combined profit > $1.00                  |
//+------------------------------------------------------------------+
#property copyright "Expert Advisor Builder"
#property link      ""
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| ===================== SECTION 1: CONFIG ======================== |
//| Central Configuration and Constants Hub                          |
//| Estimated Lines: ~635                                            |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| PROJECT INFORMATION                                              |
//+------------------------------------------------------------------+
#define EA_NAME           "GoldTrendEA"
#define EA_VERSION        "1.0"
#define EA_DESCRIPTION    "GOLD Trend Confirmation with 2-Candle System"
#define EA_AUTHOR         "Expert Advisor Builder"
#define EA_DATE           "2026-01-01"
#define EA_BROKER_TYPE    "3-Decimal (GOLD)"

//+------------------------------------------------------------------+
//| MAGIC NUMBER DEFINITION                                          |
//+------------------------------------------------------------------+
#define MAGIC_MAIN_ORDER  123456
#define MAGIC_AVERAGING   123457
#define MAGIC_EA_BASE     123456

//+------------------------------------------------------------------+
//| USER INPUT PARAMETERS - ENTRY SIGNAL                             |
//+------------------------------------------------------------------+

input string   _1_EntrySettings = "=== ENTRY SIGNAL SETTINGS ===";   // --- Entry Settings ---
input int      Candle_Size_Min_Pips = 400;           // Minimum candle body size (pips)
input int      Candle_Size_Max_Pips = 600;           // Maximum candle body size (pips)
input int      Candle_Size_Tolerance_Pct = 90;       // 2nd candle tolerance % of 1st candle
input int      ADX_Period = 14;                       // ADX calculation period
input int      EMA_Period = 50;                       // EMA calculation period
input int      ADX_Threshold = 20;                    // Minimum ADX value for entry

//+------------------------------------------------------------------+
//| USER INPUT PARAMETERS - POSITION SIZING                          |
//+------------------------------------------------------------------+

input string   _2_PositionSettings = "=== POSITION SIZING ===";   // --- Position Settings ---
input double   Initial_Lot_Size = 0.01;              // Initial order lot size
input double   Averaging_Lot_Size = 0.03;            // Averaging order lot size

//+------------------------------------------------------------------+
//| USER INPUT PARAMETERS - RISK MANAGEMENT                          |
//+------------------------------------------------------------------+

input string   _3_RiskSettings = "=== RISK MANAGEMENT ===";   // --- Risk Settings ---
input int      Fixed_TP_Pips = 2000;                 // Fixed Take Profit in pips
input int      Trailing_Activation_Pips = 1000;      // Trailing stop activation profit
input int      Trailing_Distance_Pips = 1000;        // Trailing stop distance behind high/low
input int      Trailing_Stop_Step_Pips = 100;        // Trailing stop update step size
input int      Averaging_Drawdown_Pips = -800;       // Averaging trigger drawdown pips
input double   Profit_Close_Threshold = 1.00;        // Combined profit threshold for close ($)
input int      Max_Slippage_Pips = 200;              // Maximum acceptable slippage

//+------------------------------------------------------------------+
//| ENUMS - SIGNAL AND TRADE STATES                                  |
//+------------------------------------------------------------------+

// Order type enumeration
enum ENUM_ORDER_TYPE_EA {
    ORDER_TYPE_BUY = 0,                              // Buy order
    ORDER_TYPE_SELL = 1,                             // Sell order
    ORDER_TYPE_NONE = 2                              // No active order
};

// Trade phase enumeration - tracks entry confirmation progress
enum ENUM_TRADE_PHASE {
    PHASE_NO_SIGNAL = 0,                             // No signal detected
    PHASE_1ST_CANDLE_DETECTED = 1,                   // 1st candle close confirmed above/below EMA
    PHASE_2ND_CANDLE_CONFIRMED = 2,                  // 2nd candle close with tolerance check done
    PHASE_READY_FOR_ENTRY = 3,                       // All conditions met, waiting for 3rd candle open
    PHASE_ENTRY_EXECUTED = 4                         // Order opened
};

// Exit reason enumeration - identifies which exit condition triggered
enum ENUM_EXIT_REASON {
    EXIT_REASON_NONE = 0,                            // Trade still open
    EXIT_REASON_TP = 1,                              // Take profit hit
    EXIT_REASON_SL = 2,                              // Stop loss hit
    EXIT_REASON_TRAILING_STOP = 3,                   // Trailing stop hit
    EXIT_REASON_OPPOSITE_SIGNAL = 4,                 // Opposite signal confirmed
    EXIT_REASON_MANUAL = 5,                          // Manual close
    EXIT_REASON_EA_STOP = 6,                         // EA stopped
    EXIT_REASON_ERROR = 7                            // Error during trade
};

// Signal state enumeration - current signal status
enum ENUM_SIGNAL_STATE {
    SIGNAL_STATE_NONE = 0,                           // No signal
    SIGNAL_STATE_BUY_FORMING = 1,                    // Buy signal forming
    SIGNAL_STATE_BUY_READY = 2,                      // Buy signal ready to enter
    SIGNAL_STATE_SELL_FORMING = 3,                   // Sell signal forming
    SIGNAL_STATE_SELL_READY = 4,                     // Sell signal ready to enter
    SIGNAL_STATE_BUY_ACTIVE = 5,                     // Buy trade active
    SIGNAL_STATE_SELL_ACTIVE = 6                     // Sell trade active
};

//+------------------------------------------------------------------+
//| STRUCTURES - TRADE AND ORDER DATA                                |
//+------------------------------------------------------------------+

// Trade setup structure - stores confirmed entry signal details
struct TradeSetup {
    ENUM_ORDER_TYPE_EA orderType;                    // BUY or SELL
    double entryPrice;                               // Entry price for 3rd candle
    double stopLossPrice;                            // SL price (from opposite signal)
    double takeProfitPrice;                          // TP price (fixed pips)
    int firstCandleIndex;                            // Index of 1st confirmation candle
    int secondCandleIndex;                           // Index of 2nd confirmation candle
    double firstCandleSize;                          // Body size of 1st candle (pips)
    double secondCandleSize;                         // Body size of 2nd candle (pips)
    double emaValue;                                 // EMA value at entry time
    double adxValue;                                 // ADX value at entry time
    double bidPrice;                                 // Bid price at confirmation
    double askPrice;                                 // Ask price at confirmation
    datetime entryTime;                              // Entry execution time
    bool isValid;                                    // Setup validation flag
};

// Order data structure - tracks active order details
struct OrderData {
    int ticket;                                      // Order ticket number
    ENUM_ORDER_TYPE_EA orderType;                    // BUY or SELL
    double lots;                                     // Order volume in lots
    double entryPrice;                               // Entry execution price
    double currentSL;                                // Current stop loss
    double currentTP;                                // Current take profit
    double highestPrice;                             // Highest price since entry (for trailing)
    double lowestPrice;                              // Lowest price since entry (for trailing)
    double floatingProfit;                           // Current floating profit
    datetime openTime;                               // Order open time
    datetime modifyTime;                             // Last modification time
    int barsSinceEntry;                              // Bars since order open
    bool trailingStopActive;                         // Trailing stop activation flag
    double trailingStopLevel;                        // Current trailing stop level
    int totalModifications;                          // Count of modifications
};

// Averaging basket structure - tracks initial + averaging orders
struct AveragingBasket {
    int mainOrderTicket;                             // Main order (0.01 lots)
    int averagingOrderTicket;                        // Averaging order (0.03 lots)
    double mainOrderLots;                            // 0.01 lots
    double averagingOrderLots;                       // 0.03 lots
    double mainEntryPrice;                           // Main order entry price
    double averagingEntryPrice;                      // Averaging order entry price
    double basketProfit;                             // Combined profit (excluding swap/commission)
    bool averagingTriggered;                         // Averaging order opened flag
    bool partialCloseDone;                           // 50% partial close executed flag
    double totalClosedLots;                          // Total lots closed from partial closes
    datetime lastTriggerTime;                        // Last averaging trigger time
    bool isValid;                                    // Basket validation flag
};

// Statistics structure - tracks performance metrics
struct Statistics {
    int totalTrades;                                 // Total trades executed
    int winTrades;                                   // Winning trades count
    int lossTrades;                                  // Losing trades count
    double winRate;                                  // Win rate percentage (0-100)
    double totalProfit;                              // Cumulative profit
    double totalLoss;                                // Cumulative loss
    double largestWin;                               // Largest single win
    double largestLoss;                              // Largest single loss
    double profitFactor;                             // Profit / Loss ratio
    int consecutiveWins;                             // Current win streak
    int consecutiveLosses;                           // Current loss streak
    datetime sessionStartTime;                       // EA start time
    datetime lastTradeClosedTime;                    // Last trade close time
    bool isValid;                                    // Statistics validation flag
};

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES - SESSION STATE                                 |
//+------------------------------------------------------------------+

// Current trade state
ENUM_ORDER_TYPE_EA CurrentOrderType = ORDER_TYPE_NONE;
ENUM_TRADE_PHASE CurrentPhase = PHASE_NO_SIGNAL;
ENUM_SIGNAL_STATE CurrentSignalState = SIGNAL_STATE_NONE;
ENUM_EXIT_REASON LastExitReason = EXIT_REASON_NONE;

// Trade and order tracking
OrderData CurrentOrder;
TradeSetup PendingSetup;
AveragingBasket Basket;
Statistics Stats;

// EMA and ADX tracking
double CurrentEMA = 0.0;
double PreviousEMA = 0.0;
double CurrentADX = 0.0;
double PreviousADX = 0.0;

// Candle data tracking (1st candle)
double FirstCandleOpen_G = 0.0;
double FirstCandleClose_G = 0.0;
double FirstCandleHigh_G = 0.0;
double FirstCandleLow_G = 0.0;
double FirstCandleSize_G = 0.0;

// Candle data tracking (2nd candle)
double SecondCandleOpen_G = 0.0;
double SecondCandleClose_G = 0.0;
double SecondCandleHigh_G = 0.0;
double SecondCandleLow_G = 0.0;
double SecondCandleSize_G = 0.0;

// System flags
bool IsInitialized = false;
bool IsTradingAllowed = true;
bool IsLoggerReady = false;
int LastProcessedBar = -1;
int ErrorCount = 0;
int MaxAllowedErrors = 10;

// Performance tracking
int TotalTickProcessed = 0;
datetime LastTickTime = 0;
double MaxDrawdown = 0.0;
double CurrentDrawdown = 0.0;

//+------------------------------------------------------------------+
//| CONSTANTS - DISPLAY AND COLORS                                   |
//+------------------------------------------------------------------+

#define COLOR_BUY              clrGreen
#define COLOR_SELL             clrRed
#define COLOR_PROFIT           clrLimeGreen
#define COLOR_LOSS             clrCrimson
#define COLOR_INFO             clrDodgerBlue
#define COLOR_WARNING          clrOrange
#define COLOR_ERROR            clrDarkRed

#define ICON_BUY               "►"
#define ICON_SELL              "◄"
#define ICON_CHECK             "✓"
#define ICON_CROSS             "✗"
#define ICON_WARNING           "⚠"

//+------------------------------------------------------------------+
//| CONSTANTS - VALIDATION RANGES                                    |
//+------------------------------------------------------------------+

#define MIN_CANDLE_SIZE        100        // Minimum pips
#define MAX_CANDLE_SIZE        2000       // Maximum pips
#define MIN_TOLERANCE          50         // Minimum tolerance %
#define MAX_TOLERANCE          100        // Maximum tolerance %
#define MIN_ADX_PERIOD         7          // Minimum ADX period
#define MAX_ADX_PERIOD         21         // Maximum ADX period
#define MIN_EMA_PERIOD         20         // Minimum EMA period
#define MAX_EMA_PERIOD         200        // Maximum EMA period
#define MIN_ADX_THRESHOLD      10         // Minimum ADX threshold
#define MAX_ADX_THRESHOLD      30         // Maximum ADX threshold
#define MIN_TP_PIPS            500        // Minimum TP
#define MAX_TP_PIPS            5000       // Maximum TP
#define MIN_SLIPPAGE           50         // Minimum slippage
#define MAX_SLIPPAGE           500        // Maximum slippage

//+------------------------------------------------------------------+
//| CONSTANTS - TRADE CONSTRAINTS                                    |
//+------------------------------------------------------------------+

#define MAX_SIMULTANEOUS_TRADES    1      // Only 1 position at a time
#define MAX_AVERAGING_ORDERS       1      // Maximum 1 averaging order

//+------------------------------------------------------------------+
//| ERROR CODES - EA-SPECIFIC                                        |
//+------------------------------------------------------------------+

#define ERR_INVALID_SYMBOL        1001
#define ERR_INVALID_TIMEFRAME     1002
#define ERR_INVALID_INPUTS        1003
#define ERR_SYMBOL_NOT_READY      1004
#define ERR_ORDER_SEND_FAILED     1005
#define ERR_ORDER_MODIFY_FAILED   1006
#define ERR_ORDER_CLOSE_FAILED    1007
#define ERR_INSUFFICIENT_FUNDS    1008
#define ERR_INVALID_LOT_SIZE      1009
#define ERR_SLIPPAGE_EXCEEDED     1010
#define ERR_EMA_NOT_READY         1011
#define ERR_ADX_NOT_READY         1012
#define ERR_CANDLE_NOT_READY      1013
#define ERR_TRADE_ALREADY_OPEN    1014
#define ERR_NO_OPPOSITE_SIGNAL    1015
#define ERR_ORDER_OPEN_FAILED     1016

//+------------------------------------------------------------------+
//| =================== SECTION 2: UTILITY ========================= |
//| Helper Functions for Price, Lots, and Candle Data                |
//| Estimated Lines: ~400                                            |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| PRICE CONVERSION FUNCTIONS                                       |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| FUNCTION: PriceToPips()                                          |
//| Purpose: Convert price difference to pips                        |
//| Input:   priceValue - price difference in price units            |
//| Returns: Value in pips                                           |
//+------------------------------------------------------------------+
double PriceToPips(double priceValue) {
    // For 3-digit (GOLD) and 5-digit (forex) brokers
    // Point is the smallest price unit (e.g., 0.001 for GOLD 3-digit)
    // 1 pip = 10 points for 3-digit GOLD, 10 points for 5-digit forex
    
    double pipValue = 0.0;
    
    if (Digits == 3 || Digits == 5) {
        pipValue = priceValue / (Point * 10);
    } else if (Digits == 2 || Digits == 4) {
        pipValue = priceValue / Point;
    } else {
        // Default to 10 points per pip
        pipValue = priceValue / (Point * 10);
    }
    
    return MathAbs(pipValue);
}

//+------------------------------------------------------------------+
//| FUNCTION: PipsToPrice()                                          |
//| Purpose: Convert pips to price units                             |
//| Input:   pips - value in pips                                    |
//| Returns: Value in price units                                    |
//+------------------------------------------------------------------+
double PipsToPrice(double pips) {
    double priceValue = 0.0;
    
    if (Digits == 3 || Digits == 5) {
        priceValue = pips * Point * 10;
    } else if (Digits == 2 || Digits == 4) {
        priceValue = pips * Point;
    } else {
        priceValue = pips * Point * 10;
    }
    
    return priceValue;
}

//+------------------------------------------------------------------+
//| FUNCTION: NormalizePrice()                                       |
//| Purpose: Normalize price to correct decimal places               |
//| Input:   price - price to normalize                              |
//| Returns: Normalized price                                        |
//+------------------------------------------------------------------+
double NormalizePrice(double price) {
    return NormalizeDouble(price, Digits);
}

//+------------------------------------------------------------------+
//| LOT NORMALIZATION FUNCTIONS                                      |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| FUNCTION: GetSymbolMinLot()                                      |
//| Purpose: Get minimum lot size for current symbol                 |
//| Returns: Minimum lot size                                        |
//+------------------------------------------------------------------+
double GetSymbolMinLot() {
    return MarketInfo(Symbol(), MODE_MINLOT);
}

//+------------------------------------------------------------------+
//| FUNCTION: GetSymbolMaxLot()                                      |
//| Purpose: Get maximum lot size for current symbol                 |
//| Returns: Maximum lot size                                        |
//+------------------------------------------------------------------+
double GetSymbolMaxLot() {
    return MarketInfo(Symbol(), MODE_MAXLOT);
}

//+------------------------------------------------------------------+
//| FUNCTION: GetSymbolLotStep()                                     |
//| Purpose: Get lot step for current symbol                         |
//| Returns: Lot step                                                |
//+------------------------------------------------------------------+
double GetSymbolLotStep() {
    return MarketInfo(Symbol(), MODE_LOTSTEP);
}

//+------------------------------------------------------------------+
//| FUNCTION: NormalizeLots()                                        |
//| Purpose: Normalize lot size to broker requirements               |
//| Input:   lots - lot size to normalize                            |
//| Returns: Normalized lot size                                     |
//+------------------------------------------------------------------+
double NormalizeLots(double lots) {
    double minLot = GetSymbolMinLot();
    double maxLot = GetSymbolMaxLot();
    double lotStep = GetSymbolLotStep();
    
    // Ensure above minimum
    if (lots < minLot) {
        lots = minLot;
    }
    
    // Ensure below maximum
    if (lots > maxLot) {
        lots = maxLot;
    }
    
    // Round to lot step
    lots = MathRound(lots / lotStep) * lotStep;
    
    // Normalize to 2 decimal places
    lots = NormalizeDouble(lots, 2);
    
    return lots;
}

//+------------------------------------------------------------------+
//| FUNCTION: ValidateAccountBalance()                               |
//| Purpose: Check if account has sufficient balance for trade       |
//| Input:   lots - lot size to trade                                |
//| Returns: true if sufficient, false otherwise                     |
//+------------------------------------------------------------------+
bool ValidateAccountBalance(double lots) {
    double requiredMargin = MarketInfo(Symbol(), MODE_MARGINREQUIRED) * lots;
    double freeMargin = AccountFreeMargin();
    
    if (freeMargin < requiredMargin * 1.2) {  // 20% safety buffer
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| CANDLE DATA ACCESS FUNCTIONS                                     |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| FUNCTION: GetCandleOpen()                                        |
//| Purpose: Get open price of specified bar                         |
//| Input:   shift - bar index (0 = current, 1 = previous closed)    |
//| Returns: Open price                                              |
//+------------------------------------------------------------------+
double GetCandleOpen(int shift) {
    return iOpen(Symbol(), Period(), shift);
}

//+------------------------------------------------------------------+
//| FUNCTION: GetCandleClose()                                       |
//| Purpose: Get close price of specified bar                        |
//| Input:   shift - bar index                                       |
//| Returns: Close price                                             |
//+------------------------------------------------------------------+
double GetCandleClose(int shift) {
    return iClose(Symbol(), Period(), shift);
}

//+------------------------------------------------------------------+
//| FUNCTION: GetCandleHigh()                                        |
//| Purpose: Get high price of specified bar                         |
//| Input:   shift - bar index                                       |
//| Returns: High price                                              |
//+------------------------------------------------------------------+
double GetCandleHigh(int shift) {
    return iHigh(Symbol(), Period(), shift);
}

//+------------------------------------------------------------------+
//| FUNCTION: GetCandleLow()                                         |
//| Purpose: Get low price of specified bar                          |
//| Input:   shift - bar index                                       |
//| Returns: Low price                                               |
//+------------------------------------------------------------------+
double GetCandleLow(int shift) {
    return iLow(Symbol(), Period(), shift);
}

//+------------------------------------------------------------------+
//| FUNCTION: GetBarTime()                                           |
//| Purpose: Get open time of specified bar                          |
//| Input:   shift - bar index                                       |
//| Returns: Bar open time                                           |
//+------------------------------------------------------------------+
datetime GetBarTime(int shift) {
    return iTime(Symbol(), Period(), shift);
}

//+------------------------------------------------------------------+
//| FUNCTION: GetCandleBodySize()                                    |
//| Purpose: Calculate body size of candle in pips                   |
//| Input:   shift - bar index                                       |
//| Returns: Body size in pips (absolute value)                      |
//+------------------------------------------------------------------+
double GetCandleBodySize(int shift) {
    double openPrice = GetCandleOpen(shift);
    double closePrice = GetCandleClose(shift);
    double bodyPrice = MathAbs(closePrice - openPrice);
    
    return PriceToPips(bodyPrice);
}

//+------------------------------------------------------------------+
//| FUNCTION: GetCandleDirection()                                   |
//| Purpose: Determine if candle is bullish or bearish               |
//| Input:   shift - bar index                                       |
//| Returns: 1 = bullish, -1 = bearish, 0 = doji                     |
//+------------------------------------------------------------------+
int GetCandleDirection(int shift) {
    double openPrice = GetCandleOpen(shift);
    double closePrice = GetCandleClose(shift);
    
    if (closePrice > openPrice) {
        return 1;  // Bullish
    } else if (closePrice < openPrice) {
        return -1; // Bearish
    }
    
    return 0;  // Doji
}

//+------------------------------------------------------------------+
//| FUNCTION: IsBullishCandle()                                      |
//| Purpose: Check if candle is bullish                              |
//| Input:   shift - bar index                                       |
//| Returns: true if bullish, false otherwise                        |
//+------------------------------------------------------------------+
bool IsBullishCandle(int shift) {
    return GetCandleDirection(shift) == 1;
}

//+------------------------------------------------------------------+
//| FUNCTION: IsBearishCandle()                                      |
//| Purpose: Check if candle is bearish                              |
//| Input:   shift - bar index                                       |
//| Returns: true if bearish, false otherwise                        |
//+------------------------------------------------------------------+
bool IsBearishCandle(int shift) {
    return GetCandleDirection(shift) == -1;
}

//+------------------------------------------------------------------+
//| FUNCTION: IsSpreadAcceptable()                                   |
//| Purpose: Check if current spread is within acceptable range      |
//| Input:   maxAllowedPips - maximum acceptable spread in pips      |
//| Returns: true if spread <= max, false otherwise                  |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable(double maxAllowedPips) {
    RefreshRates();
    double spreadPrice = Ask - Bid;
    double spreadPips = PriceToPips(spreadPrice);
    
    if (spreadPips > maxAllowedPips) {
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| FUNCTION: GetErrorDescription()                                  |
//| Purpose: Convert error code to human-readable description        |
//| Input:   errorCode - error code to translate                     |
//| Returns: Error description string                                |
//+------------------------------------------------------------------+
string GetErrorDescription(int errorCode) {
    switch (errorCode) {
        case 0:     return "No error";
        case 1:     return "Invalid function parameters";
        case 2:     return "Common error";
        case 3:     return "Invalid trade parameters";
        case 4:     return "Trade server is busy";
        case 5:     return "Old version of the client terminal";
        case 6:     return "No connection with trade server";
        case 7:     return "Not enough rights";
        case 8:     return "Too frequent requests";
        case 9:     return "Malfunctional trade operation";
        case 64:    return "Account disabled";
        case 65:    return "Invalid account";
        case 128:   return "Trade timeout";
        case 129:   return "Invalid price";
        case 130:   return "Invalid stops";
        case 131:   return "Invalid trade volume";
        case 132:   return "Market is closed";
        case 133:   return "Trade is disabled";
        case 134:   return "Not enough money";
        case 135:   return "Price changed";
        case 136:   return "Off quotes";
        case 137:   return "Broker is busy";
        case 138:   return "Requote";
        case 139:   return "Order is locked";
        case 140:   return "Long positions only allowed";
        case 141:   return "Too many requests";
        case 145:   return "Modification denied because order is too close to market";
        case 146:   return "Trade context is busy";
        case 147:   return "Expirations are denied on this symbol";
        case 148:   return "Trade operations are allowed only for live accounts";
        case 149:   return "Order is not in the book";
        case 150:   return "Notifications are disabled";
        case 151:   return "Operation is prohibited";
        case 152:   return "Too many open positions";
        
        // EA-specific error codes
        case ERR_INVALID_SYMBOL:    return "Invalid symbol for this EA";
        case ERR_INVALID_TIMEFRAME: return "Invalid timeframe";
        case ERR_INVALID_INPUTS:    return "Invalid input parameters";
        case ERR_SYMBOL_NOT_READY:  return "Symbol data not ready";
        case ERR_ORDER_SEND_FAILED: return "Order send failed";
        case ERR_ORDER_MODIFY_FAILED: return "Order modification failed";
        case ERR_ORDER_CLOSE_FAILED: return "Order close failed";
        case ERR_INSUFFICIENT_FUNDS: return "Insufficient funds";
        case ERR_INVALID_LOT_SIZE:  return "Invalid lot size";
        case ERR_SLIPPAGE_EXCEEDED: return "Slippage exceeded maximum allowed";
        case ERR_EMA_NOT_READY:     return "EMA indicator not ready";
        case ERR_ADX_NOT_READY:     return "ADX indicator not ready";
        case ERR_CANDLE_NOT_READY:  return "Candle data not ready";
        case ERR_TRADE_ALREADY_OPEN: return "Trade already open";
        case ERR_NO_OPPOSITE_SIGNAL: return "No opposite signal detected";
        
        default:    return "Unknown error code: " + IntegerToString(errorCode);
    }
}

//+------------------------------------------------------------------+
//| FUNCTION: GetTimeframeString()                                   |
//| Purpose: Convert period enum to readable string                  |
//| Input:   period - timeframe period                               |
//| Returns: Timeframe string (e.g., "H1", "M15")                    |
//+------------------------------------------------------------------+
string GetTimeframeString(int period) {
    switch(period) {
        case PERIOD_M1:  return "M1";
        case PERIOD_M5:  return "M5";
        case PERIOD_M15: return "M15";
        case PERIOD_M30: return "M30";
        case PERIOD_H1:  return "H1";
        case PERIOD_H4:  return "H4";
        case PERIOD_D1:  return "D1";
        case PERIOD_W1:  return "W1";
        case PERIOD_MN1: return "MN1";
        default: return "Unknown";
    }
}

//+------------------------------------------------------------------+
//| FUNCTION: GetPhaseString()                                       |
//| Purpose: Convert phase enum to readable string                   |
//| Input:   phase - trade phase enum                                |
//| Returns: Phase description string                                |
//+------------------------------------------------------------------+
string GetPhaseString(ENUM_TRADE_PHASE phase) {
    switch(phase) {
        case PHASE_NO_SIGNAL: return "No Signal";
        case PHASE_1ST_CANDLE_DETECTED: return "1st Candle Detected";
        case PHASE_2ND_CANDLE_CONFIRMED: return "2nd Candle Confirmed";
        case PHASE_READY_FOR_ENTRY: return "Ready for Entry";
        case PHASE_ENTRY_EXECUTED: return "Trade Active";
        default: return "Unknown";
    }
}

//+------------------------------------------------------------------+
//| FUNCTION: GetSignalStateString()                                 |
//| Purpose: Convert signal state enum to readable string            |
//| Input:   state - signal state enum                               |
//| Returns: Signal state description string                         |
//+------------------------------------------------------------------+
string GetSignalStateString(ENUM_SIGNAL_STATE state) {
    switch(state) {
        case SIGNAL_STATE_NONE: return "None";
        case SIGNAL_STATE_BUY_FORMING: return "BUY Forming";
        case SIGNAL_STATE_BUY_READY: return "BUY Ready";
        case SIGNAL_STATE_SELL_FORMING: return "SELL Forming";
        case SIGNAL_STATE_SELL_READY: return "SELL Ready";
        case SIGNAL_STATE_BUY_ACTIVE: return "BUY Active";
        case SIGNAL_STATE_SELL_ACTIVE: return "SELL Active";
        default: return "Unknown";
    }
}

//+------------------------------------------------------------------+
//| FUNCTION: ValidateInputParameters()                              |
//| Purpose: Validate all user input parameters against ranges       |
//| Returns: true if all inputs valid, false if any invalid          |
//+------------------------------------------------------------------+
bool ValidateInputParameters() {
    // Validate candle size range
    if (Candle_Size_Min_Pips < MIN_CANDLE_SIZE || Candle_Size_Min_Pips > MAX_CANDLE_SIZE) {
        Alert("ERROR: Candle Size Min must be between ", MIN_CANDLE_SIZE, " and ", MAX_CANDLE_SIZE, " pips");
        return false;
    }
    
    if (Candle_Size_Max_Pips < MIN_CANDLE_SIZE || Candle_Size_Max_Pips > MAX_CANDLE_SIZE) {
        Alert("ERROR: Candle Size Max must be between ", MIN_CANDLE_SIZE, " and ", MAX_CANDLE_SIZE, " pips");
        return false;
    }
    
    if (Candle_Size_Min_Pips > Candle_Size_Max_Pips) {
        Alert("ERROR: Candle Size Min cannot be greater than Max");
        return false;
    }
    
    // Validate candle tolerance
    if (Candle_Size_Tolerance_Pct < MIN_TOLERANCE || Candle_Size_Tolerance_Pct > MAX_TOLERANCE) {
        Alert("ERROR: Candle Size Tolerance must be between ", MIN_TOLERANCE, "% and ", MAX_TOLERANCE, "%");
        return false;
    }
    
    // Validate ADX period
    if (ADX_Period < MIN_ADX_PERIOD || ADX_Period > MAX_ADX_PERIOD) {
        Alert("ERROR: ADX Period must be between ", MIN_ADX_PERIOD, " and ", MAX_ADX_PERIOD);
        return false;
    }
    
    // Validate EMA period
    if (EMA_Period < MIN_EMA_PERIOD || EMA_Period > MAX_EMA_PERIOD) {
        Alert("ERROR: EMA Period must be between ", MIN_EMA_PERIOD, " and ", MAX_EMA_PERIOD);
        return false;
    }
    
    // Validate ADX threshold
    if (ADX_Threshold < MIN_ADX_THRESHOLD || ADX_Threshold > MAX_ADX_THRESHOLD) {
        Alert("ERROR: ADX Threshold must be between ", MIN_ADX_THRESHOLD, " and ", MAX_ADX_THRESHOLD);
        return false;
    }
    
    // Validate take profit
    if (Fixed_TP_Pips < MIN_TP_PIPS || Fixed_TP_Pips > MAX_TP_PIPS) {
        Alert("ERROR: Fixed TP must be between ", MIN_TP_PIPS, " and ", MAX_TP_PIPS, " pips");
        return false;
    }
    
    // Validate lot sizes
    if (Initial_Lot_Size <= 0 || Initial_Lot_Size > 1.0) {
        Alert("ERROR: Initial Lot Size must be between 0.01 and 1.0");
        return false;
    }
    
    if (Averaging_Lot_Size <= 0 || Averaging_Lot_Size > 1.0) {
        Alert("ERROR: Averaging Lot Size must be between 0.01 and 1.0");
        return false;
    }
    
    // Validate trailing stop step
    if (Trailing_Stop_Step_Pips < 10 || Trailing_Stop_Step_Pips > 500) {
        Alert("ERROR: Trailing Stop Step must be between 10 and 500 pips");
        return false;
    }
    
    // Validate averaging drawdown (should be negative)
    if (Averaging_Drawdown_Pips > -100 || Averaging_Drawdown_Pips < -2000) {
        Alert("ERROR: Averaging Drawdown must be between -100 and -2000 pips");
        return false;
    }
    
    // Validate slippage
    if (Max_Slippage_Pips < MIN_SLIPPAGE || Max_Slippage_Pips > MAX_SLIPPAGE) {
        Alert("ERROR: Max Slippage must be between ", MIN_SLIPPAGE, " and ", MAX_SLIPPAGE, " pips");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| INITIALIZATION HELPER FUNCTIONS                                  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| FUNCTION: InitializeStatistics()                                 |
//| Purpose: Reset statistics to initial state                       |
//+------------------------------------------------------------------+
void InitializeStatistics() {
    Stats.totalTrades = 0;
    Stats.winTrades = 0;
    Stats.lossTrades = 0;
    Stats.winRate = 0.0;
    Stats.totalProfit = 0.0;
    Stats.totalLoss = 0.0;
    Stats.largestWin = 0.0;
    Stats.largestLoss = 0.0;
    Stats.profitFactor = 0.0;
    Stats.consecutiveWins = 0;
    Stats.consecutiveLosses = 0;
    Stats.sessionStartTime = TimeCurrent();
    Stats.lastTradeClosedTime = 0;
    Stats.isValid = true;
}

//+------------------------------------------------------------------+
//| FUNCTION: InitializeOrderData()                                  |
//| Purpose: Reset current order data to default state               |
//+------------------------------------------------------------------+
void InitializeOrderData() {
    CurrentOrder.ticket = -1;
    CurrentOrder.orderType = ORDER_TYPE_NONE;
    CurrentOrder.lots = 0.0;
    CurrentOrder.entryPrice = 0.0;
    CurrentOrder.currentSL = 0.0;
    CurrentOrder.currentTP = 0.0;
    CurrentOrder.highestPrice = 0.0;
    CurrentOrder.lowestPrice = 0.0;
    CurrentOrder.floatingProfit = 0.0;
    CurrentOrder.openTime = 0;
    CurrentOrder.modifyTime = 0;
    CurrentOrder.barsSinceEntry = 0;
    CurrentOrder.trailingStopActive = false;
    CurrentOrder.trailingStopLevel = 0.0;
    CurrentOrder.totalModifications = 0;
}

//+------------------------------------------------------------------+
//| FUNCTION: InitializeTradeSetup()                                 |
//| Purpose: Reset pending trade setup to default state              |
//+------------------------------------------------------------------+
void InitializeTradeSetup() {
    PendingSetup.orderType = ORDER_TYPE_NONE;
    PendingSetup.entryPrice = 0.0;
    PendingSetup.stopLossPrice = 0.0;
    PendingSetup.takeProfitPrice = 0.0;
    PendingSetup.firstCandleIndex = -1;
    PendingSetup.secondCandleIndex = -1;
    PendingSetup.firstCandleSize = 0.0;
    PendingSetup.secondCandleSize = 0.0;
    PendingSetup.emaValue = 0.0;
    PendingSetup.adxValue = 0.0;
    PendingSetup.bidPrice = 0.0;
    PendingSetup.askPrice = 0.0;
    PendingSetup.entryTime = 0;
    PendingSetup.isValid = false;
}

//+------------------------------------------------------------------+
//| FUNCTION: InitializeAveragingBasket()                            |
//| Purpose: Reset averaging basket to default state                 |
//+------------------------------------------------------------------+
void InitializeAveragingBasket() {
    Basket.mainOrderTicket = -1;
    Basket.averagingOrderTicket = -1;
    Basket.mainOrderLots = Initial_Lot_Size;
    Basket.averagingOrderLots = Averaging_Lot_Size;
    Basket.mainEntryPrice = 0.0;
    Basket.averagingEntryPrice = 0.0;
    Basket.basketProfit = 0.0;
    Basket.averagingTriggered = false;
    Basket.partialCloseDone = false;
    Basket.totalClosedLots = 0.0;
    Basket.lastTriggerTime = 0;
    Basket.isValid = false;
}

//+------------------------------------------------------------------+
//| FUNCTION: ResetGlobalState()                                     |
//| Purpose: Reset all global variables to initial state             |
//+------------------------------------------------------------------+
void ResetGlobalState() {
    CurrentOrderType = ORDER_TYPE_NONE;
    CurrentPhase = PHASE_NO_SIGNAL;
    CurrentSignalState = SIGNAL_STATE_NONE;
    LastExitReason = EXIT_REASON_NONE;
    
    CurrentEMA = 0.0;
    PreviousEMA = 0.0;
    CurrentADX = 0.0;
    PreviousADX = 0.0;
    
    FirstCandleOpen_G = 0.0;
    FirstCandleClose_G = 0.0;
    FirstCandleHigh_G = 0.0;
    FirstCandleLow_G = 0.0;
    FirstCandleSize_G = 0.0;
    
    SecondCandleOpen_G = 0.0;
    SecondCandleClose_G = 0.0;
    SecondCandleHigh_G = 0.0;
    SecondCandleLow_G = 0.0;
    SecondCandleSize_G = 0.0;
    
    ErrorCount = 0;
    LastProcessedBar = -1;
    TotalTickProcessed = 0;
    
    InitializeOrderData();
    InitializeTradeSetup();
    InitializeAveragingBasket();
    InitializeStatistics();
}

//+------------------------------------------------------------------+
//| ==================== SECTION 3: LOGGER ========================= |
//| Logging and Debugging Functions                                  |
//| Estimated Lines: ~300 (simplified)                               |
//+------------------------------------------------------------------+

// Log level flags
bool EnableTradeLog = true;
bool EnableErrorLog = true;
bool EnableSignalLog = true;
bool EnableDebugLog = false;
bool EnableInfoLog = true;

//+------------------------------------------------------------------+
//| FUNCTION: LogInfo()                                              |
//| Purpose: Log informational message                               |
//+------------------------------------------------------------------+
void LogInfo(string message) {
    if (!EnableInfoLog) return;
    Print("INFO: ", message);
}

//+------------------------------------------------------------------+
//| FUNCTION: LogDebug()                                             |
//| Purpose: Log debug message                                       |
//+------------------------------------------------------------------+
void LogDebug(string message) {
    if (!EnableDebugLog) return;
    Print("DEBUG: ", message);
}

//+------------------------------------------------------------------+
//| FUNCTION: LogError()                                             |
//| Purpose: Log error event with context                            |
//+------------------------------------------------------------------+
void LogError(int errorCode, string errorContext, string additionalInfo = "") {
    if (!EnableErrorLog) return;
    Print("ERROR [", errorCode, "]: ", errorContext, " | ", GetErrorDescription(errorCode), 
          (additionalInfo != "" ? " | " + additionalInfo : ""));
}

//+------------------------------------------------------------------+
//| FUNCTION: LogWarning()                                           |
//| Purpose: Log warning event                                       |
//+------------------------------------------------------------------+
void LogWarning(string message) {
    Print("WARNING: ", message);
}

//+------------------------------------------------------------------+
//| FUNCTION: LogWarn()                                              |
//| Purpose: Log warning event (alias)                               |
//+------------------------------------------------------------------+
void LogWarn(string message) {
    Print("WARNING: ", message);
}

//+------------------------------------------------------------------+
//| FUNCTION: LogTradeEntry()                                        |
//| Purpose: Log trade entry event with full details                 |
//+------------------------------------------------------------------+
void LogTradeEntry(int ticket, int orderType, double lots, double entryPrice, double sl, double tp) {
    if (!EnableTradeLog) return;
    
    string orderTypeStr = (orderType == OP_BUY) ? "BUY" : "SELL";
    Print("========== TRADE ENTRY ==========");
    Print("Ticket: ", ticket);
    Print("Type: ", orderTypeStr);
    Print("Lots: ", DoubleToString(lots, 2));
    Print("Entry Price: ", DoubleToString(entryPrice, Digits));
    Print("SL: ", (sl > 0 ? DoubleToString(sl, Digits) : "None"));
    Print("TP: ", (tp > 0 ? DoubleToString(tp, Digits) : "None"));
    Print("Balance: ", DoubleToString(AccountBalance(), 2));
    Print("=================================");
}

//+------------------------------------------------------------------+
//| FUNCTION: LogTradeExit()                                         |
//| Purpose: Log trade exit event with results                       |
//+------------------------------------------------------------------+
void LogTradeExit(int ticket, int orderType, double lots, double entryPrice, double exitPrice, double profit, string exitReason) {
    if (!EnableTradeLog) return;
    
    string orderTypeStr = (orderType == OP_BUY) ? "BUY" : "SELL";
    Print("========== TRADE EXIT ==========");
    Print("Ticket: ", ticket);
    Print("Type: ", orderTypeStr);
    Print("Lots: ", DoubleToString(lots, 2));
    Print("Entry: ", DoubleToString(entryPrice, Digits));
    Print("Exit: ", DoubleToString(exitPrice, Digits));
    Print("Profit: ", DoubleToString(profit, 2));
    Print("Reason: ", exitReason);
    Print("=================================");
}

//+------------------------------------------------------------------+
//| FUNCTION: Log1stCandleDetected()                                 |
//| Purpose: Log 1st candle confirmation detection                   |
//+------------------------------------------------------------------+
void Log1stCandleDetected(int orderType, double candleSize, double emaValue) {
    if (!EnableSignalLog) return;
    
    string typeStr = (orderType == OP_BUY) ? "BUY" : "SELL";
    Print("SIGNAL: 1st Candle Detected | Type: ", typeStr, 
          " | Size: ", DoubleToString(candleSize, 1), " pips | EMA: ", DoubleToString(emaValue, Digits));
}

//+------------------------------------------------------------------+
//| FUNCTION: Log2ndCandleConfirmed()                                |
//| Purpose: Log 2nd candle confirmation                             |
//+------------------------------------------------------------------+
void Log2ndCandleConfirmed(int orderType, double candleSize, double tolerance) {
    if (!EnableSignalLog) return;
    
    string typeStr = (orderType == OP_BUY) ? "BUY" : "SELL";
    Print("SIGNAL: 2nd Candle Confirmed | Type: ", typeStr, 
          " | Size: ", DoubleToString(candleSize, 1), " pips | Tolerance: ", DoubleToString(tolerance, 1), "%");
}

//+------------------------------------------------------------------+
//| FUNCTION: LogADXCheck()                                          |
//| Purpose: Log ADX verification result                             |
//+------------------------------------------------------------------+
void LogADXCheck(double adxValue, bool passed) {
    if (!EnableSignalLog) return;
    
    string result = passed ? "PASSED" : "FAILED";
    Print("ADX CHECK: Value=", DoubleToString(adxValue, 2), " | Threshold=", ADX_Threshold, " | ", result);
}

//+------------------------------------------------------------------+
//| FUNCTION: LogOrderOpening()                                      |
//| Purpose: Log order opening details                               |
//+------------------------------------------------------------------+
void LogOrderOpening(int ticket, string symbol, int orderType, double lots, 
                     double entryPrice, double sl, double tp, int magicNumber) {
    LogTradeEntry(ticket, orderType, lots, entryPrice, sl, tp);
}

//+------------------------------------------------------------------+
//| FUNCTION: LogOrderModification()                                 |
//| Purpose: Log order modification event                            |
//+------------------------------------------------------------------+
void LogOrderModification(int ticket, double oldSL, double newSL, double oldTP, double newTP) {
    Print("ORDER MODIFY: Ticket ", ticket, " | SL: ", oldSL, " -> ", newSL, " | TP: ", oldTP, " -> ", newTP);
}

//+------------------------------------------------------------------+
//| FUNCTION: LogPartialClose()                                      |
//| Purpose: Log partial close event                                 |
//+------------------------------------------------------------------+
void LogPartialClose(int ticket, double lotsRemaining, double lotsClosed, double profit) {
    Print("PARTIAL CLOSE: Ticket ", ticket, " | Closed: ", lotsClosed, " | Remaining: ", lotsRemaining, " | Profit: ", profit);
}

//+------------------------------------------------------------------+
//| FUNCTION: LogOrderClosure()                                      |
//| Purpose: Log order closure details                               |
//+------------------------------------------------------------------+
void LogOrderClosure(int ticket, string symbol, int orderType, double lots, double entryPrice, double exitPrice) {
    Print("ORDER CLOSED: Ticket ", ticket, " | Entry: ", entryPrice, " | Exit: ", exitPrice);
}

//+------------------------------------------------------------------+
//| FUNCTION: LogPartialClosure()                                    |
//| Purpose: Log partial closure details                             |
//+------------------------------------------------------------------+
void LogPartialClosure(int ticket, string symbol, int orderType, double lotsClosed, double lotsRemaining, double entryPrice, double exitPrice) {
    Print("PARTIAL CLOSE: Ticket ", ticket, " | Closed: ", lotsClosed, " | Remaining: ", lotsRemaining);
}

//+------------------------------------------------------------------+
//| FUNCTION: LogAveragingEntry()                                    |
//| Purpose: Log averaging order entry                               |
//+------------------------------------------------------------------+
void LogAveragingEntry(int ticket, int mainTicket, double lots, double entryPrice, double drawdown) {
    Print("AVERAGING ORDER: Ticket: ", ticket, " | Main: ", mainTicket, " | Lots: ", lots, " | Drawdown: ", drawdown);
}

//+------------------------------------------------------------------+
//| FUNCTION: UpdateChartComment()                                   |
//| Purpose: Update chart comment with current EA status             |
//+------------------------------------------------------------------+
void UpdateChartComment(string message) {
    string comment = "\n";
    comment += "================================\n";
    comment += "  " + EA_NAME + " v" + EA_VERSION + "\n";
    comment += "================================\n\n";
    comment += "Symbol: " + Symbol() + " | TF: " + GetTimeframeString(Period()) + "\n";
    comment += "Account: " + IntegerToString(AccountNumber()) + "\n";
    comment += "Balance: $" + DoubleToString(AccountBalance(), 2) + "\n";
    comment += "Equity: $" + DoubleToString(AccountEquity(), 2) + "\n\n";
    comment += "Current Phase: " + GetPhaseString(CurrentPhase) + "\n";
    comment += "Signal State: " + GetSignalStateString(CurrentSignalState) + "\n\n";
    comment += "Total Trades: " + IntegerToString(Stats.totalTrades) + "\n";
    comment += "Win Rate: " + DoubleToString(Stats.winRate, 1) + "%\n";
    comment += "Net Profit: $" + DoubleToString(Stats.totalProfit + Stats.totalLoss, 2) + "\n\n";
    comment += "Status: " + message + "\n";
    comment += "================================\n";
    
    Comment(comment);
}

//+------------------------------------------------------------------+
//| =================== SECTION 4: STRATEGY ======================== |
//| Core Signal Detection - EMA, Crossover, ADX                      |
//| Estimated Lines: ~500                                            |
//+------------------------------------------------------------------+

// Strategy constants
#define MIN_BARS_FOR_EMA 100
#define MIN_BARS_FOR_ADX 50
#define EMA_CACHE_SIZE 10
#define ADX_CACHE_SIZE 10

// Strategy global variables
double EMA_Buffer[10];
int EMA_BufferIndex = 0;
bool EMA_Ready = false;
datetime LastEMA_Calculation = 0;

double ADX_Buffer[10];
double ADX_Plus_Buffer[10];
double ADX_Minus_Buffer[10];
int ADX_BufferIndex = 0;
bool ADX_Ready = false;
datetime LastADX_Calculation = 0;

bool CrossoverDetected = false;
ENUM_ORDER_TYPE_EA CrossoverType = ORDER_TYPE_NONE;
int CrossoverBarIndex = -1;
datetime CrossoverTime = 0;

double PreviousBarEMA = 0.0;
double PreviousBarClose = 0.0;
double CurrentBarEMA = 0.0;
double CurrentBarClose = 0.0;

bool StrategyInitialized = false;
int LastProcessedBarForSignal = -1;

//+------------------------------------------------------------------+
//| FUNCTION: InitializeStrategy()                                   |
//| Purpose: Initialize strategy system and validate data            |
//| Returns: true on success, false on failure                       |
//+------------------------------------------------------------------+
bool InitializeStrategy() {
    LogInfo("Initializing Strategy System");
    
    int barsAvailable = Bars;
    
    if (barsAvailable < MIN_BARS_FOR_EMA) {
        LogError(ERR_SYMBOL_NOT_READY, "InitializeStrategy", 
                 "Insufficient bars for EMA. Need: " + IntegerToString(MIN_BARS_FOR_EMA) + 
                 " | Have: " + IntegerToString(barsAvailable));
        return false;
    }
    
    // Initialize EMA buffer
    ArrayInitialize(EMA_Buffer, 0.0);
    EMA_BufferIndex = 0;
    
    // Initialize ADX buffer
    ArrayInitialize(ADX_Buffer, 0.0);
    ArrayInitialize(ADX_Plus_Buffer, 0.0);
    ArrayInitialize(ADX_Minus_Buffer, 0.0);
    ADX_BufferIndex = 0;
    
    // Calculate initial values
    if (!CalculateEMA()) {
        LogError(ERR_EMA_NOT_READY, "InitializeStrategy", "Failed to calculate initial EMA");
        return false;
    }
    
    if (!CalculateADX()) {
        LogError(ERR_ADX_NOT_READY, "InitializeStrategy", "Failed to calculate initial ADX");
        return false;
    }
    
    StrategyInitialized = true;
    
    LogInfo("Strategy System Initialized Successfully");
    LogInfo("EMA Period: " + IntegerToString(EMA_Period) + " | Current EMA: " + DoubleToString(CurrentEMA, Digits));
    LogInfo("ADX Period: " + IntegerToString(ADX_Period) + " | Current ADX: " + DoubleToString(CurrentADX, 2));
    
    return true;
}

//+------------------------------------------------------------------+
//| FUNCTION: CalculateEMA()                                         |
//| Purpose: Calculate EMA for current and previous bar              |
//| Returns: true on success, false on failure                       |
//+------------------------------------------------------------------+
bool CalculateEMA() {
    double emaBar1 = iMA(Symbol(), Period(), EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 1);
    
    if (emaBar1 <= 0.0) {
        LogError(ERR_EMA_NOT_READY, "CalculateEMA", "Failed to calculate EMA for bar 1");
        return false;
    }
    
    double emaBar2 = iMA(Symbol(), Period(), EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 2);
    
    if (emaBar2 <= 0.0) {
        LogError(ERR_EMA_NOT_READY, "CalculateEMA", "Failed to calculate EMA for bar 2");
        return false;
    }
    
    PreviousEMA = emaBar2;
    CurrentEMA = emaBar1;
    
    EMA_Buffer[EMA_BufferIndex] = emaBar1;
    EMA_BufferIndex = (EMA_BufferIndex + 1) % EMA_CACHE_SIZE;
    
    EMA_Ready = true;
    LastEMA_Calculation = TimeCurrent();
    
    return true;
}

//+------------------------------------------------------------------+
//| FUNCTION: GetEMAValue()                                          |
//| Purpose: Get EMA value for specified bar                         |
//| Input:   shift - bar index (1 = previous closed bar)             |
//| Returns: EMA value, 0.0 on error                                 |
//+------------------------------------------------------------------+
double GetEMAValue(int shift) {
    if (shift < 0) {
        return 0.0;
    }
    
    double emaValue = iMA(Symbol(), Period(), EMA_Period, 0, MODE_EMA, PRICE_CLOSE, shift);
    
    if (emaValue <= 0.0) {
        return 0.0;
    }
    
    return emaValue;
}

//+------------------------------------------------------------------+
//| FUNCTION: IsEMAReady()                                           |
//| Purpose: Check if EMA is ready for trading                       |
//| Returns: true if ready, false otherwise                          |
//+------------------------------------------------------------------+
bool IsEMAReady() {
    if (!EMA_Ready) return false;
    if (CurrentEMA <= 0.0) return false;
    if (PreviousEMA <= 0.0) return false;
    return true;
}

//+------------------------------------------------------------------+
//| FUNCTION: UpdateEMA()                                            |
//| Purpose: Update EMA values for new bar                           |
//| Returns: true on success, false on failure                       |
//+------------------------------------------------------------------+
bool UpdateEMA() {
    return CalculateEMA();
}

//+------------------------------------------------------------------+
//| FUNCTION: CalculateADX()                                         |
//| Purpose: Calculate ADX for current bar                           |
//| Returns: true on success, false on failure                       |
//+------------------------------------------------------------------+
bool CalculateADX() {
    double adxBar1 = iADX(Symbol(), Period(), ADX_Period, PRICE_CLOSE, MODE_MAIN, 1);
    
    if (adxBar1 < 0.0) {
        LogError(ERR_ADX_NOT_READY, "CalculateADX", "Failed to calculate ADX for bar 1");
        return false;
    }
    
    double plusDI = iADX(Symbol(), Period(), ADX_Period, PRICE_CLOSE, MODE_PLUSDI, 1);
    double minusDI = iADX(Symbol(), Period(), ADX_Period, PRICE_CLOSE, MODE_MINUSDI, 1);
    
    double adxBar2 = iADX(Symbol(), Period(), ADX_Period, PRICE_CLOSE, MODE_MAIN, 2);
    
    PreviousADX = adxBar2;
    CurrentADX = adxBar1;
    
    ADX_Buffer[ADX_BufferIndex] = adxBar1;
    ADX_Plus_Buffer[ADX_BufferIndex] = plusDI;
    ADX_Minus_Buffer[ADX_BufferIndex] = minusDI;
    ADX_BufferIndex = (ADX_BufferIndex + 1) % ADX_CACHE_SIZE;
    
    ADX_Ready = true;
    LastADX_Calculation = TimeCurrent();
    
    return true;
}

//+------------------------------------------------------------------+
//| FUNCTION: GetADXValue()                                          |
//| Purpose: Get ADX value for specified bar                         |
//+------------------------------------------------------------------+
double GetADXValue(int shift) {
    if (shift < 0) return -1.0;
    return iADX(Symbol(), Period(), ADX_Period, PRICE_CLOSE, MODE_MAIN, shift);
}

//+------------------------------------------------------------------+
//| FUNCTION: IsADXReady()                                           |
//| Purpose: Check if ADX is ready for trading                       |
//+------------------------------------------------------------------+
bool IsADXReady() {
    if (!ADX_Ready) return false;
    if (CurrentADX < 0.0) return false;
    return true;
}

//+------------------------------------------------------------------+
//| FUNCTION: IsADXAboveThreshold()                                  |
//| Purpose: Check if current ADX is above threshold                 |
//+------------------------------------------------------------------+
bool IsADXAboveThreshold() {
    if (!IsADXReady()) return false;
    
    double adxValue = CurrentADX;
    bool aboveThreshold = (adxValue >= ADX_Threshold);
    
    LogADXCheck(adxValue, aboveThreshold);
    
    return aboveThreshold;
}

//+------------------------------------------------------------------+
//| FUNCTION: UpdateADX()                                            |
//| Purpose: Update ADX values for new bar                           |
//+------------------------------------------------------------------+
bool UpdateADX() {
    return CalculateADX();
}

//+------------------------------------------------------------------+
//| FUNCTION: GetCurrentADX()                                        |
//| Purpose: Get current ADX value                                   |
//+------------------------------------------------------------------+
double GetCurrentADX() {
    return CurrentADX;
}

//+------------------------------------------------------------------+
//| FUNCTION: DetectCrossover()                                      |
//| Purpose: Detect EMA crossover on closed bar                      |
//+------------------------------------------------------------------+
bool DetectCrossover() {
    double closeBar1 = GetCandleClose(1);
    double closeBar2 = GetCandleClose(2);
    
    if (closeBar1 <= 0.0 || closeBar2 <= 0.0) {
        return false;
    }
    
    double emaBar1 = GetEMAValue(1);
    double emaBar2 = GetEMAValue(2);
    
    if (emaBar1 <= 0.0 || emaBar2 <= 0.0) {
        return false;
    }
    
    // Check for BULLISH crossover (cross ABOVE EMA)
    if (closeBar2 <= emaBar2 && closeBar1 > emaBar1) {
        LogInfo("BULLISH CROSSOVER DETECTED on bar 1");
        CrossoverDetected = true;
        CrossoverType = ORDER_TYPE_BUY;
        CrossoverBarIndex = 1;
        CrossoverTime = GetBarTime(1);
        return true;
    }
    
    // Check for BEARISH crossover (cross BELOW EMA)
    if (closeBar2 >= emaBar2 && closeBar1 < emaBar1) {
        LogInfo("BEARISH CROSSOVER DETECTED on bar 1");
        CrossoverDetected = true;
        CrossoverType = ORDER_TYPE_SELL;
        CrossoverBarIndex = 1;
        CrossoverTime = GetBarTime(1);
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| FUNCTION: ResetCrossover()                                       |
//| Purpose: Reset crossover detection state                         |
//+------------------------------------------------------------------+
void ResetCrossover() {
    CrossoverDetected = false;
    CrossoverType = ORDER_TYPE_NONE;
    CrossoverBarIndex = -1;
    CrossoverTime = 0;
}

//+------------------------------------------------------------------+
//| FUNCTION: IsBuySignalDetected()                                  |
//| Purpose: Comprehensive BUY signal detection                      |
//+------------------------------------------------------------------+
bool IsBuySignalDetected() {
    if (!StrategyInitialized) return false;
    if (!IsEMAReady()) return false;
    
    if (!DetectCrossover()) return false;
    if (CrossoverType != ORDER_TYPE_BUY) return false;
    
    double closeBar1 = GetCandleClose(1);
    double emaBar1 = GetEMAValue(1);
    
    if (closeBar1 <= emaBar1) return false;
    
    double candleSize = GetCandleBodySize(1);
    
    if (candleSize < Candle_Size_Min_Pips || candleSize > Candle_Size_Max_Pips) return false;
    
    if (!IsBullishCandle(1)) return false;
    
    LogInfo("BUY SIGNAL DETECTED | Close: " + DoubleToString(closeBar1, Digits) + 
            " | EMA: " + DoubleToString(emaBar1, Digits) + 
            " | Size: " + DoubleToString(candleSize, 1) + " pips");
    
    Log1stCandleDetected(OP_BUY, candleSize, emaBar1);
    
    return true;
}

//+------------------------------------------------------------------+
//| FUNCTION: IsSellSignalDetected()                                 |
//| Purpose: Comprehensive SELL signal detection                     |
//+------------------------------------------------------------------+
bool IsSellSignalDetected() {
    if (!StrategyInitialized) return false;
    if (!IsEMAReady()) return false;
    
    if (!DetectCrossover()) return false;
    if (CrossoverType != ORDER_TYPE_SELL) return false;
    
    double closeBar1 = GetCandleClose(1);
    double emaBar1 = GetEMAValue(1);
    
    if (closeBar1 >= emaBar1) return false;
    
    double candleSize = GetCandleBodySize(1);
    
    if (candleSize < Candle_Size_Min_Pips || candleSize > Candle_Size_Max_Pips) return false;
    
    if (!IsBearishCandle(1)) return false;
    
    LogInfo("SELL SIGNAL DETECTED | Close: " + DoubleToString(closeBar1, Digits) + 
            " | EMA: " + DoubleToString(emaBar1, Digits) + 
            " | Size: " + DoubleToString(candleSize, 1) + " pips");
    
    Log1stCandleDetected(OP_SELL, candleSize, emaBar1);
    
    return true;
}

//+------------------------------------------------------------------+
//| FUNCTION: UpdateStrategy()                                       |
//| Purpose: Update strategy indicators for new bar                  |
//+------------------------------------------------------------------+
bool UpdateStrategy() {
    if (!UpdateEMA()) return false;
    if (!UpdateADX()) return false;
    return true;
}

//+------------------------------------------------------------------+
//| FUNCTION: CheckForNewSignal()                                    |
//| Purpose: Check for new entry signal on bar close                 |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_EA CheckForNewSignal() {
    int currentBar = iBarShift(Symbol(), Period(), GetBarTime(1));
    
    if (currentBar == LastProcessedBarForSignal) {
        return ORDER_TYPE_NONE;
    }
    
    if (!UpdateStrategy()) {
        return ORDER_TYPE_NONE;
    }
    
    ResetCrossover();
    
    if (IsBuySignalDetected()) {
        LastProcessedBarForSignal = currentBar;
        return ORDER_TYPE_BUY;
    }
    
    if (IsSellSignalDetected()) {
        LastProcessedBarForSignal = currentBar;
        return ORDER_TYPE_SELL;
    }
    
    return ORDER_TYPE_NONE;
}

//+------------------------------------------------------------------+
//| ================= SECTION 5: ENTRY SIGNALS ===================== |
//| 2-Candle Confirmation State Machine                              |
//| Estimated Lines: ~500                                            |
//+------------------------------------------------------------------+

// Entry signal constants
#define MAX_CANDLE_AGE_BARS 5
#define CONFIRMATION_TIMEOUT_BARS 10

// Entry signal state machine
ENUM_TRADE_PHASE EntryPhase = PHASE_NO_SIGNAL;
ENUM_ORDER_TYPE_EA PendingSignalType = ORDER_TYPE_NONE;

// 1st Candle tracking
bool FirstCandleDetected = false;
int FirstCandleBarIndex = -1;
datetime FirstCandleTime = 0;
double FirstCandleOpen = 0.0;
double FirstCandleClose = 0.0;
double FirstCandleHigh = 0.0;
double FirstCandleLow = 0.0;
double FirstCandleSize = 0.0;
double FirstCandleEMA = 0.0;
int FirstCandleDirection = 0;

// 2nd Candle tracking
bool SecondCandleDetected = false;
int SecondCandleBarIndex = -1;
datetime SecondCandleTime = 0;
double SecondCandleOpen = 0.0;
double SecondCandleClose = 0.0;
double SecondCandleHigh = 0.0;
double SecondCandleLow = 0.0;
double SecondCandleSize = 0.0;
int SecondCandleDirection = 0;

// Confirmation tracking
bool ConfirmationComplete = false;
bool ReadyForEntry = false;
datetime ConfirmationStartTime = 0;
int ConfirmationAttempts = 0;
bool EntrySignalsInitialized = false;

//+------------------------------------------------------------------+
//| FUNCTION: InitializeEntrySignals()                               |
//+------------------------------------------------------------------+
bool InitializeEntrySignals() {
    LogInfo("Initializing Entry Signals System");
    ResetEntrySignalState();
    EntrySignalsInitialized = true;
    LogInfo("Entry Signals System Initialized");
    return true;
}

//+------------------------------------------------------------------+
//| FUNCTION: ResetEntrySignalState()                                |
//+------------------------------------------------------------------+
void ResetEntrySignalState() {
    EntryPhase = PHASE_NO_SIGNAL;
    PendingSignalType = ORDER_TYPE_NONE;
    
    FirstCandleDetected = false;
    FirstCandleBarIndex = -1;
    FirstCandleTime = 0;
    FirstCandleOpen = 0.0;
    FirstCandleClose = 0.0;
    FirstCandleHigh = 0.0;
    FirstCandleLow = 0.0;
    FirstCandleSize = 0.0;
    FirstCandleEMA = 0.0;
    FirstCandleDirection = 0;
    
    SecondCandleDetected = false;
    SecondCandleBarIndex = -1;
    SecondCandleTime = 0;
    SecondCandleOpen = 0.0;
    SecondCandleClose = 0.0;
    SecondCandleHigh = 0.0;
    SecondCandleLow = 0.0;
    SecondCandleSize = 0.0;
    SecondCandleDirection = 0;
    
    ConfirmationComplete = false;
    ReadyForEntry = false;
    ConfirmationStartTime = 0;
    ConfirmationAttempts = 0;
}

//+------------------------------------------------------------------+
//| FUNCTION: SetPhase()                                             |
//+------------------------------------------------------------------+
void SetPhase(ENUM_TRADE_PHASE newPhase) {
    ENUM_TRADE_PHASE oldPhase = EntryPhase;
    EntryPhase = newPhase;
    CurrentPhase = newPhase;
    
    if (oldPhase != newPhase) {
        LogInfo("Phase Transition: " + GetPhaseString(oldPhase) + " -> " + GetPhaseString(newPhase));
    }
}

//+------------------------------------------------------------------+
//| FUNCTION: Detect1stCandle()                                      |
//+------------------------------------------------------------------+
bool Detect1stCandle() {
    if (!EntrySignalsInitialized) return false;
    if (FirstCandleDetected) return true;
    
    ENUM_ORDER_TYPE_EA signalType = CheckForNewSignal();
    
    if (signalType == ORDER_TYPE_NONE) return false;
    
    int barIndex = 1;
    
    double candleOpen = GetCandleOpen(barIndex);
    double candleClose = GetCandleClose(barIndex);
    double candleHigh = GetCandleHigh(barIndex);
    double candleLow = GetCandleLow(barIndex);
    
    if (candleOpen <= 0.0 || candleClose <= 0.0) return false;
    
    double bodySize = GetCandleBodySize(barIndex);
    
    // Validate candle body size
    if (bodySize < Candle_Size_Min_Pips || bodySize > Candle_Size_Max_Pips) return false;
    
    double emaValue = GetEMAValue(barIndex);
    if (emaValue <= 0.0) return false;
    
    // Validate EMA cross
    if (signalType == ORDER_TYPE_BUY && candleClose <= emaValue) return false;
    if (signalType == ORDER_TYPE_SELL && candleClose >= emaValue) return false;
    
    int direction = GetCandleDirection(barIndex);
    if (direction == 0) return false;
    
    if (signalType == ORDER_TYPE_BUY && direction != 1) return false;
    if (signalType == ORDER_TYPE_SELL && direction != -1) return false;
    
    // Store 1st candle data
    FirstCandleDetected = true;
    FirstCandleBarIndex = barIndex;
    FirstCandleTime = GetBarTime(barIndex);
    FirstCandleOpen = candleOpen;
    FirstCandleClose = candleClose;
    FirstCandleHigh = candleHigh;
    FirstCandleLow = candleLow;
    FirstCandleSize = bodySize;
    FirstCandleEMA = emaValue;
    FirstCandleDirection = direction;
    PendingSignalType = signalType;
    
    SetPhase(PHASE_1ST_CANDLE_DETECTED);
    ConfirmationStartTime = TimeCurrent();
    
    LogInfo("1ST CANDLE DETECTED | Type: " + (signalType == ORDER_TYPE_BUY ? "BUY" : "SELL") + 
            " | Size: " + DoubleToString(bodySize, 1) + " pips");
    
    return true;
}

//+------------------------------------------------------------------+
//| FUNCTION: Detect2ndCandle()                                      |
//+------------------------------------------------------------------+
bool Detect2ndCandle() {
    if (!FirstCandleDetected) return false;
    if (SecondCandleDetected) return true;
    
    // Check 1st candle is still valid
    int barsSince = iBarShift(Symbol(), Period(), FirstCandleTime);
    if (barsSince > MAX_CANDLE_AGE_BARS) {
        LogWarning("1st candle expired");
        ResetEntrySignalState();
        return false;
    }
    
    int barIndex = 1;
    datetime barTime = GetBarTime(barIndex);
    
    if (barTime <= FirstCandleTime) return false;
    
    double candleOpen = GetCandleOpen(barIndex);
    double candleClose = GetCandleClose(barIndex);
    double candleHigh = GetCandleHigh(barIndex);
    double candleLow = GetCandleLow(barIndex);
    
    if (candleOpen <= 0.0 || candleClose <= 0.0) return false;
    
    double bodySize = GetCandleBodySize(barIndex);
    
    // Validate tolerance
    double minAcceptableSize = FirstCandleSize * (Candle_Size_Tolerance_Pct / 100.0);
    if (bodySize < minAcceptableSize) {
        LogWarning("2nd candle too small");
        ResetEntrySignalState();
        return false;
    }
    
    // Also check it's not too large (max 110%)
    double maxAcceptableSize = FirstCandleSize * 1.10;
    if (bodySize > maxAcceptableSize) {
        LogWarning("2nd candle too large");
        ResetEntrySignalState();
        return false;
    }
    
    int direction = GetCandleDirection(barIndex);
    if (direction == 0) {
        ResetEntrySignalState();
        return false;
    }
    
    // Validate same direction
    if (direction != FirstCandleDirection) {
        LogWarning("2nd candle direction mismatch");
        ResetEntrySignalState();
        return false;
    }
    
    // Validate close progression
    if (PendingSignalType == ORDER_TYPE_BUY && candleClose < FirstCandleClose) {
        ResetEntrySignalState();
        return false;
    }
    if (PendingSignalType == ORDER_TYPE_SELL && candleClose > FirstCandleClose) {
        ResetEntrySignalState();
        return false;
    }
    
    // Store 2nd candle data
    SecondCandleDetected = true;
    SecondCandleBarIndex = barIndex;
    SecondCandleTime = barTime;
    SecondCandleOpen = candleOpen;
    SecondCandleClose = candleClose;
    SecondCandleHigh = candleHigh;
    SecondCandleLow = candleLow;
    SecondCandleSize = bodySize;
    SecondCandleDirection = direction;
    
    SetPhase(PHASE_2ND_CANDLE_CONFIRMED);
    ConfirmationComplete = true;
    
    double tolerancePercent = (bodySize / FirstCandleSize) * 100.0;
    
    LogInfo("2ND CANDLE CONFIRMED | Size: " + DoubleToString(bodySize, 1) + 
            " pips | Tolerance: " + DoubleToString(tolerancePercent, 1) + "%");
    
    Log2ndCandleConfirmed(PendingSignalType == ORDER_TYPE_BUY ? OP_BUY : OP_SELL, bodySize, tolerancePercent);
    
    return true;
}

//+------------------------------------------------------------------+
//| FUNCTION: CheckEntryReadiness()                                  |
//+------------------------------------------------------------------+
bool CheckEntryReadiness() {
    if (!ConfirmationComplete) return false;
    if (!FirstCandleDetected || !SecondCandleDetected) return false;
    
    int barsSince2nd = iBarShift(Symbol(), Period(), SecondCandleTime);
    if (barsSince2nd > 2) {
        ResetEntrySignalState();
        return false;
    }
    
    // Check ADX at 3rd candle open
    if (!IsADXAboveThreshold()) {
        LogWarning("ADX below threshold - signal invalidated");
        ResetEntrySignalState();
        return false;
    }
    
    ReadyForEntry = true;
    SetPhase(PHASE_READY_FOR_ENTRY);
    
    LogInfo("READY FOR ENTRY | Type: " + (PendingSignalType == ORDER_TYPE_BUY ? "BUY" : "SELL") + 
            " | ADX: " + DoubleToString(GetCurrentADX(), 2));
    
    return true;
}

//+------------------------------------------------------------------+
//| FUNCTION: IsReadyForEntry()                                      |
//+------------------------------------------------------------------+
bool IsReadyForEntry() {
    return ReadyForEntry && ConfirmationComplete;
}

//+------------------------------------------------------------------+
//| FUNCTION: GetPendingSignalType()                                 |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_EA GetPendingSignalType() {
    if (!IsReadyForEntry()) return ORDER_TYPE_NONE;
    return PendingSignalType;
}

//+------------------------------------------------------------------+
//| FUNCTION: GetEntryPrice()                                        |
//+------------------------------------------------------------------+
double GetEntryPrice() {
    if (!IsReadyForEntry()) return 0.0;
    
    RefreshRates();
    
    if (PendingSignalType == ORDER_TYPE_BUY) {
        return NormalizePrice(Ask);
    } else if (PendingSignalType == ORDER_TYPE_SELL) {
        return NormalizePrice(Bid);
    }
    
    return 0.0;
}

//+------------------------------------------------------------------+
//| FUNCTION: MarkEntryExecuted()                                    |
//+------------------------------------------------------------------+
void MarkEntryExecuted() {
    SetPhase(PHASE_ENTRY_EXECUTED);
    ReadyForEntry = false;
    LogInfo("Entry executed - Entry signal state marked as executed");
}

//+------------------------------------------------------------------+
//| FUNCTION: UpdateEntrySignals()                                   |
//+------------------------------------------------------------------+
bool UpdateEntrySignals() {
    if (!EntrySignalsInitialized) return false;
    
    // Check confirmation timeout
    if (ConfirmationStartTime > 0) {
        int barsSinceStart = (int)((TimeCurrent() - ConfirmationStartTime) / PeriodSeconds());
        if (barsSinceStart > CONFIRMATION_TIMEOUT_BARS) {
            ResetEntrySignalState();
            return false;
        }
    }
    
    // State machine progression
    switch (EntryPhase) {
        case PHASE_NO_SIGNAL:
            Detect1stCandle();
            break;
            
        case PHASE_1ST_CANDLE_DETECTED:
            Detect2ndCandle();
            break;
            
        case PHASE_2ND_CANDLE_CONFIRMED:
            CheckEntryReadiness();
            break;
            
        case PHASE_READY_FOR_ENTRY:
        case PHASE_ENTRY_EXECUTED:
            break;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| FUNCTION: CheckForNewBar()                                       |
//+------------------------------------------------------------------+
bool CheckForNewBar() {
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(Symbol(), Period(), 0);
    
    if (currentBarTime != lastBarTime) {
        lastBarTime = currentBarTime;
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| ================ SECTION 6: POSITION SIZING ==================== |
//| Lot Calculation, Validation, and Basket Management               |
//| Estimated Lines: ~400                                            |
//+------------------------------------------------------------------+

#define MAX_TOTAL_EXPOSURE_LOTS 1.0
#define MIN_FREE_MARGIN_PERCENT 10.0
#define SAFETY_MARGIN_MULTIPLIER 1.2

double CalculatedInitialLots = 0.0;
double CalculatedAveragingLots = 0.0;
double CurrentTotalExposure = 0.0;
bool PositionSizingInitialized = false;

//+------------------------------------------------------------------+
//| FUNCTION: InitializePositionSizing()                             |
//+------------------------------------------------------------------+
bool InitializePositionSizing() {
    LogInfo("Initializing Position Sizing System");
    
    CalculatedInitialLots = NormalizeLots(Initial_Lot_Size);
    CalculatedAveragingLots = NormalizeLots(Averaging_Lot_Size);
    
    if (CalculatedInitialLots <= 0.0) {
        LogError(ERR_INVALID_LOT_SIZE, "InitializePositionSizing", "Initial lot size is invalid");
        return false;
    }
    
    if (CalculatedAveragingLots <= 0.0) {
        LogError(ERR_INVALID_LOT_SIZE, "InitializePositionSizing", "Averaging lot size is invalid");
        return false;
    }
    
    PositionSizingInitialized = true;
    
    LogInfo("Position Sizing Initialized | Initial: " + DoubleToString(CalculatedInitialLots, 2) + 
            " | Averaging: " + DoubleToString(CalculatedAveragingLots, 2));
    
    return true;
}

//+------------------------------------------------------------------+
//| FUNCTION: GetInitialLots()                                       |
//+------------------------------------------------------------------+
double GetInitialLots() {
    if (!PositionSizingInitialized) return 0.0;
    return CalculatedInitialLots;
}

//+------------------------------------------------------------------+
//| FUNCTION: GetAveragingLots()                                     |
//+------------------------------------------------------------------+
double GetAveragingLots() {
    if (!PositionSizingInitialized) return 0.0;
    return CalculatedAveragingLots;
}

//+------------------------------------------------------------------+
//| FUNCTION: InitializeBasket()                                     |
//+------------------------------------------------------------------+
bool InitializeBasket(int mainTicket, double mainEntryPrice) {
    if (mainTicket <= 0) return false;
    
    Basket.mainOrderTicket = mainTicket;
    Basket.averagingOrderTicket = -1;
    Basket.mainOrderLots = GetInitialLots();
    Basket.averagingOrderLots = GetAveragingLots();
    Basket.mainEntryPrice = mainEntryPrice;
    Basket.averagingEntryPrice = 0.0;
    Basket.basketProfit = 0.0;
    Basket.averagingTriggered = false;
    Basket.partialCloseDone = false;
    Basket.totalClosedLots = 0.0;
    Basket.lastTriggerTime = TimeCurrent();
    Basket.isValid = true;
    
    LogInfo("Basket initialized for main order " + IntegerToString(mainTicket));
    
    return true;
}

//+------------------------------------------------------------------+
//| FUNCTION: AddAveragingOrderToBasket()                            |
//+------------------------------------------------------------------+
bool AddAveragingOrderToBasket(int averagingTicket, double averagingEntryPrice) {
    if (!Basket.isValid) return false;
    if (averagingTicket <= 0) return false;
    if (Basket.averagingTriggered) return false;
    
    Basket.averagingOrderTicket = averagingTicket;
    Basket.averagingEntryPrice = averagingEntryPrice;
    Basket.averagingTriggered = true;
    Basket.lastTriggerTime = TimeCurrent();
    
    LogInfo("Averaging order " + IntegerToString(averagingTicket) + " added to basket");
    
    return true;
}

//+------------------------------------------------------------------+
//| FUNCTION: CalculateBasketProfit()                                |
//+------------------------------------------------------------------+
double CalculateBasketProfit() {
    if (!Basket.isValid) return 0.0;
    
    double totalProfit = 0.0;
    
    // Calculate main order profit (profit only, excluding swap/commission)
    if (Basket.mainOrderTicket > 0) {
        if (OrderSelect(Basket.mainOrderTicket, SELECT_BY_TICKET)) {
            totalProfit += OrderProfit();
        }
    }
    
    // Calculate averaging order profit if exists
    if (Basket.averagingTriggered && Basket.averagingOrderTicket > 0) {
        if (OrderSelect(Basket.averagingOrderTicket, SELECT_BY_TICKET)) {
            totalProfit += OrderProfit();
        }
    }
    
    Basket.basketProfit = totalProfit;
    
    return totalProfit;
}

//+------------------------------------------------------------------+
//| FUNCTION: GetTotalBasketLots()                                   |
//+------------------------------------------------------------------+
double GetTotalBasketLots() {
    if (!Basket.isValid) return 0.0;
    
    double totalLots = Basket.mainOrderLots;
    if (Basket.averagingTriggered) {
        totalLots += Basket.averagingOrderLots;
    }
    
    return totalLots;
}

//+------------------------------------------------------------------+
//| FUNCTION: UpdatePartialClose()                                   |
//+------------------------------------------------------------------+
void UpdatePartialClose(double lotsClosed) {
    if (!Basket.isValid) return;
    
    Basket.totalClosedLots += lotsClosed;
    Basket.partialCloseDone = true;
    
    LogInfo("Basket updated - Partial close: " + DoubleToString(lotsClosed, 2) + " lots");
}

//+------------------------------------------------------------------+
//| FUNCTION: ResetBasket()                                          |
//+------------------------------------------------------------------+
void ResetBasket() {
    InitializeAveragingBasket();
    LogInfo("Basket reset complete");
}

//+------------------------------------------------------------------+
//| FUNCTION: IsBasketValid()                                        |
//+------------------------------------------------------------------+
bool IsBasketValid() {
    return Basket.isValid && Basket.mainOrderTicket > 0;
}

//+------------------------------------------------------------------+
//| FUNCTION: UpdateCurrentExposure()                                |
//+------------------------------------------------------------------+
double UpdateCurrentExposure() {
    double totalExposure = 0.0;
    
    for (int i = OrdersTotal() - 1; i >= 0; i--) {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            if (OrderSymbol() == Symbol() && 
                (OrderMagicNumber() == MAGIC_MAIN_ORDER || OrderMagicNumber() == MAGIC_AVERAGING)) {
                totalExposure += OrderLots();
            }
        }
    }
    
    CurrentTotalExposure = totalExposure;
    
    return totalExposure;
}

//+------------------------------------------------------------------+
//| ============== SECTION 7: ORDER MANAGEMENT ===================== |
//| Order Opening, Modification, and Closing                         |
//| Estimated Lines: ~600                                            |
//+------------------------------------------------------------------+

#define MAX_OPEN_ATTEMPTS 3
#define MAX_MODIFY_ATTEMPTS 3
#define MAX_CLOSE_ATTEMPTS 3
#define RETRY_DELAY_MS 1000
#define SLIPPAGE_POINTS_MULTIPLIER 10

int TotalOrdersOpened = 0;
int SuccessfulOpenings = 0;
int FailedOpenings = 0;
int TotalModifications = 0;
int SuccessfulModifications = 0;
int FailedModifications = 0;
int TotalClosures = 0;
int SuccessfulClosures = 0;
int FailedClosures = 0;

double MaxAllowedSlippagePips = 200.0;
double LastSpreadPips = 0.0;
double MaxSpreadSinceStart = 0.0;
bool OrderTrackingInitialized = false;

//+------------------------------------------------------------------+
//| FUNCTION: OM_Initialize()                                        |
//+------------------------------------------------------------------+
bool OM_Initialize() {
    LogInfo("Initializing Order Management Module");
    
    TotalOrdersOpened = 0;
    SuccessfulOpenings = 0;
    FailedOpenings = 0;
    TotalModifications = 0;
    SuccessfulModifications = 0;
    FailedModifications = 0;
    TotalClosures = 0;
    SuccessfulClosures = 0;
    FailedClosures = 0;
    
    MaxAllowedSlippagePips = Max_Slippage_Pips;
    LastSpreadPips = 0.0;
    MaxSpreadSinceStart = 0.0;
    
    OrderTrackingInitialized = true;
    
    LogInfo("Order Management Module Initialized | Max Slippage: " + DoubleToString(MaxAllowedSlippagePips, 1) + " pips");
    
    return true;
}

//+------------------------------------------------------------------+
//| FUNCTION: GetSlippageInPoints()                                  |
//+------------------------------------------------------------------+
int GetSlippageInPoints(double slippagePips) {
    if (Digits == 5 || Digits == 3) {
        return (int)(slippagePips * SLIPPAGE_POINTS_MULTIPLIER);
    } else {
        return (int)slippagePips;
    }
}

//+------------------------------------------------------------------+
//| FUNCTION: ValidateSLDistance()                                   |
//+------------------------------------------------------------------+
bool ValidateSLDistance(int orderType, double currentPrice, double slPrice) {
    if (slPrice <= 0) return true;
    
    double distancePrice = MathAbs(currentPrice - slPrice);
    double distancePips = PriceToPips(distancePrice);
    double minDistance = 10.0;
    
    if (distancePips < minDistance) return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| FUNCTION: ValidateTPDistance()                                   |
//+------------------------------------------------------------------+
bool ValidateTPDistance(int orderType, double currentPrice, double tpPrice) {
    if (tpPrice <= 0) return true;
    
    double distancePrice = MathAbs(currentPrice - tpPrice);
    double distancePips = PriceToPips(distancePrice);
    double minDistance = 10.0;
    
    if (distancePips < minDistance) return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| FUNCTION: OM_OpenMarketOrder()                                   |
//+------------------------------------------------------------------+
int OM_OpenMarketOrder(string symbol, int orderType, double lots,
                       double slPrice, double tpPrice, 
                       int magicNumber, string comment) {
    
    if (symbol == "") return -1;
    if (orderType != OP_BUY && orderType != OP_SELL) return -1;
    if (lots <= 0.0) return -1;
    
    if (!IsSpreadAcceptable(MaxAllowedSlippagePips)) {
        LogWarn("Spread too high, order rejected");
        FailedOpenings++;
        return -1;
    }
    
    double normalizedLots = NormalizeLots(lots);
    if (normalizedLots <= 0.0) return -1;
    
    double normalizedSL = (slPrice > 0) ? NormalizePrice(slPrice) : 0;
    double normalizedTP = (tpPrice > 0) ? NormalizePrice(tpPrice) : 0;
    
    RefreshRates();
    double entryPrice = (orderType == OP_BUY) ? Ask : Bid;
    
    if (normalizedSL > 0 && !ValidateSLDistance(orderType, entryPrice, normalizedSL)) {
        normalizedSL = 0;
    }
    
    if (normalizedTP > 0 && !ValidateTPDistance(orderType, entryPrice, normalizedTP)) {
        normalizedTP = 0;
    }
    
    int ticket = -1;
    int slippagePoints = GetSlippageInPoints(MaxAllowedSlippagePips);
    
    for (int attempt = 1; attempt <= MAX_OPEN_ATTEMPTS; attempt++) {
        RefreshRates();
        entryPrice = (orderType == OP_BUY) ? Ask : Bid;
        
        if (!IsSpreadAcceptable(MaxAllowedSlippagePips)) {
            if (attempt < MAX_OPEN_ATTEMPTS) {
                Sleep(RETRY_DELAY_MS);
                continue;
            } else {
                FailedOpenings++;
                return -1;
            }
        }
        
        ResetLastError();
        
        ticket = OrderSend(symbol, orderType, normalizedLots, entryPrice, 
                          slippagePoints, normalizedSL, normalizedTP, 
                          comment, magicNumber, 0, clrNONE);
        
        if (ticket > 0) {
            TotalOrdersOpened++;
            SuccessfulOpenings++;
            
            LogInfo("Market Order Opened Successfully");
            LogInfo("  Ticket: " + IntegerToString(ticket));
            LogInfo("  Type: " + (orderType == OP_BUY ? "BUY" : "SELL"));
            LogInfo("  Entry: " + DoubleToString(entryPrice, Digits));
            LogInfo("  Lots: " + DoubleToString(normalizedLots, 2));
            
            LogOrderOpening(ticket, symbol, orderType, normalizedLots, 
                           entryPrice, normalizedSL, normalizedTP, magicNumber);
            
            return ticket;
        }
        
        int error = GetLastError();
        LogDebug("OrderSend Error: " + IntegerToString(error) + " | " + GetErrorDescription(error));
        
        if (error == 130 || error == 131 || error == 134 || error == 145) {
            FailedOpenings++;
            TotalOrdersOpened++;
            return -1;
        }
        
        if (attempt < MAX_OPEN_ATTEMPTS) {
            Sleep(RETRY_DELAY_MS * attempt);
        }
    }
    
    LogError(ERR_ORDER_OPEN_FAILED, "OM_OpenMarketOrder", "Failed after " + IntegerToString(MAX_OPEN_ATTEMPTS) + " attempts");
    FailedOpenings++;
    TotalOrdersOpened++;
    
    return -1;
}

//+------------------------------------------------------------------+
//| FUNCTION: OM_ModifyOrder()                                       |
//+------------------------------------------------------------------+
bool OM_ModifyOrder(int ticket, double slPrice, double tpPrice) {
    if (!OrderSelect(ticket, SELECT_BY_TICKET)) return false;
    
    double currentSL = OrderStopLoss();
    double currentTP = OrderTakeProfit();
    double openPrice = OrderOpenPrice();
    int orderType = OrderType();
    
    double newSL = (slPrice > 0) ? NormalizePrice(slPrice) : currentSL;
    double newTP = (tpPrice > 0) ? NormalizePrice(tpPrice) : currentTP;
    
    bool slChanged = (newSL != currentSL);
    bool tpChanged = (newTP != currentTP);
    
    if (!slChanged && !tpChanged) return true;
    
    RefreshRates();
    double currentPrice = (orderType == OP_BUY) ? Bid : Ask;
    
    if (slChanged && newSL > 0 && !ValidateSLDistance(orderType, currentPrice, newSL)) {
        newSL = currentSL;
        slChanged = false;
    }
    
    if (tpChanged && newTP > 0 && !ValidateTPDistance(orderType, currentPrice, newTP)) {
        newTP = currentTP;
        tpChanged = false;
    }
    
    if (!slChanged && !tpChanged) return true;
    
    for (int attempt = 1; attempt <= MAX_MODIFY_ATTEMPTS; attempt++) {
        ResetLastError();
        
        bool success = OrderModify(ticket, openPrice, newSL, newTP, 0, clrNONE);
        
        if (success) {
            TotalModifications++;
            SuccessfulModifications++;
            LogOrderModification(ticket, currentSL, newSL, currentTP, newTP);
            return true;
        }
        
        int error = GetLastError();
        TotalModifications++;
        FailedModifications++;
        
        if (error == 130 || error == 145) return false;
        if (error == 1) return true;
        
        if (attempt < MAX_MODIFY_ATTEMPTS) {
            Sleep(RETRY_DELAY_MS * attempt);
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| FUNCTION: OM_CloseOrderFull()                                    |
//+------------------------------------------------------------------+
bool OM_CloseOrderFull(int ticket) {
    if (!OrderSelect(ticket, SELECT_BY_TICKET)) return false;
    
    string symbol = OrderSymbol();
    int orderType = OrderType();
    double lots = OrderLots();
    double openPrice = OrderOpenPrice();
    
    if (lots <= 0) return false;
    
    for (int attempt = 1; attempt <= MAX_CLOSE_ATTEMPTS; attempt++) {
        RefreshRates();
        double closePrice = (orderType == OP_BUY) ? Bid : Ask;
        int slippagePoints = GetSlippageInPoints(MaxAllowedSlippagePips);
        
        ResetLastError();
        
        bool success = OrderClose(ticket, lots, closePrice, slippagePoints, clrNONE);
        
        if (success) {
            TotalClosures++;
            SuccessfulClosures++;
            
            LogInfo("Order Closed Successfully (Full)");
            LogOrderClosure(ticket, symbol, orderType, lots, openPrice, closePrice);
            
            return true;
        }
        
        int error = GetLastError();
        TotalClosures++;
        FailedClosures++;
        
        if (error == 1) return true;
        if (error == 130 || error == 138) return false;
        
        if (attempt < MAX_CLOSE_ATTEMPTS) {
            Sleep(RETRY_DELAY_MS * attempt);
        }
    }
    
    LogError(ERR_ORDER_CLOSE_FAILED, "OM_CloseOrderFull", "Failed after " + IntegerToString(MAX_CLOSE_ATTEMPTS) + " attempts");
    
    return false;
}

//+------------------------------------------------------------------+
//| FUNCTION: OM_CloseOrderPartial()                                 |
//+------------------------------------------------------------------+
bool OM_CloseOrderPartial(int ticket, double lotsToClose) {
    if (!OrderSelect(ticket, SELECT_BY_TICKET)) return false;
    
    string symbol = OrderSymbol();
    int orderType = OrderType();
    double totalLots = OrderLots();
    double openPrice = OrderOpenPrice();
    
    double normalizedLots = NormalizeLots(lotsToClose);
    if (normalizedLots <= 0) return false;
    
    if (normalizedLots > totalLots) {
        normalizedLots = totalLots;
    }
    
    for (int attempt = 1; attempt <= MAX_CLOSE_ATTEMPTS; attempt++) {
        RefreshRates();
        double closePrice = (orderType == OP_BUY) ? Bid : Ask;
        int slippagePoints = GetSlippageInPoints(MaxAllowedSlippagePips);
        
        ResetLastError();
        
        bool success = OrderClose(ticket, normalizedLots, closePrice, slippagePoints, clrNONE);
        
        if (success) {
            TotalClosures++;
            SuccessfulClosures++;
            
            double remainingLots = totalLots - normalizedLots;
            
            LogInfo("Order Closed Successfully (Partial)");
            LogPartialClosure(ticket, symbol, orderType, normalizedLots, remainingLots, openPrice, closePrice);
            
            return true;
        }
        
        int error = GetLastError();
        TotalClosures++;
        FailedClosures++;
        
        if (error == 1) return true;
        if (error == 130 || error == 138 || error == 131) return false;
        
        if (attempt < MAX_CLOSE_ATTEMPTS) {
            Sleep(RETRY_DELAY_MS * attempt);
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| FUNCTION: OM_CountOpenOrders()                                   |
//+------------------------------------------------------------------+
int OM_CountOpenOrders(string symbol, int magicNumber) {
    int count = 0;
    
    for (int i = 0; i < OrdersTotal(); i++) {
        if (!OrderSelect(i, SELECT_BY_POS)) continue;
        
        if (OrderSymbol() == symbol && OrderMagicNumber() == magicNumber) {
            if (OrderType() == OP_BUY || OrderType() == OP_SELL) {
                count++;
            }
        }
    }
    
    return count;
}

//+------------------------------------------------------------------+
//| FUNCTION: OM_CloseAllOrders()                                    |
//+------------------------------------------------------------------+
bool OM_CloseAllOrders(string symbol, int magicNumber) {
    int ordersToClose = OM_CountOpenOrders(symbol, magicNumber);
    
    if (ordersToClose == 0) return true;
    
    bool allSuccessful = true;
    int closedCount = 0;
    
    for (int i = OrdersTotal() - 1; i >= 0; i--) {
        if (!OrderSelect(i, SELECT_BY_POS)) continue;
        
        if (OrderSymbol() != symbol || OrderMagicNumber() != magicNumber) continue;
        if (OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
        
        int ticket = OrderTicket();
        
        if (OM_CloseOrderFull(ticket)) {
            closedCount++;
        } else {
            allSuccessful = false;
        }
    }
    
    LogInfo("Closed " + IntegerToString(closedCount) + " of " + IntegerToString(ordersToClose) + " orders");
    
    return allSuccessful && (closedCount == ordersToClose);
}

//+------------------------------------------------------------------+
//| ================ SECTION 8: TRADE MANAGEMENT =================== |
//| Main Trade Logic, Trailing Stop, Averaging, Opposite Signal      |
//| Estimated Lines: ~500                                            |
//+------------------------------------------------------------------+

// Trade management state
int ActiveMainTicket = -1;
int ActiveAveragingTicket = -1;
int ActiveOrderType = -1;
double ActiveEntryPrice = 0.0;
double HighestPriceSinceEntry = 0.0;
double LowestPriceSinceEntry = 0.0;
bool TrailingStopActivated = false;
double CurrentTrailingStopLevel = 0.0;

//+------------------------------------------------------------------+
//| FUNCTION: HasOpenPosition()                                      |
//+------------------------------------------------------------------+
bool HasOpenPosition() {
    return (OM_CountOpenOrders(Symbol(), MAGIC_MAIN_ORDER) > 0) ||
           (OM_CountOpenOrders(Symbol(), MAGIC_AVERAGING) > 0);
}

//+------------------------------------------------------------------+
//| FUNCTION: GetCurrentDrawdownPips()                               |
//+------------------------------------------------------------------+
double GetCurrentDrawdownPips() {
    if (ActiveMainTicket <= 0) return 0.0;
    
    if (!OrderSelect(ActiveMainTicket, SELECT_BY_TICKET)) return 0.0;
    
    double entryPrice = OrderOpenPrice();
    int orderType = OrderType();
    
    RefreshRates();
    double currentPrice = (orderType == OP_BUY) ? Bid : Ask;
    
    double drawdown = 0.0;
    
    if (orderType == OP_BUY) {
        drawdown = PriceToPips(currentPrice - entryPrice);
    } else {
        drawdown = PriceToPips(entryPrice - currentPrice);
    }
    
    return drawdown;
}

//+------------------------------------------------------------------+
//| FUNCTION: CheckAveragingCondition()                              |
//+------------------------------------------------------------------+
bool CheckAveragingCondition() {
    if (!Basket.isValid) return false;
    if (Basket.averagingTriggered) return false;
    
    double drawdown = GetCurrentDrawdownPips();
    
    if (drawdown <= Averaging_Drawdown_Pips) {
        LogInfo("Averaging condition met | Drawdown: " + DoubleToString(drawdown, 1) + " pips");
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| FUNCTION: OpenAveragingOrder()                                   |
//+------------------------------------------------------------------+
bool OpenAveragingOrder() {
    if (ActiveMainTicket <= 0) return false;
    if (!OrderSelect(ActiveMainTicket, SELECT_BY_TICKET)) return false;
    
    int orderType = OrderType();
    double lots = GetAveragingLots();
    
    RefreshRates();
    double entryPrice = (orderType == OP_BUY) ? Ask : Bid;
    
    string comment = "Averaging";
    
    int ticket = OM_OpenMarketOrder(Symbol(), orderType, lots, 0, 0, MAGIC_AVERAGING, comment);
    
    if (ticket > 0) {
        ActiveAveragingTicket = ticket;
        AddAveragingOrderToBasket(ticket, entryPrice);
        
        double drawdown = GetCurrentDrawdownPips();
        LogAveragingEntry(ticket, ActiveMainTicket, lots, entryPrice, drawdown);
        
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| FUNCTION: UpdateHighLowTracking()                                |
//+------------------------------------------------------------------+
void UpdateHighLowTracking() {
    if (ActiveMainTicket <= 0) return;
    if (!OrderSelect(ActiveMainTicket, SELECT_BY_TICKET)) return;
    
    int orderType = OrderType();
    
    RefreshRates();
    
    if (orderType == OP_BUY) {
        if (Bid > HighestPriceSinceEntry) {
            HighestPriceSinceEntry = Bid;
        }
    } else {
        if (Ask < LowestPriceSinceEntry || LowestPriceSinceEntry == 0) {
            LowestPriceSinceEntry = Ask;
        }
    }
}

//+------------------------------------------------------------------+
//| FUNCTION: CheckTrailingStopActivation()                          |
//+------------------------------------------------------------------+
bool CheckTrailingStopActivation() {
    if (TrailingStopActivated) return true;
    if (ActiveMainTicket <= 0) return false;
    if (!OrderSelect(ActiveMainTicket, SELECT_BY_TICKET)) return false;
    
    int orderType = OrderType();
    double entryPrice = OrderOpenPrice();
    
    RefreshRates();
    double currentPrice = (orderType == OP_BUY) ? Bid : Ask;
    
    double profitPips = 0.0;
    
    if (orderType == OP_BUY) {
        profitPips = PriceToPips(currentPrice - entryPrice);
    } else {
        profitPips = PriceToPips(entryPrice - currentPrice);
    }
    
    if (profitPips >= Trailing_Activation_Pips) {
        TrailingStopActivated = true;
        LogInfo("Trailing stop activated at " + DoubleToString(profitPips, 1) + " pips profit");
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| FUNCTION: ManageTrailingStop()                                   |
//+------------------------------------------------------------------+
void ManageTrailingStop() {
    if (!TrailingStopActivated) {
        CheckTrailingStopActivation();
        return;
    }
    
    if (ActiveMainTicket <= 0) return;
    if (!OrderSelect(ActiveMainTicket, SELECT_BY_TICKET)) return;
    
    int orderType = OrderType();
    double currentSL = OrderStopLoss();
    
    RefreshRates();
    
    double newSL = 0.0;
    
    if (orderType == OP_BUY) {
        // For BUY: Trail 1000 pips behind the highest price
        newSL = HighestPriceSinceEntry - PipsToPrice(Trailing_Distance_Pips);
        
        // Only update if new SL is higher and step size is met
        if (currentSL > 0) {
            double stepPips = PriceToPips(newSL - currentSL);
            if (stepPips < Trailing_Stop_Step_Pips) return;
        }
        
        if (newSL > currentSL) {
            if (OM_ModifyOrder(ActiveMainTicket, newSL, 0)) {
                CurrentTrailingStopLevel = newSL;
                LogInfo("Trailing stop updated to " + DoubleToString(newSL, Digits));
            }
        }
    } else {
        // For SELL: Trail 1000 pips above the lowest price
        newSL = LowestPriceSinceEntry + PipsToPrice(Trailing_Distance_Pips);
        
        // Only update if new SL is lower and step size is met
        if (currentSL > 0) {
            double stepPips = PriceToPips(currentSL - newSL);
            if (stepPips < Trailing_Stop_Step_Pips) return;
        }
        
        if (newSL < currentSL || currentSL == 0) {
            if (OM_ModifyOrder(ActiveMainTicket, newSL, 0)) {
                CurrentTrailingStopLevel = newSL;
                LogInfo("Trailing stop updated to " + DoubleToString(newSL, Digits));
            }
        }
    }
}

//+------------------------------------------------------------------+
//| FUNCTION: CheckOppositeSignal()                                  |
//+------------------------------------------------------------------+
bool CheckOppositeSignal() {
    if (ActiveMainTicket <= 0) return false;
    if (!OrderSelect(ActiveMainTicket, SELECT_BY_TICKET)) return false;
    
    int currentOrderType = OrderType();
    
    // Check if an opposite signal has completed the 2-candle confirmation
    // This happens when a full opposite signal is ready for entry
    
    // First, update entry signals to check for new pattern
    if (!CheckForNewBar()) return false;
    
    // Check for opposite signal detection
    ENUM_ORDER_TYPE_EA newSignal = CheckForNewSignal();
    
    if (newSignal == ORDER_TYPE_NONE) return false;
    
    // Check if this is opposite to current position
    bool isOpposite = false;
    
    if (currentOrderType == OP_BUY && newSignal == ORDER_TYPE_SELL) {
        isOpposite = true;
    } else if (currentOrderType == OP_SELL && newSignal == ORDER_TYPE_BUY) {
        isOpposite = true;
    }
    
    if (isOpposite) {
        LogInfo("OPPOSITE SIGNAL DETECTED - Current: " + (currentOrderType == OP_BUY ? "BUY" : "SELL") + 
                " | New: " + (newSignal == ORDER_TYPE_BUY ? "BUY" : "SELL"));
    }
    
    return isOpposite;
}

//+------------------------------------------------------------------+
//| FUNCTION: CheckBasketProfitClose()                               |
//+------------------------------------------------------------------+
bool CheckBasketProfitClose() {
    if (!Basket.isValid) return false;
    if (!Basket.averagingTriggered) return false;
    
    double basketProfit = CalculateBasketProfit();
    
    if (basketProfit >= Profit_Close_Threshold) {
        LogInfo("Basket profit threshold reached: $" + DoubleToString(basketProfit, 2));
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| FUNCTION: ExecutePartialClose()                                  |
//+------------------------------------------------------------------+
bool ExecutePartialClose() {
    if (Basket.partialCloseDone) return false;
    
    double basketProfit = CalculateBasketProfit();
    
    if (basketProfit < Profit_Close_Threshold) return false;
    
    LogInfo("Executing 50% partial close | Basket Profit: $" + DoubleToString(basketProfit, 2));
    
    bool success = true;
    double totalClosed = 0.0;
    
    // Close 50% of main order (0.01 -> 0.005)
    if (ActiveMainTicket > 0 && OrderSelect(ActiveMainTicket, SELECT_BY_TICKET)) {
        double mainLots = OrderLots();
        double closeMain = NormalizeLots(mainLots * 0.5);
        
        if (closeMain > 0 && OM_CloseOrderPartial(ActiveMainTicket, closeMain)) {
            totalClosed += closeMain;
            LogPartialClose(ActiveMainTicket, mainLots - closeMain, closeMain, basketProfit / 2);
        } else {
            success = false;
        }
    }
    
    // Close 50% of averaging order (0.03 -> 0.015)
    if (ActiveAveragingTicket > 0 && OrderSelect(ActiveAveragingTicket, SELECT_BY_TICKET)) {
        double avgLots = OrderLots();
        double closeAvg = NormalizeLots(avgLots * 0.5);
        
        if (closeAvg > 0 && OM_CloseOrderPartial(ActiveAveragingTicket, closeAvg)) {
            totalClosed += closeAvg;
            LogPartialClose(ActiveAveragingTicket, avgLots - closeAvg, closeAvg, basketProfit / 2);
        } else {
            success = false;
        }
    }
    
    if (totalClosed > 0) {
        UpdatePartialClose(totalClosed);
    }
    
    return success;
}

//+------------------------------------------------------------------+
//| FUNCTION: CloseAllPositions()                                    |
//+------------------------------------------------------------------+
bool CloseAllPositions(string reason) {
    LogInfo("Closing all positions | Reason: " + reason);
    
    bool success = true;
    
    // Close main order
    if (ActiveMainTicket > 0) {
        if (OM_CloseOrderFull(ActiveMainTicket)) {
            LogInfo("Main order closed: " + IntegerToString(ActiveMainTicket));
        } else {
            success = false;
        }
    }
    
    // Close averaging order
    if (ActiveAveragingTicket > 0) {
        if (OM_CloseOrderFull(ActiveAveragingTicket)) {
            LogInfo("Averaging order closed: " + IntegerToString(ActiveAveragingTicket));
        } else {
            success = false;
        }
    }
    
    // Reset state
    ResetTradeState();
    
    return success;
}

//+------------------------------------------------------------------+
//| FUNCTION: ResetTradeState()                                      |
//+------------------------------------------------------------------+
void ResetTradeState() {
    ActiveMainTicket = -1;
    ActiveAveragingTicket = -1;
    ActiveOrderType = -1;
    ActiveEntryPrice = 0.0;
    HighestPriceSinceEntry = 0.0;
    LowestPriceSinceEntry = 0.0;
    TrailingStopActivated = false;
    CurrentTrailingStopLevel = 0.0;
    
    ResetBasket();
    ResetEntrySignalState();
}

//+------------------------------------------------------------------+
//| FUNCTION: UpdateStatistics()                                     |
//+------------------------------------------------------------------+
void UpdateStatistics(double profit) {
    Stats.totalTrades++;
    
    if (profit > 0) {
        Stats.winTrades++;
        Stats.totalProfit += profit;
        if (profit > Stats.largestWin) {
            Stats.largestWin = profit;
        }
        Stats.consecutiveWins++;
        Stats.consecutiveLosses = 0;
    } else {
        Stats.lossTrades++;
        Stats.totalLoss += profit;
        if (profit < Stats.largestLoss) {
            Stats.largestLoss = profit;
        }
        Stats.consecutiveWins = 0;
        Stats.consecutiveLosses++;
    }
    
    if (Stats.totalTrades > 0) {
        Stats.winRate = (Stats.winTrades * 100.0) / Stats.totalTrades;
    }
    
    if (Stats.totalLoss != 0) {
        Stats.profitFactor = MathAbs(Stats.totalProfit / Stats.totalLoss);
    }
    
    Stats.lastTradeClosedTime = TimeCurrent();
    
    LogInfo("Statistics Updated | Total: " + IntegerToString(Stats.totalTrades) + 
            " | Wins: " + IntegerToString(Stats.winTrades) + 
            " | Win Rate: " + DoubleToString(Stats.winRate, 1) + "%");
}

//+------------------------------------------------------------------+
//| ================ SECTION 9: MAIN EA FUNCTIONS ================== |
//| OnInit, OnDeinit, OnTick                                         |
//| Estimated Lines: ~300                                            |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    Print("========================================");
    Print(EA_NAME, " v", EA_VERSION, " - INITIALIZING");
    Print("========================================");
    Print("Symbol: ", Symbol());
    Print("Timeframe: ", GetTimeframeString(Period()));
    Print("Account: ", AccountNumber());
    Print("Broker: ", AccountCompany());
    Print("========================================");
    
    // Validate input parameters
    if (!ValidateInputParameters()) {
        Print("ERROR: Input validation failed");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    // Initialize all systems
    ResetGlobalState();
    
    if (!InitializeStrategy()) {
        Print("ERROR: Strategy initialization failed");
        return INIT_FAILED;
    }
    
    if (!InitializeEntrySignals()) {
        Print("ERROR: Entry signals initialization failed");
        return INIT_FAILED;
    }
    
    if (!InitializePositionSizing()) {
        Print("ERROR: Position sizing initialization failed");
        return INIT_FAILED;
    }
    
    if (!OM_Initialize()) {
        Print("ERROR: Order management initialization failed");
        return INIT_FAILED;
    }
    
    IsInitialized = true;
    
    Print("========================================");
    Print(EA_NAME, " INITIALIZED SUCCESSFULLY");
    Print("========================================");
    Print("EMA Period: ", EMA_Period);
    Print("ADX Period: ", ADX_Period, " | Threshold: ", ADX_Threshold);
    Print("Candle Size: ", Candle_Size_Min_Pips, "-", Candle_Size_Max_Pips, " pips");
    Print("Tolerance: ", Candle_Size_Tolerance_Pct, "%");
    Print("TP: ", Fixed_TP_Pips, " pips | Trailing: ", Trailing_Distance_Pips, " pips");
    Print("Lots: ", DoubleToString(Initial_Lot_Size, 2), " | Averaging: ", DoubleToString(Averaging_Lot_Size, 2));
    Print("========================================");
    
    UpdateChartComment("Ready - Waiting for signals");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    Print("========================================");
    Print(EA_NAME, " - SHUTTING DOWN");
    Print("========================================");
    Print("Deinit Reason: ", reason);
    Print("Total Trades: ", Stats.totalTrades);
    Print("Win Rate: ", DoubleToString(Stats.winRate, 1), "%");
    Print("Net Profit: $", DoubleToString(Stats.totalProfit + Stats.totalLoss, 2));
    Print("========================================");
    
    Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    // Check initialization
    if (!IsInitialized) return;
    
    // Increment tick counter
    TotalTickProcessed++;
    LastTickTime = TimeCurrent();
    
    // Check if trading is allowed
    if (!IsTradingAllowed) {
        UpdateChartComment("Trading Disabled");
        return;
    }
    
    // Check for open positions
    bool hasPosition = HasOpenPosition();
    
    if (hasPosition) {
        // === POSITION MANAGEMENT ===
        
        UpdateHighLowTracking();
        
        // Check for opposite signal (exit condition)
        if (CheckOppositeSignal()) {
            // Calculate profit before closing
            double profit = CalculateBasketProfit();
            
            CloseAllPositions("Opposite Signal Confirmed");
            UpdateStatistics(profit);
            
            LastExitReason = EXIT_REASON_OPPOSITE_SIGNAL;
            UpdateChartComment("Position closed - Opposite signal");
            return;
        }
        
        // Check averaging condition (-800 pips drawdown)
        if (CheckAveragingCondition()) {
            OpenAveragingOrder();
        }
        
        // Check basket profit close (combined profit > $1.00)
        if (Basket.averagingTriggered && !Basket.partialCloseDone) {
            if (CheckBasketProfitClose()) {
                ExecutePartialClose();
            }
        }
        
        // Check for second basket close (remaining positions when profit > $1 again)
        if (Basket.partialCloseDone) {
            double basketProfit = CalculateBasketProfit();
            if (basketProfit >= Profit_Close_Threshold) {
                double totalProfit = basketProfit;
                CloseAllPositions("Basket Profit Target");
                UpdateStatistics(totalProfit);
                
                LastExitReason = EXIT_REASON_TP;
                UpdateChartComment("All positions closed - Profit target");
                return;
            }
        }
        
        // Manage trailing stop
        ManageTrailingStop();
        
        // Update chart
        string status = "Position Active";
        if (Basket.averagingTriggered) {
            status += " | Averaging Active";
        }
        if (TrailingStopActivated) {
            status += " | Trailing Active";
        }
        UpdateChartComment(status);
        
    } else {
        // === SIGNAL DETECTION ===
        
        // Check for new bar
        bool isNewBar = CheckForNewBar();
        
        if (isNewBar) {
            // Update entry signal state machine
            UpdateEntrySignals();
            
            // Check if ready for entry
            if (IsReadyForEntry()) {
                ENUM_ORDER_TYPE_EA signalType = GetPendingSignalType();
                
                if (signalType != ORDER_TYPE_NONE) {
                    int orderType = (signalType == ORDER_TYPE_BUY) ? OP_BUY : OP_SELL;
                    double lots = GetInitialLots();
                    
                    RefreshRates();
                    double entryPrice = (orderType == OP_BUY) ? Ask : Bid;
                    
                    // Calculate TP (fixed 2000 pips)
                    double tpPrice = 0.0;
                    if (orderType == OP_BUY) {
                        tpPrice = entryPrice + PipsToPrice(Fixed_TP_Pips);
                    } else {
                        tpPrice = entryPrice - PipsToPrice(Fixed_TP_Pips);
                    }
                    
                    string comment = EA_NAME + " Main";
                    
                    int ticket = OM_OpenMarketOrder(Symbol(), orderType, lots, 0, tpPrice, MAGIC_MAIN_ORDER, comment);
                    
                    if (ticket > 0) {
                        // Store trade info
                        ActiveMainTicket = ticket;
                        ActiveOrderType = orderType;
                        ActiveEntryPrice = entryPrice;
                        HighestPriceSinceEntry = (orderType == OP_BUY) ? Bid : 0.0;
                        LowestPriceSinceEntry = (orderType == OP_SELL) ? Ask : 0.0;
                        TrailingStopActivated = false;
                        
                        // Initialize basket
                        InitializeBasket(ticket, entryPrice);
                        
                        // Mark entry executed
                        MarkEntryExecuted();
                        
                        CurrentSignalState = (orderType == OP_BUY) ? SIGNAL_STATE_BUY_ACTIVE : SIGNAL_STATE_SELL_ACTIVE;
                        
                        UpdateChartComment("Trade opened: " + (orderType == OP_BUY ? "BUY" : "SELL"));
                    } else {
                        LogError(ERR_ORDER_OPEN_FAILED, "OnTick", "Failed to open entry order");
                        ResetEntrySignalState();
                    }
                }
            }
        }
        
        // Update chart status
        string phaseStr = GetPhaseString(CurrentPhase);
        UpdateChartComment("Scanning... | " + phaseStr);
    }
}

//+------------------------------------------------------------------+
//| END OF GOLDTRENDEA_COMPLETE.MQ4                                  |
//+------------------------------------------------------------------+
