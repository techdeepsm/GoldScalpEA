//+------------------------------------------------------------------+
//| OutcomeEngine.mqh                                                   |
//| Resolves what actually happened after a scenario occurrence: which |
//| R levels were reached before the stop, MFE/MAE, and timing. This   |
//| is the ONLY place forward (future-relative-to-detection) bars are  |
//| touched, which is exactly what spec #41 permits: "future candles   |
//| may ONLY be used after the hypothetical entry to determine         |
//| outcome." Detection itself never calls into this file's inputs.    |
//+------------------------------------------------------------------+
#ifndef __GSEA_OUTCOMEENGINE_MQH__
#define __GSEA_OUTCOMEENGINE_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"

enum ENUM_AMBIGUITY_RULE
  {
   AMBIG_ASSUME_SL_FIRST = 0,  // conservative default: an SL+target overlap in one candle counts as a loss
   AMBIG_ASSUME_TP_FIRST = 1   // optimistic alternative, offered for sensitivity/robustness testing only
  };

// Binary search for the first bar index whose time is >= t (bars[] assumed ascending by time).
int FindBarIndexAtOrAfter(const MqlRates &bars[],const int nBars,const datetime t)
  {
   int lo=0, hi=nBars-1, ans=nBars;
   while(lo<=hi)
     {
      int mid=(lo+hi)/2;
      if(bars[mid].time>=t){ ans=mid; hi=mid-1; }
      else lo=mid+1;
     }
   return ans;
  }

// Scans forward from startIdx (the first bar strictly AFTER entry) resolving the occurrence.
// Returns false (occ.outcomeResolved=false) if the outcome could not be determined within the
// available data or the maxScanBars safety cap - such occurrences must be excluded from
// probability statistics rather than guessed at.
bool ComputeOutcome(ScenarioOccurrence &occ,const MqlRates &bars[],const int nBars,const int startIdx,
                     const int maxScanBars,const ENUM_AMBIGUITY_RULE rule)
  {
   occ.outcomeResolved=false;
   for(int k=0;k<GSEA_R_LEVELS;k++) occ.hitLevel[k]=false;
   occ.mfeR=0.0; occ.maeR=0.0; occ.barsToStop=-1; occ.barsToFirstTarget=-1; occ.stoppedOut=false; occ.exitR=0.0;

   if(startIdx<0 || startIdx>=nBars || occ.rDistance<=0.0) return false;

   bool anyHit=false;
   bool terminal=false;
   int scanned=0;
   int i=startIdx;
   for(; i<nBars && scanned<maxScanBars; i++,scanned++)
     {
      double hi=bars[i].high, lo=bars[i].low;
      double favExcursion = (occ.direction==DIR_LONG)? (hi-occ.entryPrice) : (occ.entryPrice-lo);
      double advExcursion = (occ.direction==DIR_LONG)? (occ.entryPrice-lo) : (hi-occ.entryPrice);
      occ.mfeR = MathMax(occ.mfeR, favExcursion/occ.rDistance);
      occ.maeR = MathMax(occ.maeR, advExcursion/occ.rDistance);

      bool slTouched = (occ.direction==DIR_LONG)? (lo<=occ.slPrice) : (hi>=occ.slPrice);

      bool touchedThisBar[GSEA_R_LEVELS];
      bool anyLevelTouched=false;
      for(int k=0;k<GSEA_R_LEVELS;k++)
        {
         if(occ.hitLevel[k]){ touchedThisBar[k]=false; continue; }
         bool touched = (occ.direction==DIR_LONG)? (hi>=occ.tpLevels[k]) : (lo<=occ.tpLevels[k]);
         touchedThisBar[k]=touched;
         if(touched) anyLevelTouched=true;
        }

      if(slTouched && anyLevelTouched && rule==AMBIG_ASSUME_TP_FIRST)
        {
         for(int k=0;k<GSEA_R_LEVELS;k++)
            if(touchedThisBar[k])
              {
               occ.hitLevel[k]=true;
               if(!anyHit){ anyHit=true; occ.barsToFirstTarget=scanned+1; }
              }
        }

      if(slTouched)
        {
         occ.stoppedOut=true; occ.barsToStop=scanned+1; occ.exitR=-1.0;
         terminal=true;
         break;
        }

      if(anyLevelTouched)
        {
         for(int k=0;k<GSEA_R_LEVELS;k++)
            if(touchedThisBar[k])
              {
               occ.hitLevel[k]=true;
               if(!anyHit){ anyHit=true; occ.barsToFirstTarget=scanned+1; }
              }
         bool allHit=true;
         for(int k=0;k<GSEA_R_LEVELS;k++) if(!occ.hitLevel[k]) allHit=false;
         if(allHit)
           {
            occ.exitR=GSEA_R_MULTIPLES[GSEA_R_LEVELS-1];
            terminal=true;
            break;
           }
        }
     }

   if(!terminal) return false; // ran out of data or scan budget before a definitive outcome

   if(!occ.stoppedOut)
     {
      // resolved by hitting every configured level without ever touching SL
      double best=0.0;
      for(int k=0;k<GSEA_R_LEVELS;k++) if(occ.hitLevel[k]) best=GSEA_R_MULTIPLES[k];
      occ.exitR=best;
     }

   occ.outcomeResolved=true;
   return true;
  }

#endif // __GSEA_OUTCOMEENGINE_MQH__
