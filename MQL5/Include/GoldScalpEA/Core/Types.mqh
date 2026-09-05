//+------------------------------------------------------------------+
//| Types.mqh                                                         |
//| Shared enumerations and POD structs used across every module.     |
//| No look-ahead logic lives here - this file only defines shapes.   |
//+------------------------------------------------------------------+
#ifndef __GSEA_TYPES_MQH__
#define __GSEA_TYPES_MQH__

//---------------------------------------------------------------- modes
enum ENUM_EA_MODE
  {
   MODE_RESEARCH = 0,   // Detect / simulate / score only, no live orders
   MODE_LIVE     = 1    // Trade only VALIDATED scenarios
  };

enum ENUM_DIRECTION
  {
   DIR_LONG  = 0,
   DIR_SHORT = 1
  };

enum ENUM_SESSION
  {
   SESSION_NONE            = 0,
   SESSION_ASIAN           = 1,
   SESSION_LONDON          = 2,
   SESSION_NEWYORK         = 3,
   SESSION_LONDON_NY_OVERLAP = 4
  };

enum ENUM_BIAS
  {
   BIAS_BULLISH = 0,
   BIAS_BEARISH = 1,
   BIAS_NEUTRAL = 2
  };

enum ENUM_VOL_REGIME
  {
   VOL_LOW    = 0,
   VOL_MEDIUM = 1,
   VOL_HIGH   = 2
  };

enum ENUM_TREND_REGIME
  {
   REGIME_TRENDING = 0,
   REGIME_RANGING  = 1
  };

enum ENUM_VWAP_POS
  {
   VWAP_ABOVE = 0,
   VWAP_BELOW = 1,
   VWAP_AT    = 2
  };

//---------------------------------------------------------------- levels
enum ENUM_LEVEL_TYPE
  {
   LEVEL_NONE = 0,
   LEVEL_ASIAN_HIGH,
   LEVEL_ASIAN_LOW,
   LEVEL_PDH,
   LEVEL_PDL,
   LEVEL_PWH,
   LEVEL_PWL,
   LEVEL_EQUAL_HIGH,
   LEVEL_EQUAL_LOW,
   LEVEL_LONDON_HIGH,
   LEVEL_LONDON_LOW,
   LEVEL_NY_HIGH,
   LEVEL_NY_LOW,
   LEVEL_OR_HIGH,     // opening range high (session-specific)
   LEVEL_OR_LOW       // opening range low  (session-specific)
  };

//---------------------------------------------------------------- grammar step vocabulary (reusable building blocks)
enum ENUM_STEP_TYPE
  {
   STEP_NONE = 0,
   STEP_SWEEP_HIGH,             // sweeps a high-type level (uses .level)
   STEP_SWEEP_LOW,              // sweeps a low-type level  (uses .level)
   STEP_CLOSE_BACK_ABOVE,       // close reclaims level swept by a SWEEP_LOW step
   STEP_CLOSE_BACK_BELOW,       // close reclaims level swept by a SWEEP_HIGH step
   STEP_REJECTION_BULL,
   STEP_REJECTION_BEAR,
   STEP_BOS_BULL,
   STEP_BOS_BEAR,
   STEP_CHOCH_BULL,
   STEP_CHOCH_BEAR,
   STEP_DISPLACEMENT_BULL,
   STEP_DISPLACEMENT_BEAR,
   STEP_FVG_BULL,
   STEP_FVG_BEAR,
   STEP_FVG_RETRACEMENT,        // price returns into last FVG to configured %
   STEP_FVG_FULL_FILL,          // price fully closes the last FVG
   STEP_RETRACEMENT,            // generic retracement into swing/impulse
   STEP_STRUCTURE_RETEST,
   STEP_BREAKOUT_UP,            // uses .level
   STEP_BREAKOUT_DOWN,          // uses .level
   STEP_FALSE_BREAKOUT_UP,      // break above .level then close back below
   STEP_FALSE_BREAKOUT_DOWN,    // break below .level then close back above
   STEP_COMPRESSION,
   STEP_EXPANSION,
   STEP_EXHAUSTION,
   STEP_LARGE_WICK_REJECTION_BULL,
   STEP_LARGE_WICK_REJECTION_BEAR,
   STEP_HIGHER_LOW,
   STEP_LOWER_HIGH,
   STEP_VWAP_DEV_UPPER,
   STEP_VWAP_DEV_LOWER,
   STEP_RANGE_EXTREME_HIGH,     // price at extreme of a reference range (Asian/PDay) -> mean reversion
   STEP_RANGE_EXTREME_LOW,
   // context filters (do not consume a bar, checked as of the bar the previous step landed on)
   CTX_HTF_BULLISH,
   CTX_HTF_BEARISH,
   CTX_SESSION_ASIAN,
   CTX_SESSION_LONDON,
   CTX_SESSION_NEWYORK,
   CTX_SESSION_OVERLAP,
   CTX_ATR_EXPANSION,
   CTX_ATR_COMPRESSION,
   CTX_VOL_HIGH,
   CTX_VOL_LOW
  };

struct ScenarioStep
  {
   ENUM_STEP_TYPE level_kind;   // step type from ENUM_STEP_TYPE
   ENUM_LEVEL_TYPE level;       // which liquidity level, for level-based steps
   int             max_bars;    // max bars allowed to elapse before this step must fire (0 = use scenario default)
  };

//---------------------------------------------------------------- entry / SL / TP models
enum ENUM_ENTRY_MODEL
  {
   ENTRY_MARKET = 0,
   ENTRY_LIMIT_AT_LEVEL,
   ENTRY_FVG_RETRACEMENT,
   ENTRY_STRUCTURE_RETEST,
   ENTRY_BREAKOUT,
   ENTRY_REJECTION,
   ENTRY_DELAYED
  };

enum ENUM_SL_MODEL
  {
   SL_FIXED_POINTS = 0,
   SL_ATR_MULTIPLE,
   SL_STRUCTURE,
   SL_LIQUIDITY,
   SL_SWEEP_EXTREME,
   SL_CANDLE_EXTREME
  };

enum ENUM_TP_MODEL
  {
   TP_FIXED_POINTS = 0,
   TP_FIXED_R,
   TP_LIQUIDITY_TARGET,
   TP_PREV_HIGH_LOW,
   TP_ATR_MULTIPLE
  };

//---------------------------------------------------------------- scenario lifecycle
enum ENUM_SCENARIO_STATUS
  {
   STATUS_CANDIDATE = 0,
   STATUS_INSUFFICIENT_DATA,
   STATUS_PROMISING,
   STATUS_VALIDATING,
   STATUS_VALIDATED,
   STATUS_LIVE,
   STATUS_DEGRADED,
   STATUS_REJECTED,
   STATUS_RETIRED
  };

enum ENUM_DATASET
  {
   DATASET_TRAIN = 0,
   DATASET_VALIDATION,
   DATASET_OOS,
   DATASET_EXCLUDED    // outside every configured train/validation/OOS window - never enters statistics
  };

#define GSEA_MAX_STEPS       16
#define GSEA_MAX_COMPONENTS  16
#define GSEA_R_LEVELS        7   // 0.5,1,1.5,2,2.5,3,4

//---------------------------------------------------------------- feature snapshot (one per confirmation-TF closed bar)
struct FeatureSnapshot
  {
   datetime       time;             // open time of the confirmation-TF bar this snapshot describes
   double         open,high,low,close;
   double         atr;
   ENUM_VOL_REGIME volRegime;
   ENUM_TREND_REGIME trendRegime;
   ENUM_BIAS      htfBias;
   ENUM_SESSION   session;
   int            hour;
   int            dayOfWeek;
   double         vwap;
   ENUM_VWAP_POS  vwapPos;
   double         vwapDistPts;
   double         vwapUpperBand, vwapLowerBand;
   bool           vwapDevUpperTouch, vwapDevLowerTouch;
   bool           rangeExtremeHighAsian, rangeExtremeLowAsian;
   bool           rangeExtremeHighPDay, rangeExtremeLowPDay;
   bool           atrExtremeExpansion;
   double         spreadPts;
   // liquidity levels known as of this bar (previous-period levels only, never repainted intrabar)
   double         asianHigh, asianLow;
   double         pdh, pdl, pwh, pwl;
   double         londonHigh, londonLow;
   double         nyHigh, nyLow;
   double         equalHigh, equalLow;
   bool           hasEqualHigh, hasEqualLow;
   double         orHigh, orLow;      // opening range of current session, if applicable
   bool           hasOR;
   // structure / price action booleans evaluated strictly on this closed bar
   bool           bosBull, bosBear;
   bool           chochBull, chochBear;
   bool           displacementBull, displacementBear;
   bool           compression, expansion;
   bool           exhaustion;
   bool           largeWickRejectionBull, largeWickRejectionBear;
   bool           higherLow, lowerHigh;
   bool           structureRetestBull, structureRetestBear;
   bool           fvgBull, fvgBear;         // a new FVG of this polarity formed ending at this bar
   double         lastFvgBullTop, lastFvgBullBottom, lastFvgBullMid;
   double         lastFvgBearTop, lastFvgBearBottom, lastFvgBearMid;
   bool           fvgBullRetracement, fvgBearRetracement; // price tapped configured % of most recent unmitigated FVG
   bool           fvgBullFullFill, fvgBearFullFill;
   bool           sweptHighLevel[15];   // indexed by ENUM_LEVEL_TYPE, true if this bar swept & closed back inside for a high-type level
   bool           sweptLowLevel[15];
   bool           breakoutUpLevel[15];
   bool           breakoutDownLevel[15];
   bool           falseBreakoutUpLevel[15];
   bool           falseBreakoutDownLevel[15];
  };

//---------------------------------------------------------------- scenario definition
struct ScenarioDef
  {
   string            id;                 // "S001".."S082" or "D0001.."
   string            name;
   ENUM_DIRECTION    direction;
   ScenarioStep      sequence[GSEA_MAX_STEPS];
   int               stepCount;
   string            parentId;           // "" for root/base scenarios
   string            components[GSEA_MAX_COMPONENTS]; // human labels, used for confluence bookkeeping
   int               componentCount;
   int               depth;              // number of building blocks beyond the base = complexity measure
   int               defaultExpiryBars;  // max bars from trigger step to completed sequence
   ENUM_ENTRY_MODEL  entryModel;
   ENUM_SL_MODEL     slModel;
   ENUM_TP_MODEL     tpModel;
   double            retracementPct;     // for retracement-based entries (0..1)
   double            slBufferPoints;
   double            fixedSLPoints;
   double            fixedTPPoints;
   double            atrMultSL;
   double            atrMultTP;
   bool              enabled;
   bool              isDynamic;
   ENUM_SCENARIO_STATUS status;
  };

//---------------------------------------------------------------- an in-flight (partially matched) scenario instance
struct ScenarioInstance
  {
   string   scenarioId;
   int      cursor;                 // index of next required step
   datetime lastStepTime;
   datetime startTime;
   double   levelPrice;             // captured level value (sweep/breakout reference)
   double   sweepExtreme;           // furthest excursion beyond the level during the sweep
   double   fvgTop, fvgBottom, fvgMid;
   bool     fvgIsBull;              // polarity of the FVG this instance is tracking (independent of trade direction)
   bool     alive;
  };

//---------------------------------------------------------------- a fully matched, timestamped occurrence (research)
struct ScenarioOccurrence
  {
   long     occurrenceId;
   string   scenarioId;
   datetime detectTime;      // time sequence fully completed (signal time, no look-ahead)
   datetime entryTime;
   ENUM_DIRECTION direction;
   double   entryPrice;
   double   slPrice;
   double   tpLevels[GSEA_R_LEVELS];   // price levels for 0.5..4R
   double   rDistance;                 // price distance representing 1R
   ENUM_SESSION session;
   ENUM_BIAS htfBias;
   ENUM_VOL_REGIME volRegime;
   double   atrAtEntry;
   double   spreadAtEntry;
   int      hour;
   int      dayOfWeek;
   ENUM_DATASET dataset;
   // outcome (filled by OutcomeEngine)
   bool     outcomeResolved;
   bool     hitLevel[GSEA_R_LEVELS];   // whether each R level was reached before SL
   int      barsToStop;
   int      barsToFirstTarget;
   double   mfeR, maeR;
   double   exitR;               // realized R multiple at final resolution (first target hit or SL)
   bool     stoppedOut;
  };

//---------------------------------------------------------------- executed live trade record
struct ExecutedTrade
  {
   ulong    ticket;
   string   scenarioId;
   datetime openTime, closeTime;
   ENUM_DIRECTION direction;
   double   openPrice, closePrice, slPrice, tpPrice, lots;
   double   profit;
   double   rMultiple;
  };

//---------------------------------------------------------------- aggregated statistics for one scenario / one dataset
struct ScenarioStats
  {
   string   scenarioId;
   ENUM_DATASET dataset;
   int      occurrences;
   int      wins;                 // reached first configured target level before SL
   int      losses;
   double   winRate;
   double   probR[GSEA_R_LEVELS];      // P(reach R level before SL)
   double   probR_ciLo[GSEA_R_LEVELS]; // Wilson 95% CI lower
   double   probR_ciHi[GSEA_R_LEVELS]; // Wilson 95% CI upper
   double   avgWinR, avgLossR;
   double   avgR, medianR;
   double   expectancyR;       // "run to whichever R level is reached first, stop or the far end" - NOT
   double   profitFactor;      // a single fixed-TP outcome. See expectancyAtLevel/profitFactorAtLevel
                                // for the number that actually corresponds to a live order with its
                                // take-profit fixed at one specific R level (e.g. InpLiveTargetLevelIndex).
   double   expectancyAtLevel[GSEA_R_LEVELS];    // P(level)*level - (1-P(level))*1, per R level
   double   profitFactorAtLevel[GSEA_R_LEVELS];  // gross win / gross loss if TP were fixed at that level
   double   maxDrawdownR;
   int      maxWinStreak, maxLossStreak;
   double   avgMFE_R, avgMAE_R;
   double   avgBarsToTarget;
   ENUM_SCENARIO_STATUS status;
   bool     sufficientSample;
  };

#endif // __GSEA_TYPES_MQH__
