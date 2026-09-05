//+------------------------------------------------------------------+
//|                                                   GoldScalpEA.mq5 |
//| Scenario-based, probability-driven, dynamically expandable Gold    |
//| trading & research framework for XAUUSD.                          |
//|                                                                     |
//| MODE_RESEARCH: detects every historical occurrence of every        |
//| enabled scenario (S001-S082 plus anything dynamically generated),  |
//| scores real outcomes, computes real probabilities/expectancy/      |
//| confidence intervals, validates on out-of-sample data, ranks       |
//| everything transparently, and exports CSVs. No trade is required.  |
//|                                                                     |
//| MODE_LIVE: runs the same pipeline once at startup to build a       |
//| VALIDATED scenario library, then trades ONLY validated scenarios   |
//| that clear every configured live threshold, under a conservative   |
//| risk manager. Nothing here is a placeholder probability - every    |
//| number is counted from the data at load time.                      |
//+------------------------------------------------------------------+
#property copyright "GoldScalpEA"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
#include <GoldScalpEA/Core/Types.mqh>
#include <GoldScalpEA/Core/Utils.mqh>
#include <GoldScalpEA/Engines/MarketContext.mqh>
#include <GoldScalpEA/Features/FeatureSnapshot.mqh>
#include <GoldScalpEA/Scenario/ScenarioRegistry.mqh>
#include <GoldScalpEA/Scenario/ScenarioLibrary.mqh>
#include <GoldScalpEA/Scenario/ScenarioStateMachine.mqh>
#include <GoldScalpEA/Scenario/DynamicScenarioGenerator.mqh>
#include <GoldScalpEA/Analytics/OutcomeEngine.mqh>
#include <GoldScalpEA/Analytics/ProbabilityEngine.mqh>
#include <GoldScalpEA/Analytics/ConfluenceEngine.mqh>
#include <GoldScalpEA/Analytics/ValidationEngine.mqh>
#include <GoldScalpEA/Analytics/RankingEngine.mqh>
#include <GoldScalpEA/Risk/RiskManager.mqh>
#include <GoldScalpEA/Execution/ExecutionEngine.mqh>
#include <GoldScalpEA/IO/CSVLogger.mqh>
#include <GoldScalpEA/UI/Dashboard.mqh>

//====================================================================== INPUTS
input group "===== General ====="
input ENUM_EA_MODE    InpMode              = MODE_RESEARCH;   // Research (no trades) or Live (validated only)
input ulong           InpMagicNumber       = 20260001;
input string          InpTradeSymbol       = "";              // "" = use chart symbol

input group "===== Timeframes ====="
input ENUM_TIMEFRAMES InpTF_HTF            = PERIOD_H1;       // Higher-timeframe bias
input ENUM_TIMEFRAMES InpTF_Context        = PERIOD_M15;      // Context / regime timeframe
input ENUM_TIMEFRAMES InpTF_Confirm        = PERIOD_M5;       // Confirmation / detection timeframe
input ENUM_TIMEFRAMES InpTF_Exec           = PERIOD_M1;       // Execution / outcome-resolution timeframe

input group "===== Sessions (broker/server time, HH:MM - adjust for your broker's UTC offset) ====="
input int InpAsianStartHour=0,  InpAsianStartMin=0,  InpAsianEndHour=8,  InpAsianEndMin=0;
input int InpLondonStartHour=8, InpLondonStartMin=0, InpLondonEndHour=16,InpLondonEndMin=0;
input int InpNYStartHour=13,    InpNYStartMin=0,     InpNYEndHour=21,    InpNYEndMin=0;
input int InpOpeningRangeMinutes=30;

input group "===== Feature Engine ====="
input int    InpSwingLeft=3, InpSwingRight=3;
input double InpRetestTolerancePts=100;
input double InpEqualLevelTolerancePts=150;
input int    InpAtrPeriod=14;
input double InpAtrLowPct=0.33, InpAtrHighPct=0.66;
input double InpAtrExpansionMult=1.5, InpAtrCompressionMult=0.6;
input double InpVwapDevMult=2.0;
input int    InpDispLookback=20;
input double InpDispMult=1.5, InpDispBodyRatio=0.6, InpDispCompMult=0.6, InpDispExpMult=1.8, InpDispWickRatio=0.55;
input double InpFvgMinSizePts=100, InpFvgRetracePct=0.5;
input double InpExtremeZonePct=0.12;

input group "===== Scenario Library ====="
input bool InpEnableS021toS082          = false; // spec default: research starts with S001-S020 active
input int  InpMinSampleSize             = 100;
input bool InpEnableDynamicDiscovery    = false;
input int  InpMaxScenarioDepth          = 3;
input int  InpMaxGeneratedScenarios     = 200;
input bool InpEnableParameterVariations = false;
input int  InpMaxParameterVariants      = 3;
input bool InpEnableWalkForward         = true;
input bool InpEnableMonteCarloLikeStress= false;

input group "===== Probability / Validation ====="
input double InpWilsonZ                     = 1.96;  // 95% confidence
input double InpMinExpectancy               = 0.0;
input double InpMinProfitFactor             = 1.0;
input double InpValidationRetentionRatio    = 0.30;
input double InpMinWalkForwardPassRate      = 0.50;
input int    InpWalkForwardTrainMonths      = 12;
input int    InpWalkForwardTestMonths       = 3;

// Defaults below are tuned to an account whose XAUUSD history begins 2025.01.02 (confirmed from
// a live Journal log - "history begins from 2025.01.02"). If your broker/tester has deeper
// history, push InpTrainStart back and rebalance the windows accordingly - more TRAIN history is
// better as long as InpValidStart/InpOOSStart still land before "now" in your test range.
input group "===== Dataset Ranges (spec #30 - never let OOS feed back into scenario construction) ====="
input string InpTrainStart = "2025.01.02";
input string InpTrainEnd   = "2025.09.01";
input string InpValidStart = "2025.09.01";
input string InpValidEnd   = "2026.01.01";
input string InpOOSStart   = "2026.01.01";
input string InpOOSEnd     = "2026.12.31";

input group "===== Execution Cost Simulation (Research) ====="
input double InpSimulatedSpreadPoints = 250;
input int    InpMaxOutcomeScanBars    = 5000;
input int    InpAmbiguityRule         = 0;    // 0 = assume SL first (conservative), 1 = assume TP first

input group "===== Live Entry Thresholds ====="
input int    InpLiveTargetLevelIndex   = 3;    // index into 0.5/1/1.5/2/2.5/3/4 R -> 3 = 2R
input double InpLiveMinProbAtTarget    = 0.45;
input double InpLiveMaxDrawdownR       = 15.0;
input double InpLiveMaxSpreadPoints    = 400;
input bool   InpLiveAllowDegraded      = false;
input int    InpLiveResearchRefreshDays= 30;   // full pipeline rerun cadence - expensive, keep infrequent (0 = never)
input int    InpMinLiveSampleForDecay  = 20;   // spec #37 - never judge decay on a handful of trades

input group "===== Risk Management ====="
input bool   InpUseRiskPercent        = true;
input double InpRiskPercent           = 0.5;
input double InpFixedLot              = 0.01;
input double InpMaxDailyLossAmount    = 0.0;   // 0 = disabled
input int    InpMaxTradesPerDay       = 10;
input int    InpMaxSimultaneousTrades = 1;
input int    InpMaxTradesPerScenario  = 3;
input int    InpMaxConsecutiveLosses  = 4;
input int    InpCooldownMinutesAfterLoss = 30;
input double InpMaxAccountDrawdownPct = 20.0;

input group "===== Ranking Weights (spec #28 - every component visible, no black box) ====="
input int    InpRankSampleCap = 1000;
input double InpRankExpectancyCap = 1.0;
input double InpRankPFRangeAboveOne = 2.0;
input double InpRankDDCap = 20.0;
input double InpRankWeightSample = 1.0, InpRankWeightExpectancy = 2.0, InpRankWeightProb = 1.0;
input double InpRankWeightPF = 1.0, InpRankWeightDrawdown = 1.0, InpRankWeightStability = 1.5;
input double InpRankComplexityPenaltyPerComponent = 0.05;

input group "===== CSV Export ====="
input bool   InpExportCSV  = true;
input string InpFilePrefix = "GSEA_";

input group "===== Dashboard ====="
input bool InpShowDashboard = true;

//====================================================================== GLOBAL STATE
CMarketContext           g_market;           // convenience copy of the builder's own context (Init'd separately for pre-pipeline use)
CFeatureSnapshotBuilder   g_builder;
CScenarioRegistry         g_registry;
CScenarioStateMachine     g_stateMachine;
CRiskManager              g_risk;
CDashboard                g_dash;
CTrade                    g_trade;

ScenarioOccurrence g_occurrences[];
MqlRates           g_confirmBars[];

string        g_cacheIds[];
ScenarioStats g_cacheStatsOOS[];
double        g_cacheWFRate[];

RankingResult g_rankResults[];

string   g_openTicketScenario[]; ulong g_openTicketId[]; double g_openTicketRDist[];
ExecutedTrade g_trades[];
datetime g_lastConfirmBarTime=0, g_lastHTFBarTime=0, g_lastCtxBarTime=0;
datetime g_lastFullResearchRun=0;
datetime g_lastProcessedDealTime=0;

//====================================================================== SMALL HELPERS
string EffectiveSymbol() { return (InpTradeSymbol=="")? _Symbol : InpTradeSymbol; }

FeatureBuilderConfig BuildFeatureConfig()
  {
   FeatureBuilderConfig c;
   c.swingLeft=InpSwingLeft; c.swingRight=InpSwingRight; c.retestTolerancePts=InpRetestTolerancePts;
   c.eqLevelTolerancePts=InpEqualLevelTolerancePts;
   c.atrPeriod=InpAtrPeriod; c.atrLowPct=InpAtrLowPct; c.atrHighPct=InpAtrHighPct;
   c.atrExpansionMult=InpAtrExpansionMult; c.atrCompressionMult=InpAtrCompressionMult;
   c.vwapDevMult=InpVwapDevMult;
   c.dispLookback=InpDispLookback; c.dispMult=InpDispMult; c.dispBodyRatio=InpDispBodyRatio;
   c.dispCompMult=InpDispCompMult; c.dispExpMult=InpDispExpMult; c.dispWickRatio=InpDispWickRatio;
   c.fvgMinSizePts=InpFvgMinSizePts; c.fvgRetracePct=InpFvgRetracePct;
   c.extremeZonePct=InpExtremeZonePct;
   c.orMinutes=InpOpeningRangeMinutes;
   c.asianWin.startHour=InpAsianStartHour; c.asianWin.startMin=InpAsianStartMin;
   c.asianWin.endHour=InpAsianEndHour; c.asianWin.endMin=InpAsianEndMin;
   c.londonWin.startHour=InpLondonStartHour; c.londonWin.startMin=InpLondonStartMin;
   c.londonWin.endHour=InpLondonEndHour; c.londonWin.endMin=InpLondonEndMin;
   c.nyWin.startHour=InpNYStartHour; c.nyWin.startMin=InpNYStartMin;
   c.nyWin.endHour=InpNYEndHour; c.nyWin.endMin=InpNYEndMin;
   return c;
  }

RiskConfig BuildRiskConfig()
  {
   RiskConfig c;
   c.useRiskPercent=InpUseRiskPercent; c.riskPercent=InpRiskPercent; c.fixedLot=InpFixedLot;
   c.maxDailyLossAmount=InpMaxDailyLossAmount; c.maxTradesPerDay=InpMaxTradesPerDay;
   c.maxSimultaneousTrades=InpMaxSimultaneousTrades; c.maxTradesPerScenario=InpMaxTradesPerScenario;
   c.maxConsecutiveLosses=InpMaxConsecutiveLosses; c.cooldownMinutesAfterLoss=InpCooldownMinutesAfterLoss;
   c.maxSpreadPoints=InpLiveMaxSpreadPoints; c.maxAccountDrawdownPct=InpMaxAccountDrawdownPct;
   return c;
  }

LifecycleThresholds BuildLifecycleThresholds()
  {
   LifecycleThresholds t;
   t.minSampleSize=InpMinSampleSize; t.minExpectancy=InpMinExpectancy; t.minProfitFactor=InpMinProfitFactor;
   t.validationRetentionRatio=InpValidationRetentionRatio; t.minWalkForwardPassRate=InpMinWalkForwardPassRate;
   t.degradeExpectancyRatio=0.3; t.retireExpectancy=-0.2;
   return t;
  }

RankingWeights BuildRankingWeights()
  {
   RankingWeights w;
   w.sampleCap=InpRankSampleCap; w.expectancyCap=InpRankExpectancyCap; w.pfRangeAboveOne=InpRankPFRangeAboveOne;
   w.ddCap=InpRankDDCap; w.wSample=InpRankWeightSample; w.wExpectancy=InpRankWeightExpectancy;
   w.wProb=InpRankWeightProb; w.wPF=InpRankWeightPF; w.wDrawdown=InpRankWeightDrawdown;
   w.wStability=InpRankWeightStability; w.complexityPenaltyPerComponent=InpRankComplexityPenaltyPerComponent;
   return w;
  }

LiveEligibilityConfig BuildLiveEligibilityConfig()
  {
   LiveEligibilityConfig c;
   c.minSampleSize=InpMinSampleSize; c.targetLevelIndex=InpLiveTargetLevelIndex;
   c.minProbAtTarget=InpLiveMinProbAtTarget; c.minExpectancy=InpMinExpectancy;
   c.minProfitFactor=InpMinProfitFactor; c.maxDrawdownR=InpLiveMaxDrawdownR;
   c.maxSpreadPoints=InpLiveMaxSpreadPoints; c.allowDegraded=InpLiveAllowDegraded;
   return c;
  }

DatasetRanges BuildDatasetRanges()
  {
   DatasetRanges r;
   r.trainStart=StringToTime(InpTrainStart); r.trainEnd=StringToTime(InpTrainEnd);
   r.validStart=StringToTime(InpValidStart); r.validEnd=StringToTime(InpValidEnd);
   r.oosStart=StringToTime(InpOOSStart);     r.oosEnd=StringToTime(InpOOSEnd);
   return r;
  }

void AppendOccurrence(const ScenarioOccurrence &o)
  {
   int n=ArraySize(g_occurrences);
   ArrayResize(g_occurrences,n+1,4096);
   g_occurrences[n]=o;
  }

int FindCacheSlot(const string id)
  {
   for(int i=0;i<ArraySize(g_cacheIds);i++) if(g_cacheIds[i]==id) return i;
   return -1;
  }

bool GetCachedStats(const string id,ScenarioStats &out,double &wfRate)
  {
   int i=FindCacheSlot(id);
   if(i<0) return false;
   out=g_cacheStatsOOS[i]; wfRate=g_cacheWFRate[i];
   return true;
  }

//====================================================================== CORE PIPELINE
// Rebuilds every engine from scratch and scans the whole configured history ONCE, running every
// currently-registered scenario's state machine in the same pass (spec #55 - the cost scales with
// bars x scenarios-alive-per-bar, never with a separate rescan per scenario).
void RunDetectionPass()
  {
   ArrayResize(g_occurrences,0);
   g_builder.Deinit();
   FeatureBuilderConfig cfg=BuildFeatureConfig();
   string sym=EffectiveSymbol();
   if(!g_builder.Init(sym,InpTF_HTF,InpTF_Context,InpTF_Confirm,cfg))
     { Print("GoldScalpEA: feature builder init failed"); return; }

   datetime overallStart=StringToTime(InpTrainStart);
   datetime overallEnd=(datetime)MathMin((double)TimeCurrent(),(double)StringToTime(InpOOSEnd));
   if(!g_builder.LoadHistoricalContext(overallStart,overallEnd))
      Print("GoldScalpEA: warning - HTF/context history load returned no data");

   int n=CopyRates(sym,InpTF_Confirm,overallStart,overallEnd,g_confirmBars);
   if(n<=0){ Print("GoldScalpEA: no confirmation-TF history available for ",sym); return; }

   // Diagnostic: if the terminal's actual history is shallower than the requested range, say so
   // loudly - this is the single most common reason every scenario ends up INSUFFICIENT_DATA.
   datetime gotFirst=g_confirmBars[0].time, gotLast=g_confirmBars[n-1].time;
   if(gotFirst>overallStart+PeriodSeconds(InpTF_Confirm)*10)
      PrintFormat("GoldScalpEA: WARNING - requested history from %s but %s %s data actually begins %s. "
                  "TRAIN/VALIDATION windows before that date will get ZERO occurrences and every scenario "
                  "will stay INSUFFICIENT_DATA. Set InpTrainStart/InpValidStart/InpOOSStart to fit the "
                  "history this account actually has.",
                  TimeToString(overallStart,TIME_DATE),sym,EnumToString(InpTF_Confirm),TimeToString(gotFirst,TIME_DATE));

   g_stateMachine.Init();
   int periodSec=PeriodSeconds(InpTF_Confirm);
   double point=g_builder.Market().Point();

   for(int i=0;i<n;i++)
     {
      FeatureSnapshot snap;
      g_builder.BuildSnapshot(g_confirmBars[i],InpSimulatedSpreadPoints,snap);
      ScenarioOccurrence newOcc[]; int newCount;
      g_stateMachine.OnBar(snap,g_registry,periodSec,point,InpSimulatedSpreadPoints,newOcc,newCount);
      for(int k=0;k<newCount;k++) AppendOccurrence(newOcc[k]);
     }
  }

// The only place forward bars are read - after every occurrence's detection timestamp, using the
// execution timeframe for the finest available resolution of SL/TP-first ambiguity (spec #13).
void ResolveAllOutcomes()
  {
   string sym=EffectiveSymbol();
   datetime overallStart=StringToTime(InpTrainStart);
   datetime overallEnd=(datetime)MathMin((double)TimeCurrent(),(double)StringToTime(InpOOSEnd));
   MqlRates execBars[];
   int n=CopyRates(sym,InpTF_Exec,overallStart,overallEnd,execBars);
   if(n<=0){ ArrayCopy(execBars,g_confirmBars); n=ArraySize(execBars); }

   int confirmPeriodSec=PeriodSeconds(InpTF_Confirm);
   int total=ArraySize(g_occurrences);
   for(int i=0;i<total;i++)
     {
      datetime fillTime=g_occurrences[i].entryTime+confirmPeriodSec; // scan starts once the confirm bar has fully closed
      int startIdx=FindBarIndexAtOrAfter(execBars,n,fillTime);
      ComputeOutcome(g_occurrences[i],execBars,n,startIdx,InpMaxOutcomeScanBars,(ENUM_AMBIGUITY_RULE)InpAmbiguityRule);
     }
  }

void EvaluateLifecycleForAll()
  {
   DatasetRanges ranges=BuildDatasetRanges();
   ClassifyDatasets(g_occurrences,ArraySize(g_occurrences),ranges);
   LifecycleThresholds th=BuildLifecycleThresholds();
   int total=ArraySize(g_occurrences);
   int cnt=g_registry.Count();
   for(int i=0;i<cnt;i++)
     {
      ScenarioDef def; if(!g_registry.GetAt(i,def)) continue;
      ScenarioStats trainSt,validSt;
      ComputeScenarioStats(g_occurrences,total,def.id,DATASET_TRAIN,InpMinSampleSize,InpWilsonZ,trainSt);
      ComputeScenarioStats(g_occurrences,total,def.id,DATASET_VALIDATION,InpMinSampleSize,InpWilsonZ,validSt);
      ENUM_SCENARIO_STATUS newStatus=EvaluateLifecycleTrainValidation(trainSt,validSt,th);
      g_registry.SetStatus(def.id,newStatus);
     }
  }

int CollectParentsForExpansion(string &outIds[])
  {
   ArrayResize(outIds,0);
   int cnt=g_registry.Count();
   for(int i=0;i<cnt;i++)
     {
      ScenarioDef def; if(!g_registry.GetAt(i,def)) continue;
      if(def.status==STATUS_PROMISING || def.status==STATUS_VALIDATING)
        {
         int n=ArraySize(outIds); ArrayResize(outIds,n+1); outIds[n]=def.id;
        }
     }
   return ArraySize(outIds);
  }

// Final one-way OOS gate + walk-forward, and the cache every live/ranking lookup reads from.
void FinalizeOOSAndWalkForward()
  {
   LifecycleThresholds th=BuildLifecycleThresholds();
   datetime overallStart=StringToTime(InpTrainStart);
   datetime overallEnd=(datetime)MathMin((double)TimeCurrent(),(double)StringToTime(InpOOSEnd));
   int total=ArraySize(g_occurrences);
   int cnt=g_registry.Count();
   ArrayResize(g_cacheIds,0); ArrayResize(g_cacheStatsOOS,0); ArrayResize(g_cacheWFRate,0);
   for(int i=0;i<cnt;i++)
     {
      ScenarioDef def; if(!g_registry.GetAt(i,def)) continue;
      ScenarioStats oosSt;
      ComputeScenarioStats(g_occurrences,total,def.id,DATASET_OOS,InpMinSampleSize,InpWilsonZ,oosSt);
      double passRate=1.0;
      if(InpEnableWalkForward)
        {
         WalkForwardWindowResult wf[];
         RunWalkForward(g_occurrences,total,def.id,overallStart,overallEnd,
                        InpWalkForwardTrainMonths,InpWalkForwardTestMonths,InpMinSampleSize,InpWilsonZ,wf);
         passRate=WalkForwardPassRate(wf,ArraySize(wf));
        }
      if(def.status==STATUS_VALIDATING)
        {
         ENUM_SCENARIO_STATUS newStatus=EvaluateLifecycleOOS(def.status,oosSt,passRate,th);
         g_registry.SetStatus(def.id,newStatus);
        }
      int n=ArraySize(g_cacheIds);
      ArrayResize(g_cacheIds,n+1); ArrayResize(g_cacheStatsOOS,n+1); ArrayResize(g_cacheWFRate,n+1);
      g_cacheIds[n]=def.id; g_cacheStatsOOS[n]=oosSt; g_cacheWFRate[n]=passRate;
     }
  }

void BuildRankingTableGlobal()
  {
   RankingWeights w=BuildRankingWeights();
   int cnt=g_registry.Count();
   ArrayResize(g_rankResults,cnt);
   for(int i=0;i<cnt;i++)
     {
      ScenarioDef def; g_registry.GetAt(i,def);
      ScenarioStats st; double wf;
      if(!GetCachedStats(def.id,st,wf)){ ZeroMemory(st); wf=0.0; }
      RankingResult r;
      RankScenario(def,st,wf,w,r);
      g_rankResults[i]=r;
     }
   SortRankingResultsDesc(g_rankResults,cnt);
  }

// Spec #26 - bounded, opt-in parameter variation: a handful of retracement/SL-buffer variants of
// each promising scenario, tested exactly like any other candidate (not assumed better).
void GenerateParameterVariationsForPromising()
  {
   double retraceOptions[3]={0.33,0.5,0.66};
   int cnt=g_registry.Count();
   string baseIds[]; int baseCount=0;
   for(int i=0;i<cnt;i++)
     {
      ScenarioDef def; g_registry.GetAt(i,def);
      if(def.isDynamic) continue; // vary the 82 base definitions only, to keep this bounded
      if(def.status==STATUS_PROMISING || def.status==STATUS_VALIDATING || def.status==STATUS_VALIDATED)
        { ArrayResize(baseIds,baseCount+1); baseIds[baseCount]=def.id; baseCount++; }
     }
   int added=0;
   for(int b=0;b<baseCount;b++)
     {
      ScenarioDef def; if(!g_registry.Get(baseIds[b],def)) continue;
      for(int v=0;v<MathMin(InpMaxParameterVariants,3);v++)
        {
         ScenarioDef variant=def;
         variant.id=def.id+"_PV"+(string)(v+1);
         variant.parentId=def.id;
         variant.isDynamic=true;
         variant.status=STATUS_CANDIDATE;
         variant.retracementPct=retraceOptions[v];
         if(g_registry.FindIndex(variant.id)>=0) continue;
         if(g_registry.Add(variant)) added++;
        }
     }
   if(added>0)
     {
      RunDetectionPass();
      ResolveAllOutcomes();
      EvaluateLifecycleForAll();
     }
  }

// Spec #56 - spread-sensitivity stress test on VALIDATED scenarios only: recompute entry/SL/TP
// under a doubled spread assumption and compare resulting OOS expectancy against the baseline.
void RunStressTestForValidated()
  {
   int cnt=g_registry.Count();
   double point=g_builder.Market().Point();
   string sym=EffectiveSymbol();
   MqlRates execBars[];
   datetime overallStart=StringToTime(InpTrainStart);
   datetime overallEnd=(datetime)MathMin((double)TimeCurrent(),(double)StringToTime(InpOOSEnd));
   int nExec=CopyRates(sym,InpTF_Exec,overallStart,overallEnd,execBars);
   if(nExec<=0){ ArrayCopy(execBars,g_confirmBars); nExec=ArraySize(execBars); }
   int confirmPeriodSec=PeriodSeconds(InpTF_Confirm);

   for(int i=0;i<cnt;i++)
     {
      ScenarioDef def; g_registry.GetAt(i,def);
      if(def.status!=STATUS_VALIDATED) continue;
      ScenarioOccurrence stressed[];
      int m=0;
      for(int k=0;k<ArraySize(g_occurrences);k++)
        {
         if(g_occurrences[k].scenarioId!=def.id || g_occurrences[k].dataset!=DATASET_OOS) continue;
         ArrayResize(stressed,m+1);
         stressed[m]=g_occurrences[k];
         int sign=DirSign(stressed[m].direction);
         double baselineHalf=InpSimulatedSpreadPoints*point/2.0;
         double stressedHalf=(InpSimulatedSpreadPoints*2.0)*point/2.0;
         double rawEntry=stressed[m].entryPrice-sign*baselineHalf;
         double newEntry=rawEntry+sign*stressedHalf;
         stressed[m].entryPrice=newEntry;
         stressed[m].slPrice=newEntry-sign*stressed[m].rDistance;
         for(int r=0;r<GSEA_R_LEVELS;r++) stressed[m].tpLevels[r]=newEntry+sign*stressed[m].rDistance*GSEA_R_MULTIPLES[r];
         int startIdx=FindBarIndexAtOrAfter(execBars,nExec,stressed[m].entryTime+confirmPeriodSec);
         ComputeOutcome(stressed[m],execBars,nExec,startIdx,InpMaxOutcomeScanBars,(ENUM_AMBIGUITY_RULE)InpAmbiguityRule);
         m++;
        }
      ScenarioStats stressedStats; ComputeScenarioStats(stressed,m,def.id,DATASET_OOS,1,InpWilsonZ,stressedStats);
      ScenarioStats baseline; double wf; GetCachedStats(def.id,baseline,wf);
      PrintFormat("GoldScalpEA STRESS %s: baseline OOS expectancy=%.3fR (n=%d) -> 2x-spread expectancy=%.3fR (n=%d)",
                  def.id,baseline.expectancyR,baseline.occurrences,stressedStats.expectancyR,m);
     }
  }

void RunFullPipeline()
  {
   g_registry.Init();
   RegisterAllScenarios(g_registry,InpEnableS021toS082);

   RunDetectionPass();
   ResolveAllOutcomes();
   EvaluateLifecycleForAll();

   if(InpEnableDynamicDiscovery)
     {
      string parents[]; int parentCount=CollectParentsForExpansion(parents);
      int totalGenerated=0;
      for(int depth=1; depth<=InpMaxScenarioDepth && totalGenerated<InpMaxGeneratedScenarios && parentCount>0; depth++)
        {
         string newIds[];
         int added=GenerateNextDepthLevel(g_registry,parents,parentCount,InpMaxGeneratedScenarios-totalGenerated,newIds);
         if(added==0) break;
         totalGenerated+=added;

         RunDetectionPass();
         ResolveAllOutcomes();
         EvaluateLifecycleForAll();

         string nextParents[]; int nextCount=0;
         for(int i=0;i<ArraySize(newIds);i++)
           {
            ScenarioDef d;
            if(g_registry.Get(newIds[i],d) && (d.status==STATUS_PROMISING || d.status==STATUS_VALIDATING))
              { ArrayResize(nextParents,nextCount+1); nextParents[nextCount]=newIds[i]; nextCount++; }
           }
         ArrayCopy(parents,nextParents); parentCount=nextCount;
        }
     }

   FinalizeOOSAndWalkForward();
   if(InpEnableParameterVariations) GenerateParameterVariationsForPromising();
   FinalizeOOSAndWalkForward();
   BuildRankingTableGlobal();
   if(InpEnableMonteCarloLikeStress) RunStressTestForValidated();

   if(InpExportCSV) ExportAllCSVs();
   PrintDiscoveryReport();
   g_lastFullResearchRun=TimeCurrent();
  }

void ExportAllCSVs()
  {
   int cnt=g_registry.Count();
   ScenarioStats trainAll[],validAll[],oosAll[];
   string ids[]; ENUM_SCENARIO_STATUS statuses[]; double wfRates[];
   ArrayResize(trainAll,cnt); ArrayResize(validAll,cnt); ArrayResize(oosAll,cnt);
   ArrayResize(ids,cnt); ArrayResize(statuses,cnt); ArrayResize(wfRates,cnt);
   ScenarioStats allForSummary[]; ArrayResize(allForSummary,0);
   ConfluenceComparison confRows[]; ArrayResize(confRows,0);

   int total=ArraySize(g_occurrences);
   for(int i=0;i<cnt;i++)
     {
      ScenarioDef def; g_registry.GetAt(i,def);
      ids[i]=def.id; statuses[i]=def.status;
      ComputeScenarioStats(g_occurrences,total,def.id,DATASET_TRAIN,InpMinSampleSize,InpWilsonZ,trainAll[i]);
      ComputeScenarioStats(g_occurrences,total,def.id,DATASET_VALIDATION,InpMinSampleSize,InpWilsonZ,validAll[i]);
      ScenarioStats oosSt; double wf; GetCachedStats(def.id,oosSt,wf);
      oosAll[i]=oosSt; wfRates[i]=wf;

      int n1=ArraySize(allForSummary);
      ArrayResize(allForSummary,n1+3);
      allForSummary[n1]=trainAll[i]; allForSummary[n1+1]=validAll[i]; allForSummary[n1+2]=oosAll[i];

      if(def.parentId!="")
        {
         ScenarioDef parentDef;
         if(g_registry.Get(def.parentId,parentDef))
           {
            ScenarioStats parentOos; double pwf;
            if(GetCachedStats(parentDef.id,parentOos,pwf))
              {
               ConfluenceComparison cc;
               CompareConfluence(parentOos,oosSt,InpMinSampleSize,cc);
               int n2=ArraySize(confRows); ArrayResize(confRows,n2+1); confRows[n2]=cc;
              }
           }
        }
     }

   string prefix=InpFilePrefix;
   CSV_WriteOccurrences(prefix+"scenario_occurrences.csv",g_occurrences,total);
   CSV_WriteSummary(prefix+"scenario_summary.csv",allForSummary,ArraySize(allForSummary));
   CSV_WriteProbability(prefix+"scenario_probability.csv",allForSummary,ArraySize(allForSummary));
   CSV_WriteConfluence(prefix+"scenario_confluence.csv",confRows,ArraySize(confRows));
   CSV_WriteValidation(prefix+"scenario_validation.csv",ids,statuses,trainAll,validAll,oosAll,wfRates,cnt);
  }

void PrintDiscoveryReport()
  {
   int cnt=g_registry.Count();
   int rejected=0,insufficient=0,promising=0,validating=0,validated=0,candidate=0;
   for(int i=0;i<cnt;i++)
     {
      ScenarioDef def; g_registry.GetAt(i,def);
      switch(def.status)
        {
         case STATUS_REJECTED: rejected++; break;
         case STATUS_INSUFFICIENT_DATA: insufficient++; break;
         case STATUS_PROMISING: promising++; break;
         case STATUS_VALIDATING: validating++; break;
         case STATUS_VALIDATED: case STATUS_LIVE: validated++; break;
         default: candidate++; break;
        }
     }
   if(insufficient==cnt && cnt>0)
      Print("GoldScalpEA: WARNING - every scenario is INSUFFICIENT_DATA, so live mode has nothing ",
            "VALIDATED to trade and will place zero orders. Check the warning above about actual vs ",
            "requested history range, and/or lower InpMinSampleSize if this account genuinely has ",
            "limited history, and/or set InpTrainStart/InpValidStart/InpOOSStart to fit inside it.");
   Print("===== GoldScalpEA Scenario Discovery Report =====");
   PrintFormat("Total scenarios: %d  Rejected: %d  Insufficient data: %d  Promising: %d  Validating: %d  Validated: %d",
               cnt,rejected,insufficient,promising,validating,validated);
   int topN=MathMin(10,ArraySize(g_rankResults));
   Print("Top ranked scenarios:");
   for(int i=0;i<topN;i++)
      PrintFormat("%d. %s  score=%.3f  sample=%.2f  expectancy=%.2f  prob(2R)=%.2f  drawdown=%.2f  stability=%.2f  complexityPenalty=%.3f",
                  i+1,g_rankResults[i].scenarioId,g_rankResults[i].totalScore,g_rankResults[i].sampleScore,
                  g_rankResults[i].expectancyScore,g_rankResults[i].probScore,g_rankResults[i].drawdownScore,
                  g_rankResults[i].stabilityScore,g_rankResults[i].complexityPenalty);
  }

//====================================================================== LIVE TICK HANDLING
void ProcessClosedTrades()
  {
   HistorySelect(g_lastProcessedDealTime,TimeCurrent()+1);
   int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
     {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;
      if((ulong)HistoryDealGetInteger(ticket,DEAL_MAGIC)!=InpMagicNumber) continue;
      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=EffectiveSymbol()) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      datetime dealTime=(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
      if(dealTime<=g_lastProcessedDealTime) continue;

      long posId=HistoryDealGetInteger(ticket,DEAL_POSITION_ID);
      double profit=HistoryDealGetDouble(ticket,DEAL_PROFIT)+HistoryDealGetDouble(ticket,DEAL_SWAP)+HistoryDealGetDouble(ticket,DEAL_COMMISSION);

      string scenarioId="UNKNOWN"; double rDist=0.0;
      for(int s=0;s<ArraySize(g_openTicketId);s++)
         if(g_openTicketId[s]==(ulong)posId)
           {
            scenarioId=g_openTicketScenario[s]; rDist=g_openTicketRDist[s];
            int last=ArraySize(g_openTicketId)-1;
            g_openTicketScenario[s]=g_openTicketScenario[last]; g_openTicketId[s]=g_openTicketId[last]; g_openTicketRDist[s]=g_openTicketRDist[last];
            ArrayResize(g_openTicketScenario,last); ArrayResize(g_openTicketId,last); ArrayResize(g_openTicketRDist,last);
            break;
           }

      double lots=HistoryDealGetDouble(ticket,DEAL_VOLUME);
      double rMultiple=0.0;
      if(rDist>0.0)
        {
         double perLotLoss=g_builder.Market().PriceDistanceToMoney(rDist,1.0);
         if(perLotLoss>0.0 && lots>0.0) rMultiple=profit/(perLotLoss*lots);
        }
      g_risk.OnTradeClosed(scenarioId,profit,rMultiple,dealTime);

      ExecutedTrade et; ZeroMemory(et);
      et.ticket=(ulong)posId; et.scenarioId=scenarioId; et.closeTime=dealTime; et.openTime=dealTime;
      et.direction=(ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket,DEAL_TYPE)==DEAL_TYPE_SELL? DIR_LONG:DIR_SHORT;
      et.closePrice=HistoryDealGetDouble(ticket,DEAL_PRICE); et.lots=lots; et.profit=profit; et.rMultiple=rMultiple;
      int n=ArraySize(g_trades); ArrayResize(g_trades,n+1,256); g_trades[n]=et;

      if(dealTime>g_lastProcessedDealTime) g_lastProcessedDealTime=dealTime;
     }
  }

// Spec #37 - monitor deployed scenarios' rolling live performance against their validated
// baseline and demote them (never on a handful of losses - gated by InpMinLiveSampleForDecay).
void CheckAllScenarioDecay()
  {
   LifecycleThresholds th=BuildLifecycleThresholds();
   int cnt=g_registry.Count();
   for(int i=0;i<cnt;i++)
     {
      ScenarioDef def; if(!g_registry.GetAt(i,def)) continue;
      if(def.status!=STATUS_VALIDATED && def.status!=STATUS_LIVE && def.status!=STATUS_DEGRADED) continue;

      double exitRs[]; ArrayResize(exitRs,0);
      int wins=0;
      for(int t=0;t<ArraySize(g_trades);t++)
        {
         if(g_trades[t].scenarioId!=def.id) continue;
         int m=ArraySize(exitRs); ArrayResize(exitRs,m+1); exitRs[m]=g_trades[t].rMultiple;
         if(g_trades[t].rMultiple>0.0) wins++;
        }
      ScenarioStats rolling; ZeroMemory(rolling);
      rolling.occurrences=ArraySize(exitRs); rolling.wins=wins; rolling.losses=rolling.occurrences-wins;
      rolling.expectancyR=ArrayMean(exitRs);
      rolling.sufficientSample=(rolling.occurrences>=InpMinLiveSampleForDecay);

      ScenarioStats baseline; double wf;
      if(!GetCachedStats(def.id,baseline,wf)) continue;

      bool degrade,retire;
      if(CheckDecay(baseline,rolling,th,degrade,retire))
        {
         if(retire) g_registry.SetStatus(def.id,STATUS_RETIRED);
         else if(degrade) g_registry.SetStatus(def.id,STATUS_DEGRADED);
         else if(def.status==STATUS_DEGRADED) g_registry.SetStatus(def.id,STATUS_VALIDATED);
        }
     }
  }

void RememberOpenTicket(const string scenarioId,const ulong ticket,const double rDist)
  {
   int n=ArraySize(g_openTicketId);
   ArrayResize(g_openTicketScenario,n+1); ArrayResize(g_openTicketId,n+1); ArrayResize(g_openTicketRDist,n+1);
   g_openTicketScenario[n]=scenarioId; g_openTicketId[n]=ticket; g_openTicketRDist[n]=rDist;
  }

void UpdateDashboardLive(const bool haveActive,const ScenarioOccurrence &activeOcc,const string activeName,
                          const ScenarioStats &activeStats)
  {
   if(!InpShowDashboard) return;
   string sym=EffectiveSymbol();
   double spread=g_builder.Market().CurrentSpreadPoints();
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   int openPos=CountOpenPositions(sym,InpMagicNumber);
   RenderDashboard(g_dash,sym,spread,SESSION_NONE,BIAS_NEUTRAL,VOL_MEDIUM,0.0,
                    haveActive,haveActive?activeOcc.scenarioId:"",activeName,
                    haveActive?activeOcc.direction:DIR_LONG,
                    haveActive?activeOcc.entryPrice:0.0,haveActive?activeOcc.slPrice:0.0,
                    haveActive?activeOcc.tpLevels[InpLiveTargetLevelIndex]:0.0,
                    activeStats.occurrences,activeStats.probR[1],activeStats.probR[3],activeStats.probR[5],
                    activeStats.expectancyR,activeStats.profitFactor,
                    g_risk.DailyPL(),0.0,openPos,0.0,g_risk.ConsecutiveLosses(),InpMode);
  }

//====================================================================== EVENT HANDLERS
int OnInit()
  {
   if(!g_market.Init(EffectiveSymbol()))
     { Print("GoldScalpEA: failed to initialize market context for ",EffectiveSymbol()); return(INIT_FAILED); }

   g_risk.Init(BuildRiskConfig());
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetTypeFillingBySymbol(EffectiveSymbol());
   if(InpShowDashboard) g_dash.Init();

   RunFullPipeline();

   g_lastProcessedDealTime=TimeCurrent(); // live trade tracking only looks at deals from EA start onward

   if(InpMode==MODE_LIVE)
      EventSetTimer(30);

   Print("GoldScalpEA initialized in ",EnumToString(InpMode)," mode. Registry size=",g_registry.Count());
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   g_builder.Deinit();
   if(InpShowDashboard) g_dash.Deinit();
   EventKillTimer();
  }

void OnTimer()
  {
   if(InpMode!=MODE_LIVE) return;
   g_risk.OnTick(TimeCurrent(),AccountInfoDouble(ACCOUNT_EQUITY));
   ProcessClosedTrades();
   CheckAllScenarioDecay();
   if(InpLiveResearchRefreshDays>0 && TimeCurrent()-g_lastFullResearchRun>=InpLiveResearchRefreshDays*86400)
      RunFullPipeline();
  }

void OnTick()
  {
   if(InpMode!=MODE_LIVE) return;
   string sym=EffectiveSymbol();

   datetime htfBarTime=iTime(sym,InpTF_HTF,1);
   if(htfBarTime>0 && htfBarTime!=g_lastHTFBarTime)
     {
      MqlRates r[];
      if(CopyRates(sym,InpTF_HTF,1,1,r)==1){ g_builder.AppendHTFBar(r[0]); g_lastHTFBarTime=htfBarTime; }
     }
   datetime ctxBarTime=iTime(sym,InpTF_Context,1);
   if(ctxBarTime>0 && ctxBarTime!=g_lastCtxBarTime)
     {
      MqlRates r[];
      if(CopyRates(sym,InpTF_Context,1,1,r)==1){ g_builder.AppendContextBar(r[0]); g_lastCtxBarTime=ctxBarTime; }
     }

   datetime curBarTime=iTime(sym,InpTF_Confirm,0);
   if(curBarTime==g_lastConfirmBarTime) return;

   MqlRates closedBar[];
   if(CopyRates(sym,InpTF_Confirm,1,1,closedBar)!=1) return;
   g_lastConfirmBarTime=curBarTime;

   double liveSpread=g_builder.Market().CurrentSpreadPoints();
   FeatureSnapshot snap;
   g_builder.BuildSnapshot(closedBar[0],liveSpread,snap);

   ScenarioOccurrence newOcc[]; int newCount;
   int periodSec=PeriodSeconds(InpTF_Confirm);
   g_stateMachine.OnBar(snap,g_registry,periodSec,g_builder.Market().Point(),liveSpread,newOcc,newCount);

   g_risk.OnTick(TimeCurrent(),AccountInfoDouble(ACCOUNT_EQUITY));

   bool haveActive=false; ScenarioOccurrence activeOcc; string activeName=""; ScenarioStats activeStats; ZeroMemory(activeStats);

   if(newCount>0)
     {
      ScenarioDef defs[]; ScenarioStats stats[]; RankingResult ranks[];
      ArrayResize(defs,newCount); ArrayResize(stats,newCount); ArrayResize(ranks,newCount);
      RankingWeights rw=BuildRankingWeights();
      for(int i=0;i<newCount;i++)
        {
         g_registry.Get(newOcc[i].scenarioId,defs[i]);
         double wf=0.0;
         if(!GetCachedStats(newOcc[i].scenarioId,stats[i],wf)) ZeroMemory(stats[i]);
         RankScenario(defs[i],stats[i],wf,rw,ranks[i]);
        }
      LiveEligibilityConfig ecfg=BuildLiveEligibilityConfig();
      string reasons[];
      int best=SelectBestEligible(newOcc,newCount,defs,stats,ranks,ecfg,liveSpread,reasons);

      if(best>=0)
        {
         haveActive=true; activeOcc=newOcc[best]; activeName=defs[best].name; activeStats=stats[best];
         string reason;
         int openPos=CountOpenPositions(sym,InpMagicNumber);
         if(g_risk.CanTrade(TimeCurrent(),newOcc[best].scenarioId,liveSpread,openPos,reason))
           {
            double lots=g_risk.CalcLotSize(AccountInfoDouble(ACCOUNT_EQUITY),newOcc[best].rDistance,g_builder.Market());
            ulong ticket;
            if(ExecuteOccurrence(g_trade,g_builder.Market(),newOcc[best],InpLiveTargetLevelIndex,lots,InpMagicNumber,
                                  newOcc[best].scenarioId,ticket))
              {
               g_risk.OnTradeOpened(newOcc[best].scenarioId);
               RememberOpenTicket(newOcc[best].scenarioId,ticket,newOcc[best].rDistance);
               PrintFormat("GoldScalpEA: executed %s ticket=%I64u dir=%s entry=%.2f sl=%.2f tp=%.2f",
                           newOcc[best].scenarioId,ticket,DirectionToString(newOcc[best].direction),
                           newOcc[best].entryPrice,newOcc[best].slPrice,newOcc[best].tpLevels[InpLiveTargetLevelIndex]);
              }
            else
               PrintFormat("GoldScalpEA: execution failed for %s retcode=%d %s",
                           newOcc[best].scenarioId,g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
           }
         else
            PrintFormat("GoldScalpEA: %s eligible but blocked by risk manager: %s",newOcc[best].scenarioId,reason);
        }
     }

   ProcessClosedTrades();
   UpdateDashboardLive(haveActive,activeOcc,activeName,activeStats);
  }
//+------------------------------------------------------------------+
