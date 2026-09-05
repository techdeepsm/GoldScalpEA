//+------------------------------------------------------------------+
//| ScenarioStateMachine.mqh                                            |
//| Generic sequence matcher shared by all 82 preloaded scenarios and   |
//| every dynamically generated one. A scenario is nothing but an      |
//| ordered list of building-block steps; this engine advances a pool  |
//| of in-flight instances per closed confirmation-TF bar and emits a  |
//| ScenarioOccurrence exactly when a sequence fully completes.        |
//|                                                                     |
//| Context steps (CTX_*) never consume a bar: when the cursor reaches |
//| one, it is checked immediately against the SAME bar that completed |
//| the previous real step, and either the instance advances past it   |
//| at once or the whole occurrence is discarded right there.          |
//+------------------------------------------------------------------+
#ifndef __GSEA_SCENARIOSTATEMACHINE_MQH__
#define __GSEA_SCENARIOSTATEMACHINE_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "ScenarioRegistry.mqh"

bool IsContextStepType(const ENUM_STEP_TYPE k)
  {
   return (k==CTX_HTF_BULLISH || k==CTX_HTF_BEARISH || k==CTX_SESSION_ASIAN || k==CTX_SESSION_LONDON ||
           k==CTX_SESSION_NEWYORK || k==CTX_SESSION_OVERLAP || k==CTX_ATR_EXPANSION || k==CTX_ATR_COMPRESSION ||
           k==CTX_VOL_HIGH || k==CTX_VOL_LOW);
  }

// A minimal grammar/legality guard: rejects empty sequences, sequences that start on a context
// filter (context has nothing to attach to yet), and sequences longer than the fixed buffer.
// This is what "only generate logically feasible sequences" (spec #6/#19) is enforced against.
bool IsSequenceLegal(const ScenarioStep &seq[],const int stepCount)
  {
   if(stepCount<=0 || stepCount>GSEA_MAX_STEPS) return false;
   if(IsContextStepType(seq[0].level_kind)) return false;
   for(int i=0;i<stepCount;i++)
      if(seq[i].level_kind==STEP_NONE) return false;
   return true;
  }

double ResolveLevelValueFromSnapshot(const FeatureSnapshot &snap,const ENUM_LEVEL_TYPE lvl)
  {
   switch(lvl)
     {
      case LEVEL_ASIAN_HIGH:  return snap.asianHigh;
      case LEVEL_ASIAN_LOW:   return snap.asianLow;
      case LEVEL_PDH:         return snap.pdh;
      case LEVEL_PDL:         return snap.pdl;
      case LEVEL_PWH:         return snap.pwh;
      case LEVEL_PWL:         return snap.pwl;
      case LEVEL_EQUAL_HIGH:  return snap.equalHigh;
      case LEVEL_EQUAL_LOW:   return snap.equalLow;
      case LEVEL_LONDON_HIGH: return snap.londonHigh;
      case LEVEL_LONDON_LOW:  return snap.londonLow;
      case LEVEL_NY_HIGH:     return snap.nyHigh;
      case LEVEL_NY_LOW:      return snap.nyLow;
      case LEVEL_OR_HIGH:     return snap.orHigh;
      case LEVEL_OR_LOW:      return snap.orLow;
      default: return 0.0;
     }
  }

bool EvaluateStep(const ScenarioStep &step,const FeatureSnapshot &snap,ScenarioInstance &inst,const ENUM_DIRECTION dir)
  {
   switch(step.level_kind)
     {
      case STEP_SWEEP_HIGH:
         if((int)step.level<0 || (int)step.level>14 || !snap.sweptHighLevel[step.level]) return false;
         inst.levelPrice=ResolveLevelValueFromSnapshot(snap,step.level); inst.sweepExtreme=snap.high; return true;
      case STEP_SWEEP_LOW:
         if((int)step.level<0 || (int)step.level>14 || !snap.sweptLowLevel[step.level]) return false;
         inst.levelPrice=ResolveLevelValueFromSnapshot(snap,step.level); inst.sweepExtreme=snap.low; return true;
      case STEP_BREAKOUT_UP:
         if((int)step.level<0 || (int)step.level>14 || !snap.breakoutUpLevel[step.level]) return false;
         inst.levelPrice=ResolveLevelValueFromSnapshot(snap,step.level); inst.sweepExtreme=snap.high; return true;
      case STEP_BREAKOUT_DOWN:
         if((int)step.level<0 || (int)step.level>14 || !snap.breakoutDownLevel[step.level]) return false;
         inst.levelPrice=ResolveLevelValueFromSnapshot(snap,step.level); inst.sweepExtreme=snap.low; return true;
      case STEP_CLOSE_BACK_ABOVE: return snap.close>inst.levelPrice;
      case STEP_CLOSE_BACK_BELOW: return snap.close<inst.levelPrice;
      case STEP_REJECTION_BULL: return snap.largeWickRejectionBull;
      case STEP_REJECTION_BEAR: return snap.largeWickRejectionBear;
      case STEP_BOS_BULL: return snap.bosBull;
      case STEP_BOS_BEAR: return snap.bosBear;
      case STEP_CHOCH_BULL: return snap.chochBull;
      case STEP_CHOCH_BEAR: return snap.chochBear;
      case STEP_DISPLACEMENT_BULL: return snap.displacementBull;
      case STEP_DISPLACEMENT_BEAR: return snap.displacementBear;
      case STEP_FVG_BULL:
         if(!snap.fvgBull) return false;
         inst.fvgTop=snap.lastFvgBullTop; inst.fvgBottom=snap.lastFvgBullBottom; inst.fvgMid=snap.lastFvgBullMid;
         inst.fvgIsBull=true; return true;
      case STEP_FVG_BEAR:
         if(!snap.fvgBear) return false;
         inst.fvgTop=snap.lastFvgBearTop; inst.fvgBottom=snap.lastFvgBearBottom; inst.fvgMid=snap.lastFvgBearMid;
         inst.fvgIsBull=false; return true;
      // Polarity follows the FVG this instance actually captured, NOT the trade direction - a
      // reversal scenario (e.g. S032) can legitimately trade opposite to the FVG that failed.
      case STEP_FVG_RETRACEMENT: return inst.fvgIsBull? snap.fvgBullRetracement : snap.fvgBearRetracement;
      case STEP_FVG_FULL_FILL:   return inst.fvgIsBull? snap.fvgBullFullFill   : snap.fvgBearFullFill;
      case STEP_RETRACEMENT:
      case STEP_STRUCTURE_RETEST: return (dir==DIR_LONG)? snap.structureRetestBull : snap.structureRetestBear;
      case STEP_COMPRESSION: return snap.compression;
      case STEP_EXPANSION:   return snap.expansion;
      case STEP_EXHAUSTION:  return snap.exhaustion;
      case STEP_LARGE_WICK_REJECTION_BULL: return snap.largeWickRejectionBull;
      case STEP_LARGE_WICK_REJECTION_BEAR: return snap.largeWickRejectionBear;
      case STEP_HIGHER_LOW: return snap.higherLow;
      case STEP_LOWER_HIGH: return snap.lowerHigh;
      case STEP_VWAP_DEV_UPPER: return snap.vwapDevUpperTouch;
      case STEP_VWAP_DEV_LOWER: return snap.vwapDevLowerTouch;
      case STEP_RANGE_EXTREME_HIGH: return snap.rangeExtremeHighAsian || snap.rangeExtremeHighPDay;
      case STEP_RANGE_EXTREME_LOW:  return snap.rangeExtremeLowAsian  || snap.rangeExtremeLowPDay;
      case CTX_HTF_BULLISH:   return snap.htfBias==BIAS_BULLISH;
      case CTX_HTF_BEARISH:   return snap.htfBias==BIAS_BEARISH;
      case CTX_SESSION_ASIAN: return snap.session==SESSION_ASIAN;
      case CTX_SESSION_LONDON:return snap.session==SESSION_LONDON || snap.session==SESSION_LONDON_NY_OVERLAP;
      case CTX_SESSION_NEWYORK:return snap.session==SESSION_NEWYORK || snap.session==SESSION_LONDON_NY_OVERLAP;
      case CTX_SESSION_OVERLAP:return snap.session==SESSION_LONDON_NY_OVERLAP;
      case CTX_ATR_EXPANSION: return snap.atrExtremeExpansion;
      case CTX_ATR_COMPRESSION:return snap.volRegime==VOL_LOW;
      case CTX_VOL_HIGH: return snap.volRegime==VOL_HIGH;
      case CTX_VOL_LOW:  return snap.volRegime==VOL_LOW;
      default: return false;
     }
  }

//------------------------------------------------------------ entry/SL/TP resolution
void ComputeEntrySLTP(const ScenarioDef &def,const ScenarioInstance &inst,const FeatureSnapshot &snap,
                       const double point,const double spreadPts,
                       double &entry,double &sl,double &tpLevels[],double &rDistance)
  {
   int sign = DirSign(def.direction);
   double spread = spreadPts*point;

   double rawEntry;
   switch(def.entryModel)
     {
      case ENTRY_FVG_RETRACEMENT:   rawEntry = (inst.fvgMid!=0.0)? inst.fvgMid : snap.close; break;
      case ENTRY_STRUCTURE_RETEST:  rawEntry = (inst.levelPrice!=0.0)? inst.levelPrice : snap.close; break;
      case ENTRY_LIMIT_AT_LEVEL:    rawEntry = (inst.levelPrice!=0.0)? inst.levelPrice : snap.close; break;
      default:                      rawEntry = snap.close; break; // MARKET, BREAKOUT, REJECTION, DELAYED
     }
   entry = rawEntry + sign*(spread/2.0);

   double slDist;
   switch(def.slModel)
     {
      case SL_FIXED_POINTS:  slDist = def.fixedSLPoints*point; break;
      case SL_ATR_MULTIPLE:  slDist = snap.atr*def.atrMultSL; break;
      case SL_LIQUIDITY:     slDist = MathAbs(entry-inst.levelPrice) + def.slBufferPoints*point; break;
      case SL_SWEEP_EXTREME: slDist = MathAbs(entry-inst.sweepExtreme) + def.slBufferPoints*point; break;
      case SL_STRUCTURE:
      case SL_CANDLE_EXTREME:
      default:
         slDist = MathAbs(entry-((def.direction==DIR_LONG)? snap.low : snap.high)) + def.slBufferPoints*point;
         break;
     }
   if(slDist<=point*5.0) slDist=point*5.0; // sanity floor - never a zero/negative stop distance
   sl = entry - sign*slDist;
   rDistance = slDist;

   ArrayResize(tpLevels,GSEA_R_LEVELS);
   for(int i=0;i<GSEA_R_LEVELS;i++)
      tpLevels[i] = entry + sign*rDistance*GSEA_R_MULTIPLES[i];
  }

class CScenarioStateMachine
  {
private:
   ScenarioInstance m_instances[];
   int              m_instCount;
   long             m_nextOccId;

   void RemoveAt(const int idx)
     {
      m_instances[idx]=m_instances[m_instCount-1];
      m_instCount--;
     }

   int BarsBetween(const datetime a,const datetime b,const int periodSeconds) const
     {
      if(periodSeconds<=0) return 0;
      return (int)((b-a)/periodSeconds);
     }

public:
   void Init()
     {
      ArrayResize(m_instances,64,256);
      m_instCount=0;
      m_nextOccId=1;
     }

   // Advances every active instance and spawns new ones for scenarios whose first step fires
   // fresh on this bar. Emits zero or more completed occurrences. periodSeconds is the
   // confirmation timeframe's bar length, used to translate max_bars windows into elapsed time.
   void OnBar(const FeatureSnapshot &snap,CScenarioRegistry &registry,const int periodSeconds,
              const double point,const double spreadPts,
              ScenarioOccurrence &outOcc[],int &outCount)
     {
      outCount=0;
      ArrayResize(outOcc,0);

      // 1) advance existing instances
      for(int i=m_instCount-1;i>=0;i--)
        {
         ScenarioDef def;
         if(!registry.Get(m_instances[i].scenarioId,def) || !def.enabled)
           { RemoveAt(i); continue; }

         int cursor=m_instances[i].cursor;
         if(cursor>=def.stepCount){ RemoveAt(i); continue; }

         int maxBars = (def.sequence[cursor].max_bars>0)? def.sequence[cursor].max_bars : def.defaultExpiryBars;
         int elapsed = BarsBetween(m_instances[i].lastStepTime,snap.time,periodSeconds);
         if(elapsed>maxBars){ RemoveAt(i); continue; }

         if(!EvaluateStep(def.sequence[cursor],snap,m_instances[i],def.direction))
            continue; // still waiting, not yet expired

         m_instances[i].cursor++;
         m_instances[i].lastStepTime=snap.time;

         // auto-advance through any immediately-following context filters on the same bar
         while(m_instances[i].cursor<def.stepCount && IsContextStepType(def.sequence[m_instances[i].cursor].level_kind))
           {
            if(EvaluateStep(def.sequence[m_instances[i].cursor],snap,m_instances[i],def.direction))
               m_instances[i].cursor++;
            else
              {
               m_instances[i].cursor=-1; // mark failed
               break;
              }
           }

         if(m_instances[i].cursor<0){ RemoveAt(i); continue; }

         if(m_instances[i].cursor>=def.stepCount)
           {
            // sequence complete -> emit occurrence
            ScenarioOccurrence occ;
            ZeroMemory(occ);
            occ.occurrenceId = m_nextOccId++;
            occ.scenarioId = def.id;
            occ.detectTime = snap.time;
            occ.entryTime  = snap.time;
            occ.direction  = def.direction;
            occ.session    = snap.session;
            occ.htfBias    = snap.htfBias;
            occ.volRegime  = snap.volRegime;
            occ.atrAtEntry = snap.atr;
            occ.spreadAtEntry = spreadPts;
            occ.hour       = snap.hour;
            occ.dayOfWeek  = snap.dayOfWeek;
            occ.dataset    = DATASET_TRAIN; // reclassified later by ValidationEngine

            double entry,sl,rDist;
            double tps[];
            ComputeEntrySLTP(def,m_instances[i],snap,point,spreadPts,entry,sl,tps,rDist);
            occ.entryPrice=entry; occ.slPrice=sl; occ.rDistance=rDist;
            for(int k=0;k<GSEA_R_LEVELS;k++) occ.tpLevels[k]=tps[k];

            int n=ArraySize(outOcc);
            ArrayResize(outOcc,n+1);
            outOcc[n]=occ;
            outCount++;

            RemoveAt(i);
           }
        }

      // 2) spawn new instances for any enabled scenario whose trigger step fires fresh this bar
      int total=registry.Count();
      for(int s=0;s<total;s++)
        {
         ScenarioDef def;
         if(!registry.GetAt(s,def) || !def.enabled) continue;
         if(!IsSequenceLegal(def.sequence,def.stepCount)) continue;

         ScenarioInstance cand;
         ZeroMemory(cand);
         cand.scenarioId=def.id;
         cand.cursor=0;
         cand.startTime=snap.time;
         cand.lastStepTime=snap.time;
         cand.alive=true;

         if(!EvaluateStep(def.sequence[0],snap,cand,def.direction)) continue;
         cand.cursor=1;

         while(cand.cursor<def.stepCount && IsContextStepType(def.sequence[cand.cursor].level_kind))
           {
            if(EvaluateStep(def.sequence[cand.cursor],snap,cand,def.direction))
               cand.cursor++;
            else
              { cand.cursor=-1; break; }
           }
         if(cand.cursor<0) continue;

         if(cand.cursor>=def.stepCount)
           {
            // single-step (or all-context-tail) scenario completed on the trigger bar itself
            ScenarioOccurrence occ;
            ZeroMemory(occ);
            occ.occurrenceId=m_nextOccId++;
            occ.scenarioId=def.id;
            occ.detectTime=snap.time; occ.entryTime=snap.time;
            occ.direction=def.direction; occ.session=snap.session; occ.htfBias=snap.htfBias;
            occ.volRegime=snap.volRegime; occ.atrAtEntry=snap.atr; occ.spreadAtEntry=spreadPts;
            occ.hour=snap.hour; occ.dayOfWeek=snap.dayOfWeek; occ.dataset=DATASET_TRAIN;
            double entry,sl,rDist; double tps[];
            ComputeEntrySLTP(def,cand,snap,point,spreadPts,entry,sl,tps,rDist);
            occ.entryPrice=entry; occ.slPrice=sl; occ.rDistance=rDist;
            for(int k=0;k<GSEA_R_LEVELS;k++) occ.tpLevels[k]=tps[k];
            int n=ArraySize(outOcc);
            ArrayResize(outOcc,n+1);
            outOcc[n]=occ;
            outCount++;
            continue;
           }

         if(m_instCount>=ArraySize(m_instances))
            ArrayResize(m_instances,m_instCount+64,256);
         m_instances[m_instCount]=cand;
         m_instCount++;
        }
     }

   int ActiveInstanceCount() const { return m_instCount; }
  };

#endif // __GSEA_SCENARIOSTATEMACHINE_MQH__
