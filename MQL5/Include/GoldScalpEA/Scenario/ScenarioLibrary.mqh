//+------------------------------------------------------------------+
//| ScenarioLibrary.mqh                                                 |
//| The preloaded S001-S082 scenario library. Every definition is       |
//| assembled purely from the reusable grammar steps in Types.mqh /     |
//| ScenarioStateMachine.mqh - there is no per-scenario detection code, |
//| only data. This is what "do not hardcode each scenario             |
//| independently" (spec #18) means in practice: one generic engine,    |
//| 82 declarative sequences.                                           |
//|                                                                      |
//| Simplifications documented once here rather than per scenario:      |
//| - Where the prose spec does not name a specific liquidity level     |
//|   (e.g. many Tier 5/8/9 "generic" scenarios), a representative      |
//|   level or condition was chosen; that choice is noted inline.       |
//| - S060/S063/S064 mean-reversion triggers reuse a combined           |
//|   Asian-range/prior-day-range "extreme zone" flag rather than       |
//|   separate engines per range type, to avoid near-duplicate signals. |
//+------------------------------------------------------------------+
#ifndef __GSEA_SCENARIOLIBRARY_MQH__
#define __GSEA_SCENARIOLIBRARY_MQH__

#include "../Core/Types.mqh"
#include "ScenarioRegistry.mqh"

ScenarioStep MkStep(const ENUM_STEP_TYPE k,const ENUM_LEVEL_TYPE l=LEVEL_NONE,const int maxBars=0)
  {
   ScenarioStep s;
   s.level_kind=k; s.level=l; s.max_bars=maxBars;
   return s;
  }

void ResetScenario(ScenarioDef &d,const string id,const string name,const ENUM_DIRECTION dir)
  {
   ZeroMemory(d);
   d.id=id; d.name=name; d.direction=dir;
   d.stepCount=0; d.componentCount=0; d.parentId="";
   d.entryModel=ENTRY_MARKET; d.slModel=SL_ATR_MULTIPLE; d.tpModel=TP_FIXED_R;
   d.retracementPct=0.5; d.slBufferPoints=150; d.fixedSLPoints=300; d.fixedTPPoints=600;
   d.atrMultSL=1.5; d.atrMultTP=3.0; d.defaultExpiryBars=300;
   d.enabled=true; d.isDynamic=false; d.status=STATUS_CANDIDATE;
  }

void AddStep(ScenarioDef &d,const ENUM_STEP_TYPE k,const ENUM_LEVEL_TYPE l=LEVEL_NONE,const int maxBars=0)
  {
   if(d.stepCount<GSEA_MAX_STEPS){ d.sequence[d.stepCount]=MkStep(k,l,maxBars); d.stepCount++; }
  }

void AddComp(ScenarioDef &d,const string c)
  {
   if(d.componentCount<GSEA_MAX_COMPONENTS){ d.components[d.componentCount]=c; d.componentCount++; d.depth=d.componentCount; }
  }

//===================================================================
// TIER 1 - LIQUIDITY SWEEPS
//===================================================================
void Def_S001(ScenarioDef &d)
  {
   ResetScenario(d,"S001","Asian Low Sweep Reversal",DIR_LONG);
   AddStep(d,STEP_SWEEP_LOW,LEVEL_ASIAN_LOW,480);
   AddStep(d,STEP_CLOSE_BACK_ABOVE,LEVEL_NONE,12);
   AddComp(d,"AsianLowSweep"); AddComp(d,"CloseReclaim");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S002(ScenarioDef &d)
  {
   ResetScenario(d,"S002","Asian High Sweep Reversal",DIR_SHORT);
   AddStep(d,STEP_SWEEP_HIGH,LEVEL_ASIAN_HIGH,480);
   AddStep(d,STEP_CLOSE_BACK_BELOW,LEVEL_NONE,12);
   AddComp(d,"AsianHighSweep"); AddComp(d,"CloseReclaim");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S003(ScenarioDef &d)
  {
   ResetScenario(d,"S003","Previous Day Low Sweep",DIR_LONG);
   AddStep(d,STEP_SWEEP_LOW,LEVEL_PDL,288);
   AddStep(d,STEP_CLOSE_BACK_ABOVE,LEVEL_NONE,12);
   AddComp(d,"PDLSweep"); AddComp(d,"CloseReclaim");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S004(ScenarioDef &d)
  {
   ResetScenario(d,"S004","Previous Day High Sweep",DIR_SHORT);
   AddStep(d,STEP_SWEEP_HIGH,LEVEL_PDH,288);
   AddStep(d,STEP_CLOSE_BACK_BELOW,LEVEL_NONE,12);
   AddComp(d,"PDHSweep"); AddComp(d,"CloseReclaim");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S005(ScenarioDef &d)
  {
   ResetScenario(d,"S005","Previous Week Low Sweep",DIR_LONG);
   AddStep(d,STEP_SWEEP_LOW,LEVEL_PWL,2000);
   AddStep(d,STEP_CLOSE_BACK_ABOVE,LEVEL_NONE,20);
   AddComp(d,"PWLSweep"); AddComp(d,"CloseReclaim");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S006(ScenarioDef &d)
  {
   ResetScenario(d,"S006","Previous Week High Sweep",DIR_SHORT);
   AddStep(d,STEP_SWEEP_HIGH,LEVEL_PWH,2000);
   AddStep(d,STEP_CLOSE_BACK_BELOW,LEVEL_NONE,20);
   AddComp(d,"PWHSweep"); AddComp(d,"CloseReclaim");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S007(ScenarioDef &d)
  {
   ResetScenario(d,"S007","Equal Low Sweep",DIR_LONG);
   AddStep(d,STEP_SWEEP_LOW,LEVEL_EQUAL_LOW,500);
   AddStep(d,STEP_CLOSE_BACK_ABOVE,LEVEL_NONE,12);
   AddComp(d,"EqualLowSweep"); AddComp(d,"CloseReclaim");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S008(ScenarioDef &d)
  {
   ResetScenario(d,"S008","Equal High Sweep",DIR_SHORT);
   AddStep(d,STEP_SWEEP_HIGH,LEVEL_EQUAL_HIGH,500);
   AddStep(d,STEP_CLOSE_BACK_BELOW,LEVEL_NONE,12);
   AddComp(d,"EqualHighSweep"); AddComp(d,"CloseReclaim");
   d.slModel=SL_SWEEP_EXTREME;
  }

//===================================================================
// TIER 2 - SWEEP + STRUCTURE  (Asian-Low-Sweep family: parent = S001)
//===================================================================
void Def_S009(ScenarioDef &d)
  {
   ResetScenario(d,"S009","Sweep + BOS",DIR_LONG); d.parentId="S001";
   AddStep(d,STEP_SWEEP_LOW,LEVEL_ASIAN_LOW,480);
   AddStep(d,STEP_CLOSE_BACK_ABOVE,LEVEL_NONE,12);
   AddStep(d,STEP_BOS_BULL,LEVEL_NONE,30);
   AddComp(d,"AsianLowSweep"); AddComp(d,"CloseReclaim"); AddComp(d,"BOS");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S010(ScenarioDef &d)
  {
   ResetScenario(d,"S010","Sweep + CHOCH",DIR_LONG); d.parentId="S001";
   AddStep(d,STEP_SWEEP_LOW,LEVEL_ASIAN_LOW,480);
   AddStep(d,STEP_CLOSE_BACK_ABOVE,LEVEL_NONE,12);
   AddStep(d,STEP_CHOCH_BULL,LEVEL_NONE,30);
   AddComp(d,"AsianLowSweep"); AddComp(d,"CloseReclaim"); AddComp(d,"CHOCH");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S011(ScenarioDef &d)
  {
   ResetScenario(d,"S011","Sweep + Displacement",DIR_LONG); d.parentId="S001";
   AddStep(d,STEP_SWEEP_LOW,LEVEL_ASIAN_LOW,480);
   AddStep(d,STEP_CLOSE_BACK_ABOVE,LEVEL_NONE,12);
   AddStep(d,STEP_DISPLACEMENT_BULL,LEVEL_NONE,20);
   AddComp(d,"AsianLowSweep"); AddComp(d,"CloseReclaim"); AddComp(d,"Displacement");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S012(ScenarioDef &d)
  {
   ResetScenario(d,"S012","Sweep + BOS + Displacement",DIR_LONG); d.parentId="S001";
   AddStep(d,STEP_SWEEP_LOW,LEVEL_ASIAN_LOW,480);
   AddStep(d,STEP_CLOSE_BACK_ABOVE,LEVEL_NONE,12);
   AddStep(d,STEP_BOS_BULL,LEVEL_NONE,30);
   AddStep(d,STEP_DISPLACEMENT_BULL,LEVEL_NONE,20);
   AddComp(d,"AsianLowSweep"); AddComp(d,"CloseReclaim"); AddComp(d,"BOS"); AddComp(d,"Displacement");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S013(ScenarioDef &d)
  {
   ResetScenario(d,"S013","Sweep + FVG",DIR_LONG); d.parentId="S001";
   AddStep(d,STEP_SWEEP_LOW,LEVEL_ASIAN_LOW,480);
   AddStep(d,STEP_CLOSE_BACK_ABOVE,LEVEL_NONE,12);
   AddStep(d,STEP_DISPLACEMENT_BULL,LEVEL_NONE,20);
   AddStep(d,STEP_FVG_BULL,LEVEL_NONE,10);
   AddComp(d,"AsianLowSweep"); AddComp(d,"CloseReclaim"); AddComp(d,"Displacement"); AddComp(d,"FVG");
   d.slModel=SL_SWEEP_EXTREME; d.entryModel=ENTRY_FVG_RETRACEMENT;
  }
void Def_S014(ScenarioDef &d)
  {
   ResetScenario(d,"S014","Sweep + BOS + FVG",DIR_LONG); d.parentId="S001";
   AddStep(d,STEP_SWEEP_LOW,LEVEL_ASIAN_LOW,480);
   AddStep(d,STEP_CLOSE_BACK_ABOVE,LEVEL_NONE,12);
   AddStep(d,STEP_BOS_BULL,LEVEL_NONE,30);
   AddStep(d,STEP_FVG_BULL,LEVEL_NONE,10);
   AddStep(d,STEP_FVG_RETRACEMENT,LEVEL_NONE,30);
   AddComp(d,"AsianLowSweep"); AddComp(d,"CloseReclaim"); AddComp(d,"BOS"); AddComp(d,"FVG");
   d.slModel=SL_SWEEP_EXTREME; d.entryModel=ENTRY_FVG_RETRACEMENT;
  }
void Def_S015(ScenarioDef &d)
  {
   ResetScenario(d,"S015","Sweep + HTF Bias",DIR_LONG); d.parentId="S001";
   AddStep(d,STEP_SWEEP_LOW,LEVEL_ASIAN_LOW,480);
   AddStep(d,STEP_CLOSE_BACK_ABOVE,LEVEL_NONE,12);
   AddStep(d,CTX_HTF_BULLISH);
   AddComp(d,"AsianLowSweep"); AddComp(d,"CloseReclaim"); AddComp(d,"HTFBullish");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S016(ScenarioDef &d)
  {
   ResetScenario(d,"S016","Sweep + HTF + BOS + FVG",DIR_LONG); d.parentId="S001";
   AddStep(d,STEP_SWEEP_LOW,LEVEL_ASIAN_LOW,480);
   AddStep(d,STEP_CLOSE_BACK_ABOVE,LEVEL_NONE,12);
   AddStep(d,CTX_HTF_BULLISH);
   AddStep(d,STEP_BOS_BULL,LEVEL_NONE,30);
   AddStep(d,STEP_DISPLACEMENT_BULL,LEVEL_NONE,20);
   AddStep(d,STEP_FVG_BULL,LEVEL_NONE,10);
   AddStep(d,STEP_FVG_RETRACEMENT,LEVEL_NONE,30);
   AddComp(d,"AsianLowSweep"); AddComp(d,"CloseReclaim"); AddComp(d,"HTFBullish");
   AddComp(d,"BOS"); AddComp(d,"Displacement"); AddComp(d,"FVG");
   d.slModel=SL_SWEEP_EXTREME; d.entryModel=ENTRY_FVG_RETRACEMENT;
  }

//===================================================================
// TIER 3 - BREAKOUTS
//===================================================================
void Def_S017(ScenarioDef &d)
  {
   ResetScenario(d,"S017","Asian Range Breakout Long",DIR_LONG);
   AddStep(d,STEP_BREAKOUT_UP,LEVEL_ASIAN_HIGH,480);
   AddStep(d,STEP_DISPLACEMENT_BULL,LEVEL_NONE,10);
   AddComp(d,"AsianHighBreakout"); AddComp(d,"Displacement");
   d.entryModel=ENTRY_BREAKOUT; d.slModel=SL_LIQUIDITY;
  }
void Def_S018(ScenarioDef &d)
  {
   ResetScenario(d,"S018","Asian Range Breakout Short",DIR_SHORT);
   AddStep(d,STEP_BREAKOUT_DOWN,LEVEL_ASIAN_LOW,480);
   AddStep(d,STEP_DISPLACEMENT_BEAR,LEVEL_NONE,10);
   AddComp(d,"AsianLowBreakdown"); AddComp(d,"Displacement");
   d.entryModel=ENTRY_BREAKOUT; d.slModel=SL_LIQUIDITY;
  }
void Def_S019(ScenarioDef &d)
  {
   ResetScenario(d,"S019","Asian Breakout Retest Long",DIR_LONG);
   AddStep(d,STEP_BREAKOUT_UP,LEVEL_ASIAN_HIGH,480);
   AddStep(d,STEP_DISPLACEMENT_BULL,LEVEL_NONE,10);
   AddStep(d,STEP_STRUCTURE_RETEST,LEVEL_NONE,30);
   AddComp(d,"AsianHighBreakout"); AddComp(d,"Displacement"); AddComp(d,"Retest");
   d.entryModel=ENTRY_STRUCTURE_RETEST; d.slModel=SL_LIQUIDITY;
  }
void Def_S020(ScenarioDef &d)
  {
   ResetScenario(d,"S020","Asian Breakout Retest Short",DIR_SHORT);
   AddStep(d,STEP_BREAKOUT_DOWN,LEVEL_ASIAN_LOW,480);
   AddStep(d,STEP_DISPLACEMENT_BEAR,LEVEL_NONE,10);
   AddStep(d,STEP_STRUCTURE_RETEST,LEVEL_NONE,30);
   AddComp(d,"AsianLowBreakdown"); AddComp(d,"Displacement"); AddComp(d,"Retest");
   d.entryModel=ENTRY_STRUCTURE_RETEST; d.slModel=SL_LIQUIDITY;
  }
void Def_S021(ScenarioDef &d)
  {
   ResetScenario(d,"S021","London Opening Range Breakout Long",DIR_LONG);
   AddStep(d,STEP_BREAKOUT_UP,LEVEL_OR_HIGH,60);
   AddStep(d,CTX_SESSION_LONDON);
   AddStep(d,STEP_DISPLACEMENT_BULL,LEVEL_NONE,10);
   AddComp(d,"LondonORBreakout"); AddComp(d,"Displacement");
   d.entryModel=ENTRY_BREAKOUT; d.slModel=SL_LIQUIDITY;
  }
void Def_S022(ScenarioDef &d)
  {
   ResetScenario(d,"S022","London Opening Range Breakout Short",DIR_SHORT);
   AddStep(d,STEP_BREAKOUT_DOWN,LEVEL_OR_LOW,60);
   AddStep(d,CTX_SESSION_LONDON);
   AddStep(d,STEP_DISPLACEMENT_BEAR,LEVEL_NONE,10);
   AddComp(d,"LondonORBreakdown"); AddComp(d,"Displacement");
   d.entryModel=ENTRY_BREAKOUT; d.slModel=SL_LIQUIDITY;
  }
void Def_S023(ScenarioDef &d)
  {
   ResetScenario(d,"S023","New York Opening Range Breakout Long",DIR_LONG);
   AddStep(d,STEP_BREAKOUT_UP,LEVEL_OR_HIGH,60);
   AddStep(d,CTX_SESSION_NEWYORK);
   AddStep(d,STEP_DISPLACEMENT_BULL,LEVEL_NONE,10);
   AddComp(d,"NYORBreakout"); AddComp(d,"Displacement");
   d.entryModel=ENTRY_BREAKOUT; d.slModel=SL_LIQUIDITY;
  }
void Def_S024(ScenarioDef &d)
  {
   ResetScenario(d,"S024","New York Opening Range Breakout Short",DIR_SHORT);
   AddStep(d,STEP_BREAKOUT_DOWN,LEVEL_OR_LOW,60);
   AddStep(d,CTX_SESSION_NEWYORK);
   AddStep(d,STEP_DISPLACEMENT_BEAR,LEVEL_NONE,10);
   AddComp(d,"NYORBreakdown"); AddComp(d,"Displacement");
   d.entryModel=ENTRY_BREAKOUT; d.slModel=SL_LIQUIDITY;
  }

//===================================================================
// TIER 4 - FVG / IMBALANCE
//===================================================================
void Def_S025(ScenarioDef &d)
  {
   ResetScenario(d,"S025","Bullish FVG Retracement",DIR_LONG);
   AddStep(d,STEP_DISPLACEMENT_BULL);
   AddStep(d,STEP_FVG_BULL,LEVEL_NONE,10);
   AddStep(d,STEP_FVG_RETRACEMENT,LEVEL_NONE,60);
   AddComp(d,"Displacement"); AddComp(d,"FVG"); AddComp(d,"FVGRetracement");
   d.entryModel=ENTRY_FVG_RETRACEMENT;
  }
void Def_S026(ScenarioDef &d)
  {
   ResetScenario(d,"S026","Bearish FVG Retracement",DIR_SHORT);
   AddStep(d,STEP_DISPLACEMENT_BEAR);
   AddStep(d,STEP_FVG_BEAR,LEVEL_NONE,10);
   AddStep(d,STEP_FVG_RETRACEMENT,LEVEL_NONE,60);
   AddComp(d,"Displacement"); AddComp(d,"FVG"); AddComp(d,"FVGRetracement");
   d.entryModel=ENTRY_FVG_RETRACEMENT;
  }
void Def_S027(ScenarioDef &d)
  {
   ResetScenario(d,"S027","Sweep -> Bullish FVG",DIR_LONG); // level not specified in spec; PDL used as representative
   AddStep(d,STEP_SWEEP_LOW,LEVEL_PDL,288);
   AddStep(d,STEP_CLOSE_BACK_ABOVE,LEVEL_NONE,12);
   AddStep(d,STEP_DISPLACEMENT_BULL,LEVEL_NONE,20);
   AddStep(d,STEP_FVG_BULL,LEVEL_NONE,10);
   AddComp(d,"PDLSweep"); AddComp(d,"CloseReclaim"); AddComp(d,"Displacement"); AddComp(d,"FVG");
   d.slModel=SL_SWEEP_EXTREME; d.entryModel=ENTRY_FVG_RETRACEMENT;
  }
void Def_S028(ScenarioDef &d)
  {
   ResetScenario(d,"S028","Sweep -> Bearish FVG",DIR_SHORT);
   AddStep(d,STEP_SWEEP_HIGH,LEVEL_PDH,288);
   AddStep(d,STEP_CLOSE_BACK_BELOW,LEVEL_NONE,12);
   AddStep(d,STEP_DISPLACEMENT_BEAR,LEVEL_NONE,20);
   AddStep(d,STEP_FVG_BEAR,LEVEL_NONE,10);
   AddComp(d,"PDHSweep"); AddComp(d,"CloseReclaim"); AddComp(d,"Displacement"); AddComp(d,"FVG");
   d.slModel=SL_SWEEP_EXTREME; d.entryModel=ENTRY_FVG_RETRACEMENT;
  }
void Def_S029(ScenarioDef &d)
  {
   ResetScenario(d,"S029","BOS -> Bullish FVG",DIR_LONG);
   AddStep(d,STEP_BOS_BULL);
   AddStep(d,STEP_FVG_BULL,LEVEL_NONE,10);
   AddComp(d,"BOS"); AddComp(d,"FVG");
   d.entryModel=ENTRY_FVG_RETRACEMENT;
  }
void Def_S030(ScenarioDef &d)
  {
   ResetScenario(d,"S030","BOS -> Bearish FVG",DIR_SHORT);
   AddStep(d,STEP_BOS_BEAR);
   AddStep(d,STEP_FVG_BEAR,LEVEL_NONE,10);
   AddComp(d,"BOS"); AddComp(d,"FVG");
   d.entryModel=ENTRY_FVG_RETRACEMENT;
  }
void Def_S031(ScenarioDef &d)
  {
   ResetScenario(d,"S031","FVG Consequent Encroachment",DIR_LONG);
   AddStep(d,STEP_FVG_BULL);
   AddStep(d,STEP_FVG_RETRACEMENT,LEVEL_NONE,60);
   AddComp(d,"FVG"); AddComp(d,"FiftyPercentEntry");
   d.retracementPct=0.5; d.entryModel=ENTRY_FVG_RETRACEMENT;
  }
void Def_S032(ScenarioDef &d)
  {
   ResetScenario(d,"S032","FVG Full Fill Reversal",DIR_SHORT); // bullish FVG fails -> short reversal
   AddStep(d,STEP_FVG_BULL);
   AddStep(d,STEP_FVG_FULL_FILL,LEVEL_NONE,60);
   AddStep(d,STEP_REJECTION_BEAR,LEVEL_NONE,10);
   AddComp(d,"FVG"); AddComp(d,"FullFill"); AddComp(d,"Rejection");
   d.slModel=SL_ATR_MULTIPLE;
  }

//===================================================================
// TIER 5 - DISPLACEMENT
//===================================================================
void Def_S033(ScenarioDef &d)
  {
   ResetScenario(d,"S033","Bullish Displacement Pullback",DIR_LONG);
   AddStep(d,STEP_DISPLACEMENT_BULL);
   AddStep(d,STEP_STRUCTURE_RETEST,LEVEL_NONE,30);
   AddComp(d,"Displacement"); AddComp(d,"Retest");
  }
void Def_S034(ScenarioDef &d)
  {
   ResetScenario(d,"S034","Bearish Displacement Pullback",DIR_SHORT);
   AddStep(d,STEP_DISPLACEMENT_BEAR);
   AddStep(d,STEP_STRUCTURE_RETEST,LEVEL_NONE,30);
   AddComp(d,"Displacement"); AddComp(d,"Retest");
  }
void Def_S035(ScenarioDef &d)
  {
   ResetScenario(d,"S035","Sweep + Bullish Displacement",DIR_LONG); // PDL used to differ from S011 (Asian-based)
   AddStep(d,STEP_SWEEP_LOW,LEVEL_PDL,288);
   AddStep(d,STEP_CLOSE_BACK_ABOVE,LEVEL_NONE,12);
   AddStep(d,STEP_DISPLACEMENT_BULL,LEVEL_NONE,20);
   AddComp(d,"PDLSweep"); AddComp(d,"CloseReclaim"); AddComp(d,"Displacement");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S036(ScenarioDef &d)
  {
   ResetScenario(d,"S036","Sweep + Bearish Displacement",DIR_SHORT);
   AddStep(d,STEP_SWEEP_HIGH,LEVEL_PDH,288);
   AddStep(d,STEP_CLOSE_BACK_BELOW,LEVEL_NONE,12);
   AddStep(d,STEP_DISPLACEMENT_BEAR,LEVEL_NONE,20);
   AddComp(d,"PDHSweep"); AddComp(d,"CloseReclaim"); AddComp(d,"Displacement");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S037(ScenarioDef &d)
  {
   ResetScenario(d,"S037","Compression -> Expansion Long",DIR_LONG);
   AddStep(d,STEP_COMPRESSION,LEVEL_NONE,60);
   AddStep(d,STEP_EXPANSION,LEVEL_NONE,10);
   AddStep(d,STEP_DISPLACEMENT_BULL,LEVEL_NONE,5);
   AddComp(d,"Compression"); AddComp(d,"Expansion"); AddComp(d,"Displacement");
  }
void Def_S038(ScenarioDef &d)
  {
   ResetScenario(d,"S038","Compression -> Expansion Short",DIR_SHORT);
   AddStep(d,STEP_COMPRESSION,LEVEL_NONE,60);
   AddStep(d,STEP_EXPANSION,LEVEL_NONE,10);
   AddStep(d,STEP_DISPLACEMENT_BEAR,LEVEL_NONE,5);
   AddComp(d,"Compression"); AddComp(d,"Expansion"); AddComp(d,"Displacement");
  }

//===================================================================
// TIER 6 - PREVIOUS DAY LIQUIDITY
//===================================================================
void Def_S039(ScenarioDef &d)
  {
   ResetScenario(d,"S039","PDH Breakout Continuation",DIR_LONG);
   AddStep(d,STEP_BREAKOUT_UP,LEVEL_PDH,288);
   AddStep(d,STEP_DISPLACEMENT_BULL,LEVEL_NONE,10);
   AddComp(d,"PDHBreakout"); AddComp(d,"Displacement");
   d.entryModel=ENTRY_BREAKOUT; d.slModel=SL_LIQUIDITY;
  }
void Def_S040(ScenarioDef &d)
  {
   ResetScenario(d,"S040","PDH False Breakout",DIR_SHORT);
   AddStep(d,STEP_BREAKOUT_UP,LEVEL_PDH,288);
   AddStep(d,STEP_CLOSE_BACK_BELOW,LEVEL_NONE,12);
   AddComp(d,"PDHBreakout"); AddComp(d,"FalseBreakFail");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S041(ScenarioDef &d)
  {
   ResetScenario(d,"S041","PDH Sweep + Reversal",DIR_SHORT);
   AddStep(d,STEP_SWEEP_HIGH,LEVEL_PDH,288);
   AddStep(d,STEP_CLOSE_BACK_BELOW,LEVEL_NONE,12);
   AddComp(d,"PDHSweep"); AddComp(d,"CloseReclaim");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S042(ScenarioDef &d)
  {
   ResetScenario(d,"S042","PDL Breakdown Continuation",DIR_SHORT);
   AddStep(d,STEP_BREAKOUT_DOWN,LEVEL_PDL,288);
   AddStep(d,STEP_DISPLACEMENT_BEAR,LEVEL_NONE,10);
   AddComp(d,"PDLBreakdown"); AddComp(d,"Displacement");
   d.entryModel=ENTRY_BREAKOUT; d.slModel=SL_LIQUIDITY;
  }
void Def_S043(ScenarioDef &d)
  {
   ResetScenario(d,"S043","PDL False Breakdown",DIR_LONG);
   AddStep(d,STEP_BREAKOUT_DOWN,LEVEL_PDL,288);
   AddStep(d,STEP_CLOSE_BACK_ABOVE,LEVEL_NONE,12);
   AddComp(d,"PDLBreakdown"); AddComp(d,"FalseBreakFail");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S044(ScenarioDef &d)
  {
   ResetScenario(d,"S044","PDL Sweep + Reversal",DIR_LONG);
   AddStep(d,STEP_SWEEP_LOW,LEVEL_PDL,288);
   AddStep(d,STEP_CLOSE_BACK_ABOVE,LEVEL_NONE,12);
   AddComp(d,"PDLSweep"); AddComp(d,"CloseReclaim");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S045(ScenarioDef &d)
  {
   ResetScenario(d,"S045","PDH -> FVG Short",DIR_SHORT);
   AddStep(d,STEP_SWEEP_HIGH,LEVEL_PDH,288);
   AddStep(d,STEP_CLOSE_BACK_BELOW,LEVEL_NONE,12);
   AddStep(d,STEP_DISPLACEMENT_BEAR,LEVEL_NONE,10);
   AddStep(d,STEP_FVG_BEAR,LEVEL_NONE,10);
   AddComp(d,"PDHSweep"); AddComp(d,"CloseReclaim"); AddComp(d,"Displacement"); AddComp(d,"FVG");
   d.slModel=SL_SWEEP_EXTREME; d.entryModel=ENTRY_FVG_RETRACEMENT;
  }
void Def_S046(ScenarioDef &d)
  {
   ResetScenario(d,"S046","PDL -> FVG Long",DIR_LONG);
   AddStep(d,STEP_SWEEP_LOW,LEVEL_PDL,288);
   AddStep(d,STEP_CLOSE_BACK_ABOVE,LEVEL_NONE,12);
   AddStep(d,STEP_DISPLACEMENT_BULL,LEVEL_NONE,10);
   AddStep(d,STEP_FVG_BULL,LEVEL_NONE,10);
   AddComp(d,"PDLSweep"); AddComp(d,"CloseReclaim"); AddComp(d,"Displacement"); AddComp(d,"FVG");
   d.slModel=SL_SWEEP_EXTREME; d.entryModel=ENTRY_FVG_RETRACEMENT;
  }

//===================================================================
// TIER 7 - SESSION SCENARIOS
//===================================================================
void Def_S047(ScenarioDef &d)
  {
   ResetScenario(d,"S047","London Sweep -> Reversal",DIR_LONG);
   AddStep(d,STEP_SWEEP_LOW,LEVEL_ASIAN_LOW,288);
   AddStep(d,STEP_CLOSE_BACK_ABOVE,LEVEL_NONE,12);
   AddStep(d,CTX_SESSION_LONDON);
   AddComp(d,"AsianLowSweep"); AddComp(d,"CloseReclaim"); AddComp(d,"LondonSession");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S048(ScenarioDef &d)
  {
   ResetScenario(d,"S048","London Breakout -> Continuation",DIR_LONG);
   AddStep(d,STEP_BREAKOUT_UP,LEVEL_ASIAN_HIGH,288);
   AddStep(d,CTX_SESSION_LONDON);
   AddStep(d,STEP_DISPLACEMENT_BULL,LEVEL_NONE,10);
   AddComp(d,"AsianHighBreakout"); AddComp(d,"LondonSession"); AddComp(d,"Displacement");
   d.entryModel=ENTRY_BREAKOUT; d.slModel=SL_LIQUIDITY;
  }
void Def_S049(ScenarioDef &d)
  {
   ResetScenario(d,"S049","London Sweep -> NY Continuation",DIR_LONG);
   AddStep(d,STEP_SWEEP_LOW,LEVEL_ASIAN_LOW,288);
   AddStep(d,STEP_CLOSE_BACK_ABOVE,LEVEL_NONE,12);
   AddStep(d,CTX_SESSION_LONDON);
   AddStep(d,STEP_BOS_BULL,LEVEL_NONE,120);
   AddStep(d,CTX_SESSION_NEWYORK);
   AddComp(d,"AsianLowSweep"); AddComp(d,"CloseReclaim"); AddComp(d,"LondonSession");
   AddComp(d,"BOS"); AddComp(d,"NYSession");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S050(ScenarioDef &d)
  {
   ResetScenario(d,"S050","London Trend -> Pullback",DIR_LONG);
   AddStep(d,STEP_BOS_BULL);
   AddStep(d,CTX_SESSION_LONDON);
   AddStep(d,STEP_STRUCTURE_RETEST,LEVEL_NONE,30);
   AddComp(d,"BOS"); AddComp(d,"LondonSession"); AddComp(d,"Retest");
  }
void Def_S051(ScenarioDef &d)
  {
   ResetScenario(d,"S051","NY Liquidity Sweep -> Reversal",DIR_SHORT);
   AddStep(d,STEP_SWEEP_HIGH,LEVEL_ASIAN_HIGH,400);
   AddStep(d,STEP_CLOSE_BACK_BELOW,LEVEL_NONE,12);
   AddStep(d,CTX_SESSION_NEWYORK);
   AddComp(d,"AsianHighSweep"); AddComp(d,"CloseReclaim"); AddComp(d,"NYSession");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S052(ScenarioDef &d)
  {
   ResetScenario(d,"S052","NY Opening Breakout",DIR_LONG);
   AddStep(d,STEP_BREAKOUT_UP,LEVEL_OR_HIGH,60);
   AddStep(d,CTX_SESSION_NEWYORK);
   AddStep(d,STEP_DISPLACEMENT_BULL,LEVEL_NONE,10);
   AddComp(d,"NYORBreakout"); AddComp(d,"Displacement");
   d.entryModel=ENTRY_BREAKOUT; d.slModel=SL_LIQUIDITY;
  }
void Def_S053(ScenarioDef &d)
  {
   ResetScenario(d,"S053","NY Continuation of London Trend",DIR_LONG);
   AddStep(d,STEP_BOS_BULL);
   AddStep(d,CTX_SESSION_NEWYORK);
   AddStep(d,STEP_STRUCTURE_RETEST,LEVEL_NONE,30);
   AddComp(d,"BOS"); AddComp(d,"NYSession"); AddComp(d,"Retest");
  }
void Def_S054(ScenarioDef &d)
  {
   ResetScenario(d,"S054","NY London-High Sweep",DIR_SHORT);
   AddStep(d,STEP_SWEEP_HIGH,LEVEL_LONDON_HIGH,120);
   AddStep(d,STEP_CLOSE_BACK_BELOW,LEVEL_NONE,12);
   AddStep(d,CTX_SESSION_NEWYORK);
   AddComp(d,"LondonHighSweep"); AddComp(d,"CloseReclaim"); AddComp(d,"NYSession");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S055(ScenarioDef &d)
  {
   ResetScenario(d,"S055","NY London-Low Sweep",DIR_LONG);
   AddStep(d,STEP_SWEEP_LOW,LEVEL_LONDON_LOW,120);
   AddStep(d,STEP_CLOSE_BACK_ABOVE,LEVEL_NONE,12);
   AddStep(d,CTX_SESSION_NEWYORK);
   AddComp(d,"LondonLowSweep"); AddComp(d,"CloseReclaim"); AddComp(d,"NYSession");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S056(ScenarioDef &d)
  {
   ResetScenario(d,"S056","London/NY Overlap Liquidity Sweep",DIR_LONG);
   AddStep(d,STEP_SWEEP_LOW,LEVEL_ASIAN_LOW,400);
   AddStep(d,STEP_CLOSE_BACK_ABOVE,LEVEL_NONE,12);
   AddStep(d,CTX_SESSION_OVERLAP);
   AddComp(d,"AsianLowSweep"); AddComp(d,"CloseReclaim"); AddComp(d,"Overlap");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S057(ScenarioDef &d)
  {
   ResetScenario(d,"S057","London/NY Overlap Breakout",DIR_LONG);
   AddStep(d,STEP_BREAKOUT_UP,LEVEL_LONDON_HIGH,120);
   AddStep(d,CTX_SESSION_OVERLAP);
   AddStep(d,STEP_DISPLACEMENT_BULL,LEVEL_NONE,10);
   AddComp(d,"LondonHighBreakout"); AddComp(d,"Overlap"); AddComp(d,"Displacement");
   d.entryModel=ENTRY_BREAKOUT; d.slModel=SL_LIQUIDITY;
  }
void Def_S058(ScenarioDef &d)
  {
   ResetScenario(d,"S058","London/NY Overlap BOS + FVG",DIR_LONG);
   AddStep(d,STEP_BOS_BULL);
   AddStep(d,CTX_SESSION_OVERLAP);
   AddStep(d,STEP_FVG_BULL,LEVEL_NONE,10);
   AddComp(d,"BOS"); AddComp(d,"Overlap"); AddComp(d,"FVG");
   d.entryModel=ENTRY_FVG_RETRACEMENT;
  }
void Def_S059(ScenarioDef &d)
  {
   ResetScenario(d,"S059","London/NY Overlap Displacement Continuation",DIR_LONG);
   AddStep(d,STEP_DISPLACEMENT_BULL);
   AddStep(d,CTX_SESSION_OVERLAP);
   AddStep(d,STEP_STRUCTURE_RETEST,LEVEL_NONE,30);
   AddComp(d,"Displacement"); AddComp(d,"Overlap"); AddComp(d,"Retest");
  }

//===================================================================
// TIER 8 - MEAN REVERSION
//===================================================================
void Def_S060(ScenarioDef &d)
  {
   ResetScenario(d,"S060","Extreme ATR Expansion -> Mean Reversion",DIR_SHORT);
   AddStep(d,STEP_EXPANSION);
   AddStep(d,STEP_LARGE_WICK_REJECTION_BEAR,LEVEL_NONE,10);
   AddComp(d,"ATRExpansion"); AddComp(d,"WickRejection");
  }
void Def_S061(ScenarioDef &d)
  {
   ResetScenario(d,"S061","VWAP Upper Deviation -> Reversion",DIR_SHORT);
   AddStep(d,STEP_VWAP_DEV_UPPER);
   AddStep(d,STEP_REJECTION_BEAR,LEVEL_NONE,10);
   AddComp(d,"VWAPUpperDeviation"); AddComp(d,"Rejection");
  }
void Def_S062(ScenarioDef &d)
  {
   ResetScenario(d,"S062","VWAP Lower Deviation -> Reversion",DIR_LONG);
   AddStep(d,STEP_VWAP_DEV_LOWER);
   AddStep(d,STEP_REJECTION_BULL,LEVEL_NONE,10);
   AddComp(d,"VWAPLowerDeviation"); AddComp(d,"Rejection");
  }
void Def_S063(ScenarioDef &d)
  {
   ResetScenario(d,"S063","Previous Day Range Extreme -> Reversion",DIR_LONG);
   AddStep(d,STEP_RANGE_EXTREME_LOW);
   AddStep(d,STEP_REJECTION_BULL,LEVEL_NONE,10);
   AddComp(d,"PDayRangeExtreme"); AddComp(d,"Rejection");
  }
void Def_S064(ScenarioDef &d)
  {
   ResetScenario(d,"S064","Asian Range Extreme -> Reversion",DIR_LONG);
   AddStep(d,STEP_RANGE_EXTREME_LOW);
   AddStep(d,STEP_REJECTION_BULL,LEVEL_NONE,10);
   AddComp(d,"AsianRangeExtreme"); AddComp(d,"Rejection");
  }
void Def_S065(ScenarioDef &d)
  {
   ResetScenario(d,"S065","3-Candle Exhaustion -> Reversal",DIR_SHORT);
   AddStep(d,STEP_EXHAUSTION);
   AddStep(d,STEP_REJECTION_BEAR,LEVEL_NONE,10);
   AddComp(d,"Exhaustion"); AddComp(d,"Rejection");
  }
void Def_S066(ScenarioDef &d)
  {
   ResetScenario(d,"S066","Large Wick Rejection -> Reversion",DIR_LONG);
   AddStep(d,STEP_LARGE_WICK_REJECTION_BULL);
   AddComp(d,"WickRejection");
  }

//===================================================================
// TIER 9 - TREND CONTINUATION
//===================================================================
void Def_S067(ScenarioDef &d)
  {
   ResetScenario(d,"S067","HTF Bullish + LTF BOS + Pullback",DIR_LONG);
   AddStep(d,STEP_BOS_BULL);
   AddStep(d,CTX_HTF_BULLISH);
   AddStep(d,STEP_STRUCTURE_RETEST,LEVEL_NONE,30);
   AddComp(d,"BOS"); AddComp(d,"HTFBullish"); AddComp(d,"Retest");
  }
void Def_S068(ScenarioDef &d)
  {
   ResetScenario(d,"S068","HTF Bearish + LTF BOS + Pullback",DIR_SHORT);
   AddStep(d,STEP_BOS_BEAR);
   AddStep(d,CTX_HTF_BEARISH);
   AddStep(d,STEP_STRUCTURE_RETEST,LEVEL_NONE,30);
   AddComp(d,"BOS"); AddComp(d,"HTFBearish"); AddComp(d,"Retest");
  }
void Def_S069(ScenarioDef &d)
  {
   ResetScenario(d,"S069","Bullish BOS -> FVG -> Continuation",DIR_LONG);
   AddStep(d,STEP_BOS_BULL);
   AddStep(d,STEP_FVG_BULL,LEVEL_NONE,10);
   AddStep(d,STEP_FVG_RETRACEMENT,LEVEL_NONE,30);
   AddComp(d,"BOS"); AddComp(d,"FVG"); AddComp(d,"FVGRetracement");
   d.entryModel=ENTRY_FVG_RETRACEMENT;
  }
void Def_S070(ScenarioDef &d)
  {
   ResetScenario(d,"S070","Bearish BOS -> FVG -> Continuation",DIR_SHORT);
   AddStep(d,STEP_BOS_BEAR);
   AddStep(d,STEP_FVG_BEAR,LEVEL_NONE,10);
   AddStep(d,STEP_FVG_RETRACEMENT,LEVEL_NONE,30);
   AddComp(d,"BOS"); AddComp(d,"FVG"); AddComp(d,"FVGRetracement");
   d.entryModel=ENTRY_FVG_RETRACEMENT;
  }
void Def_S071(ScenarioDef &d)
  {
   ResetScenario(d,"S071","Higher Low -> Displacement Long",DIR_LONG);
   AddStep(d,STEP_HIGHER_LOW);
   AddStep(d,STEP_DISPLACEMENT_BULL,LEVEL_NONE,20);
   AddComp(d,"HigherLow"); AddComp(d,"Displacement");
  }
void Def_S072(ScenarioDef &d)
  {
   ResetScenario(d,"S072","Lower High -> Displacement Short",DIR_SHORT);
   AddStep(d,STEP_LOWER_HIGH);
   AddStep(d,STEP_DISPLACEMENT_BEAR,LEVEL_NONE,20);
   AddComp(d,"LowerHigh"); AddComp(d,"Displacement");
  }
void Def_S073(ScenarioDef &d)
  {
   ResetScenario(d,"S073","London Trend -> NY Pullback Long",DIR_LONG);
   AddStep(d,STEP_BOS_BULL);
   AddStep(d,CTX_SESSION_LONDON);
   AddStep(d,STEP_STRUCTURE_RETEST,LEVEL_NONE,60);
   AddStep(d,CTX_SESSION_NEWYORK);
   AddComp(d,"BOS"); AddComp(d,"LondonSession"); AddComp(d,"Retest"); AddComp(d,"NYSession");
  }
void Def_S074(ScenarioDef &d)
  {
   ResetScenario(d,"S074","London Trend -> NY Pullback Short",DIR_SHORT);
   AddStep(d,STEP_BOS_BEAR);
   AddStep(d,CTX_SESSION_LONDON);
   AddStep(d,STEP_STRUCTURE_RETEST,LEVEL_NONE,60);
   AddStep(d,CTX_SESSION_NEWYORK);
   AddComp(d,"BOS"); AddComp(d,"LondonSession"); AddComp(d,"Retest"); AddComp(d,"NYSession");
  }

//===================================================================
// TIER 10 - FAILED BREAKOUTS
//===================================================================
void Def_S075(ScenarioDef &d)
  {
   ResetScenario(d,"S075","Asian High False Break",DIR_SHORT);
   AddStep(d,STEP_BREAKOUT_UP,LEVEL_ASIAN_HIGH,288);
   AddStep(d,STEP_CLOSE_BACK_BELOW,LEVEL_NONE,12);
   AddComp(d,"AsianHighBreakout"); AddComp(d,"FalseBreakFail");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S076(ScenarioDef &d)
  {
   ResetScenario(d,"S076","Asian Low False Break",DIR_LONG);
   AddStep(d,STEP_BREAKOUT_DOWN,LEVEL_ASIAN_LOW,288);
   AddStep(d,STEP_CLOSE_BACK_ABOVE,LEVEL_NONE,12);
   AddComp(d,"AsianLowBreakdown"); AddComp(d,"FalseBreakFail");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S077(ScenarioDef &d)
  {
   ResetScenario(d,"S077","PDH False Break",DIR_SHORT);
   AddStep(d,STEP_BREAKOUT_UP,LEVEL_PDH,288);
   AddStep(d,STEP_CLOSE_BACK_BELOW,LEVEL_NONE,12);
   AddComp(d,"PDHBreakout"); AddComp(d,"FalseBreakFail");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S078(ScenarioDef &d)
  {
   ResetScenario(d,"S078","PDL False Break",DIR_LONG);
   AddStep(d,STEP_BREAKOUT_DOWN,LEVEL_PDL,288);
   AddStep(d,STEP_CLOSE_BACK_ABOVE,LEVEL_NONE,12);
   AddComp(d,"PDLBreakdown"); AddComp(d,"FalseBreakFail");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S079(ScenarioDef &d)
  {
   ResetScenario(d,"S079","London High False Break",DIR_SHORT);
   AddStep(d,STEP_BREAKOUT_UP,LEVEL_LONDON_HIGH,120);
   AddStep(d,STEP_CLOSE_BACK_BELOW,LEVEL_NONE,12);
   AddComp(d,"LondonHighBreakout"); AddComp(d,"FalseBreakFail");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S080(ScenarioDef &d)
  {
   ResetScenario(d,"S080","London Low False Break",DIR_LONG);
   AddStep(d,STEP_BREAKOUT_DOWN,LEVEL_LONDON_LOW,120);
   AddStep(d,STEP_CLOSE_BACK_ABOVE,LEVEL_NONE,12);
   AddComp(d,"LondonLowBreakdown"); AddComp(d,"FalseBreakFail");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S081(ScenarioDef &d)
  {
   ResetScenario(d,"S081","Opening Range False Break Long",DIR_LONG);
   AddStep(d,STEP_BREAKOUT_DOWN,LEVEL_OR_LOW,60);
   AddStep(d,STEP_CLOSE_BACK_ABOVE,LEVEL_NONE,12);
   AddComp(d,"ORBreakdown"); AddComp(d,"FalseBreakFail");
   d.slModel=SL_SWEEP_EXTREME;
  }
void Def_S082(ScenarioDef &d)
  {
   ResetScenario(d,"S082","Opening Range False Break Short",DIR_SHORT);
   AddStep(d,STEP_BREAKOUT_UP,LEVEL_OR_HIGH,60);
   AddStep(d,STEP_CLOSE_BACK_BELOW,LEVEL_NONE,12);
   AddComp(d,"ORBreakout"); AddComp(d,"FalseBreakFail");
   d.slModel=SL_SWEEP_EXTREME;
  }

// Registers all 82 preloaded scenarios. initiallyEnabledUpTo lets the caller implement spec #54
// ("default enabled for research: S001-S020") by disabling everything past a given tier at load time.
void RegisterAllScenarios(CScenarioRegistry &reg,const bool enableS021toS082)
  {
   ScenarioDef d;
#define GSEA_REG(fn) { fn(d); if(!enableS021toS082){ int __n=(int)StringToInteger(StringSubstr(d.id,1)); if(__n>20) d.enabled=false; } reg.Add(d); }
   GSEA_REG(Def_S001) GSEA_REG(Def_S002) GSEA_REG(Def_S003) GSEA_REG(Def_S004)
   GSEA_REG(Def_S005) GSEA_REG(Def_S006) GSEA_REG(Def_S007) GSEA_REG(Def_S008)
   GSEA_REG(Def_S009) GSEA_REG(Def_S010) GSEA_REG(Def_S011) GSEA_REG(Def_S012)
   GSEA_REG(Def_S013) GSEA_REG(Def_S014) GSEA_REG(Def_S015) GSEA_REG(Def_S016)
   GSEA_REG(Def_S017) GSEA_REG(Def_S018) GSEA_REG(Def_S019) GSEA_REG(Def_S020)
   GSEA_REG(Def_S021) GSEA_REG(Def_S022) GSEA_REG(Def_S023) GSEA_REG(Def_S024)
   GSEA_REG(Def_S025) GSEA_REG(Def_S026) GSEA_REG(Def_S027) GSEA_REG(Def_S028)
   GSEA_REG(Def_S029) GSEA_REG(Def_S030) GSEA_REG(Def_S031) GSEA_REG(Def_S032)
   GSEA_REG(Def_S033) GSEA_REG(Def_S034) GSEA_REG(Def_S035) GSEA_REG(Def_S036)
   GSEA_REG(Def_S037) GSEA_REG(Def_S038) GSEA_REG(Def_S039) GSEA_REG(Def_S040)
   GSEA_REG(Def_S041) GSEA_REG(Def_S042) GSEA_REG(Def_S043) GSEA_REG(Def_S044)
   GSEA_REG(Def_S045) GSEA_REG(Def_S046) GSEA_REG(Def_S047) GSEA_REG(Def_S048)
   GSEA_REG(Def_S049) GSEA_REG(Def_S050) GSEA_REG(Def_S051) GSEA_REG(Def_S052)
   GSEA_REG(Def_S053) GSEA_REG(Def_S054) GSEA_REG(Def_S055) GSEA_REG(Def_S056)
   GSEA_REG(Def_S057) GSEA_REG(Def_S058) GSEA_REG(Def_S059) GSEA_REG(Def_S060)
   GSEA_REG(Def_S061) GSEA_REG(Def_S062) GSEA_REG(Def_S063) GSEA_REG(Def_S064)
   GSEA_REG(Def_S065) GSEA_REG(Def_S066) GSEA_REG(Def_S067) GSEA_REG(Def_S068)
   GSEA_REG(Def_S069) GSEA_REG(Def_S070) GSEA_REG(Def_S071) GSEA_REG(Def_S072)
   GSEA_REG(Def_S073) GSEA_REG(Def_S074) GSEA_REG(Def_S075) GSEA_REG(Def_S076)
   GSEA_REG(Def_S077) GSEA_REG(Def_S078) GSEA_REG(Def_S079) GSEA_REG(Def_S080)
   GSEA_REG(Def_S081) GSEA_REG(Def_S082)
#undef GSEA_REG
  }

#endif // __GSEA_SCENARIOLIBRARY_MQH__
