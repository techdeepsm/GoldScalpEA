//+------------------------------------------------------------------+
//| DynamicScenarioGenerator.mqh                                        |
//| Grows the scenario tree from validated/promising parents by         |
//| appending ONE compatible reusable building block at a time.         |
//| This is deliberately NOT a brute-force combination generator        |
//| (spec #19): every candidate must pass IsSequenceLegal() plus a      |
//| small set of grammar-compatibility rules below, and the caller is   |
//| expected to only pass PROMISING/VALIDATED parents back in for the   |
//| next depth (statistical gating lives in ValidationEngine, not       |
//| here - this file only knows what is syntactically feasible).        |
//+------------------------------------------------------------------+
#ifndef __GSEA_DYNAMICSCENARIOGENERATOR_MQH__
#define __GSEA_DYNAMICSCENARIOGENERATOR_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "ScenarioRegistry.mqh"
#include "ScenarioLibrary.mqh"      // MkStep
#include "ScenarioStateMachine.mqh" // IsSequenceLegal, IsContextStepType

struct BuildingBlockTemplate
  {
   string          label;
   ENUM_STEP_TYPE  longStep;
   ENUM_STEP_TYPE  shortStep;   // equals longStep for non-directional (context) blocks
   int             maxBars;
  };

int BuildBlockPool(BuildingBlockTemplate &pool[])
  {
   int n=0;
   ArrayResize(pool,20);
   pool[n].label="BOS";              pool[n].longStep=STEP_BOS_BULL;              pool[n].shortStep=STEP_BOS_BEAR;              pool[n].maxBars=30;  n++;
   pool[n].label="CHOCH";            pool[n].longStep=STEP_CHOCH_BULL;            pool[n].shortStep=STEP_CHOCH_BEAR;            pool[n].maxBars=30;  n++;
   pool[n].label="Displacement";     pool[n].longStep=STEP_DISPLACEMENT_BULL;     pool[n].shortStep=STEP_DISPLACEMENT_BEAR;     pool[n].maxBars=20;  n++;
   pool[n].label="FVG";              pool[n].longStep=STEP_FVG_BULL;              pool[n].shortStep=STEP_FVG_BEAR;              pool[n].maxBars=10;  n++;
   pool[n].label="FVGRetracement";   pool[n].longStep=STEP_FVG_RETRACEMENT;       pool[n].shortStep=STEP_FVG_RETRACEMENT;       pool[n].maxBars=30;  n++;
   pool[n].label="StructureRetest";  pool[n].longStep=STEP_STRUCTURE_RETEST;      pool[n].shortStep=STEP_STRUCTURE_RETEST;      pool[n].maxBars=30;  n++;
   pool[n].label="HTFAligned";       pool[n].longStep=CTX_HTF_BULLISH;            pool[n].shortStep=CTX_HTF_BEARISH;            pool[n].maxBars=0;   n++;
   pool[n].label="LondonSession";    pool[n].longStep=CTX_SESSION_LONDON;         pool[n].shortStep=CTX_SESSION_LONDON;         pool[n].maxBars=0;   n++;
   pool[n].label="NYSession";        pool[n].longStep=CTX_SESSION_NEWYORK;        pool[n].shortStep=CTX_SESSION_NEWYORK;        pool[n].maxBars=0;   n++;
   pool[n].label="OverlapSession";   pool[n].longStep=CTX_SESSION_OVERLAP;        pool[n].shortStep=CTX_SESSION_OVERLAP;        pool[n].maxBars=0;   n++;
   pool[n].label="AsianSession";     pool[n].longStep=CTX_SESSION_ASIAN;          pool[n].shortStep=CTX_SESSION_ASIAN;          pool[n].maxBars=0;   n++;
   pool[n].label="ATRExpansion";     pool[n].longStep=CTX_ATR_EXPANSION;          pool[n].shortStep=CTX_ATR_EXPANSION;          pool[n].maxBars=0;   n++;
   pool[n].label="ATRCompression";   pool[n].longStep=CTX_ATR_COMPRESSION;        pool[n].shortStep=CTX_ATR_COMPRESSION;        pool[n].maxBars=0;   n++;
   pool[n].label="VolHigh";          pool[n].longStep=CTX_VOL_HIGH;               pool[n].shortStep=CTX_VOL_HIGH;               pool[n].maxBars=0;   n++;
   pool[n].label="VolLow";           pool[n].longStep=CTX_VOL_LOW;                pool[n].shortStep=CTX_VOL_LOW;                pool[n].maxBars=0;   n++;
   ArrayResize(pool,n);
   return n;
  }

bool IsSessionCtxStep(const ENUM_STEP_TYPE k)
  { return (k==CTX_SESSION_ASIAN||k==CTX_SESSION_LONDON||k==CTX_SESSION_NEWYORK||k==CTX_SESSION_OVERLAP); }
bool IsAtrCtxStep(const ENUM_STEP_TYPE k) { return (k==CTX_ATR_EXPANSION||k==CTX_ATR_COMPRESSION); }
bool IsVolCtxStep(const ENUM_STEP_TYPE k) { return (k==CTX_VOL_HIGH||k==CTX_VOL_LOW); }
bool IsHtfCtxStep(const ENUM_STEP_TYPE k) { return (k==CTX_HTF_BULLISH||k==CTX_HTF_BEARISH); }

bool SequenceContainsFvgTrigger(const ScenarioStep &seq[],const int count)
  {
   for(int i=0;i<count;i++) if(seq[i].level_kind==STEP_FVG_BULL || seq[i].level_kind==STEP_FVG_BEAR) return true;
   return false;
  }

// Grammar-compatibility rules beyond plain legality: no duplicate condition types, no
// contradictory context filters stacked together, and FVG retracement requires a prior FVG.
bool IsBlockCompatible(const ScenarioDef &parent,const ENUM_STEP_TYPE chosenStep)
  {
   for(int i=0;i<parent.stepCount;i++)
      if(parent.sequence[i].level_kind==chosenStep) return false;

   if(chosenStep==STEP_FVG_RETRACEMENT && !SequenceContainsFvgTrigger(parent.sequence,parent.stepCount))
      return false;

   if(IsSessionCtxStep(chosenStep))
      for(int i=0;i<parent.stepCount;i++) if(IsSessionCtxStep(parent.sequence[i].level_kind)) return false;
   if(IsAtrCtxStep(chosenStep))
      for(int i=0;i<parent.stepCount;i++) if(IsAtrCtxStep(parent.sequence[i].level_kind)) return false;
   if(IsVolCtxStep(chosenStep))
      for(int i=0;i<parent.stepCount;i++) if(IsVolCtxStep(parent.sequence[i].level_kind)) return false;
   if(IsHtfCtxStep(chosenStep))
      for(int i=0;i<parent.stepCount;i++) if(IsHtfCtxStep(parent.sequence[i].level_kind)) return false;

   return true;
  }

// Appends one building block to 'parent', producing a fully-formed child ScenarioDef.
// The deterministic ID is keyed on the FAMILY ROOT (not the immediate parent) plus the full
// sorted component set, so the same net feature combination always maps to the same Dxxx ID
// no matter which order the blocks were added in (spec #18).
bool BuildChild(const ScenarioDef &parent,const string rootId,const BuildingBlockTemplate &tmpl,ScenarioDef &child)
  {
   ENUM_STEP_TYPE chosen = (parent.direction==DIR_LONG)? tmpl.longStep : tmpl.shortStep;
   if(!IsBlockCompatible(parent,chosen)) return false;

   child = parent;
   child.parentId = parent.id;
   child.isDynamic = true;
   child.status = STATUS_CANDIDATE;
   if(child.stepCount>=GSEA_MAX_STEPS) return false;
   child.sequence[child.stepCount]=MkStep(chosen,LEVEL_NONE,tmpl.maxBars);
   child.stepCount++;
   if(child.componentCount>=GSEA_MAX_COMPONENTS) return false;
   child.components[child.componentCount]=tmpl.label;
   child.componentCount++;
   child.depth = child.componentCount;

   if(!IsSequenceLegal(child.sequence,child.stepCount)) return false;

   child.id = MakeDynamicId(child.components,child.componentCount,rootId,child.direction);
   return true;
  }

// Generates every legal, non-duplicate one-block extension of 'parentId' and registers them as
// CANDIDATE. Returns the number actually added (skips anything already in the registry, so
// re-running this on the same parent twice is a no-op the second time).
int GenerateChildrenOf(CScenarioRegistry &reg,const string parentId,const int maxNewTotal,string &outNewIds[])
  {
   ArrayResize(outNewIds,0);
   ScenarioDef parent;
   if(!reg.Get(parentId,parent)) return 0;

   BuildingBlockTemplate pool[];
   int poolN = BuildBlockPool(pool);
   string rootId = reg.GetRootId(parentId);

   int added=0;
   for(int i=0;i<poolN && added<maxNewTotal;i++)
     {
      ScenarioDef child;
      if(!BuildChild(parent,rootId,pool[i],child)) continue;
      if(reg.FindIndex(child.id)>=0) continue; // already exists - same net combination seen before
      if(!reg.Add(child)) continue;
      int n=ArraySize(outNewIds);
      ArrayResize(outNewIds,n+1);
      outNewIds[n]=child.id;
      added++;
     }
   return added;
  }

// Orchestrates one full depth level: extend every parent in parentIds[], subject to a global cap
// on how many new scenarios this level may add (spec's MaxGeneratedScenarios input).
int GenerateNextDepthLevel(CScenarioRegistry &reg,string &parentIds[],const int parentCount,
                            const int maxTotalNew,string &outNewIds[])
  {
   ArrayResize(outNewIds,0);
   int total=0;
   for(int p=0;p<parentCount && total<maxTotalNew;p++)
     {
      string added[];
      int remaining = maxTotalNew-total;
      int got = GenerateChildrenOf(reg,parentIds[p],remaining,added);
      for(int i=0;i<got;i++)
        {
         int n=ArraySize(outNewIds);
         ArrayResize(outNewIds,n+1);
         outNewIds[n]=added[i];
        }
      total+=got;
     }
   return total;
  }

#endif // __GSEA_DYNAMICSCENARIOGENERATOR_MQH__
