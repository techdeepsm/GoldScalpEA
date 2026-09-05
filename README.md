# GoldScalpEA

A scenario-based, probability-driven, dynamically expandable XAUUSD research and execution
framework for MetaTrader 5, built as a modular MQL5 project (not a single-file EA).

## What this is

`MQL5/Experts/GoldScalpEA/GoldScalpEA.mq5` is the Expert Advisor. It is built entirely on top of
22 `.mqh` modules under `MQL5/Include/GoldScalpEA/`, organized as:

```
Core/        Types.mqh, Utils.mqh              - shared enums/structs, math & hashing helpers
Engines/     MarketContext, SessionEngine, StructureEngine, LiquidityEngine,
             VolatilityEngine, DisplacementEngine, FVGEngine
Features/    FeatureSnapshot.mqh                - wires every engine into one per-bar snapshot
Scenario/    ScenarioRegistry, ScenarioLibrary (S001-S082), ScenarioStateMachine,
             DynamicScenarioGenerator
Analytics/   OutcomeEngine, ProbabilityEngine, ConfluenceEngine, ValidationEngine, RankingEngine
Risk/        RiskManager.mqh
Execution/   ExecutionEngine.mqh
IO/          CSVLogger.mqh
UI/          Dashboard.mqh
```

## Installation

Copy the `MQL5/` folder's contents into your terminal's `MQL5/` data folder (merge, don't
overwrite), so you end up with:

```
<terminal data folder>/MQL5/Experts/GoldScalpEA/GoldScalpEA.mq5
<terminal data folder>/MQL5/Include/GoldScalpEA/...
```

Open `GoldScalpEA.mq5` in MetaEditor and compile (F7). This was written and self-reviewed
carefully but **has not been compiled in MetaEditor** (no MT5/MetaEditor toolchain is available
in the environment this was built in) - compile and fix any remaining syntax issues before
relying on it. Everything was checked signature-by-signature against MQL5 semantics, but a real
compiler is the final word.

## How it works

**Research mode** (`InpMode = MODE_RESEARCH`, the default): on `OnInit()`, the EA loads history
for the confirmation timeframe (default M5) plus H1 (bias) and M15 (context) over the configured
Train/Validation/OOS date range, builds one `FeatureSnapshot` per closed bar (no look-ahead - see
"No look-ahead bias" below), and runs every enabled scenario's state machine over that single pass.
Every completed sequence becomes a `ScenarioOccurrence`; the `OutcomeEngine` then scans forward
bars (execution timeframe, default M1) to find out what actually happened, resolving all seven
R-multiples (0.5R-4R) per occurrence. From there:

1. Occurrences are labelled TRAIN / VALIDATION / OOS / EXCLUDED by `entryTime`.
2. `ProbabilityEngine` computes real statistics per scenario per dataset - win rate, P(R) with
   Wilson 95% confidence intervals, expectancy, profit factor, drawdown, streaks, MFE/MAE. Nothing
   is a hardcoded placeholder; every number comes from counting `ScenarioOccurrence` records.
3. `ValidationEngine` moves scenarios through CANDIDATE -> INSUFFICIENT_DATA / REJECTED /
   PROMISING / VALIDATING -> (final OOS gate) VALIDATED / REJECTED. OOS is only ever read by the
   final gate - dynamic generation and parameter variation only ever look at TRAIN/VALIDATION.
4. If `InpEnableDynamicDiscovery` is on, `DynamicScenarioGenerator` extends PROMISING/VALIDATING
   scenarios one reusable building block at a time (never brute-forcing every combination), up to
   `InpMaxScenarioDepth` rounds and `InpMaxGeneratedScenarios` total, re-running the full detection
   pass each round. Every generated scenario gets a deterministic `Dxxxxxxxx` ID derived from its
   family root + sorted component set, so the same combination always maps to the same ID.
5. `RankingEngine` scores every scenario on sample size, expectancy, P(2R), profit factor,
   drawdown, and walk-forward stability, minus an explicit complexity penalty - every component of
   the score is stored on the result, not hidden behind one opaque number.
6. Six CSVs are exported to `MQL5/Files/`: `..._scenario_occurrences.csv`, `..._scenario_summary.csv`,
   `..._scenario_probability.csv`, `..._scenario_confluence.csv`, `..._scenario_validation.csv`
   (plus `trade_log.csv` support in `CSVLogger.mqh`, populated once trades exist in live mode).
7. A discovery report prints to the Experts log: totals by status and the top-ranked scenarios.

**Live mode** (`InpMode = MODE_LIVE`) runs the exact same pipeline once at startup (and again every
`InpLiveResearchRefreshDays`) to build a validated scenario library with real statistics, then
trades tick-by-tick: on every new confirmation-bar close it detects any newly-completed
occurrences, keeps only ones whose scenario is VALIDATED (or LIVE/DEGRADED if explicitly allowed)
and clears every configured live threshold (sample size, P(target R), expectancy, profit factor,
drawdown, spread), ranks the eligible candidates, and executes only the best one - subject to the
`RiskManager`'s daily-loss/trade-count/consecutive-loss/cooldown/spread gates. Closed trades feed
back into a rolling live-performance check (`CheckAllScenarioDecay`) that can move a scenario from
VALIDATED to DEGRADED to RETIRED if live performance deteriorates - never on a handful of losses.

## The 82 preloaded scenarios

`ScenarioLibrary.mqh` defines S001-S082 as **data**, not code: each is a short sequence of
reusable grammar steps (sweep, close-back-above/below, BOS, CHOCH, displacement, FVG,
retracement, breakout, context filters for HTF bias/session/volatility, etc.) evaluated by one
generic state machine in `ScenarioStateMachine.mqh`. Per spec, S021-S082 are registered but
disabled by default (`InpEnableS021toS082 = false`); S001-S020 run out of the box.

Where the prose spec did not name a specific liquidity level (several Tier 5/8/9 "generic"
scenarios), a representative level/condition was chosen and is noted in a comment at that
scenario's definition. S060/S063/S064's "range extreme" trigger reuses one combined
Asian-range/prior-day-range extreme-zone flag rather than wholly separate detectors, to avoid
near-duplicate signals for the same idea.

## No look-ahead bias

- Swing highs/lows in `StructureEngine` only confirm once `InpSwingRight` bars have closed after
  the candidate bar - the swing's existence literally cannot be known any earlier.
- PDH/PDL/PWH/PWL are read from the prior **fully closed** D1/W1 bar via `iBarShift` anchored to
  the bar's own timestamp (not "shift from now"), so a fast historical replay resolves "yesterday"
  correctly instead of reading the terminal's real-time D1 bar.
- H1 bias and M15 context are advanced via a monotonic cursor that only consumes a bar once its
  **close** time (open + period) is at or before the confirmation bar being built - not merely
  once its open time has passed.
- The `OutcomeEngine` is the only file that ever reads bars after a scenario's detection time, and
  only to score the hypothetical outcome - never to help detect the scenario itself.
- Same-candle SL/TP ambiguity defaults to "assume SL first" (`InpAmbiguityRule = 0`), never the
  favorable assumption, per spec #13.

## Known simplifications (read before relying on this)

- **Sessions use broker/server time**, not true IANA timezones - MQL5 has no timezone database.
  Set the Asian/London/NY hour inputs to match your broker's UTC offset and DST convention.
- **Research mode runs synchronously in `OnInit()`**, not through the Strategy Tester's tick
  loop, so it can process years of history in one pass without waiting on tick-by-tick
  simulation. This means `OnInit()` can take a while to return on a large date range - reduce
  `InpTrainStart`/the overall range, or be patient on first load. It also means results are
  produced independent of - and can be cross-checked against - a normal Strategy Tester run.
- **Monte Carlo-style stress testing** (`InpEnableMonteCarloLikeStress`) currently perturbs
  spread only (doubling `InpSimulatedSpreadPoints` and re-scoring VALIDATED scenarios' OOS
  occurrences), logged via `Print()`. The framework is structured so slippage/entry-delay/
  parameter-perturbation variants can be added the same way; they are not implemented yet.
- **Parameter variation** (`InpEnableParameterVariations`) currently varies retracement
  percentage on the 82 base scenarios only, bounded by `InpMaxParameterVariants`.
- **CTX_HTF_BULLISH/BEARISH is only ever added "aligned"** with a candidate scenario's own trade
  direction during dynamic generation (a long scenario can gain "HTF bullish", never "HTF
  bearish"). Testing contrarian HTF filters is a reasonable future extension.
- Entry fill is modelled as the confirmation bar's close plus/minus half the configured/live
  spread; a limit/retracement entry model uses the captured FVG midpoint or level price instead.
  This is a deliberate, documented simplification of live order-fill mechanics, not a hidden one.
- Position tracking correlates open/close via the MT5 **deal ticket that opened the position**
  (`CTrade::ResultDeal()`, which equals `DEAL_POSITION_ID` on every later deal against that
  position) - this is the correct MT5 identifier chain, distinct from the order ticket.

## Compiling and testing

This was authored without access to MetaEditor/MT5 (no such toolchain exists in this build
environment), so **you must compile it yourself and treat the first compile as the real
correctness check**. If MetaEditor reports errors, they are most likely to be in the largest,
most mechanically-repetitive files (`ScenarioLibrary.mqh`'s 82 definitions, the main `.mq5`'s
input/config wiring) rather than in the smaller, more carefully hand-checked engine files.

Suggested test order once it compiles:
1. Strategy Tester, visual mode, `MODE_RESEARCH`, a short date range first (a few months) to
   confirm the Experts log prints a discovery report and `MQL5/Files/` gets the five CSVs.
2. Widen the date range once that works, and inspect `..._scenario_summary.csv` for scenarios
   whose sample size clears `InpMinSampleSize` - their P(R)/expectancy numbers are the actual
   backtested statistics for this build's assumptions (spread, ambiguity rule, etc.), not
   predictions of live performance.
3. Only then test `MODE_LIVE` in the Strategy Tester (which will run the same research pipeline
   once at the start of the test), before ever considering a demo/live account.
