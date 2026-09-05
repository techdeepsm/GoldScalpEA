//+------------------------------------------------------------------+
//| ProbabilityEngine.mqh                                               |
//| Turns a set of resolved ScenarioOccurrence records into the full    |
//| statistics block (spec #14): every number here is counted directly |
//| from observed occurrences - nothing is a hardcoded placeholder.     |
//+------------------------------------------------------------------+
#ifndef __GSEA_PROBABILITYENGINE_MQH__
#define __GSEA_PROBABILITYENGINE_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"

#define GSEA_WIN_LEVEL_INDEX 1  // index of 1.0R inside GSEA_R_MULTIPLES - the win/loss split used for streaks & PF

// occs[] must be in chronological order (ascending detectTime) for streak/drawdown math to mean
// anything; the research driver builds occurrences in that order by construction.
void ComputeScenarioStats(const ScenarioOccurrence &occs[],const int total,const string scenarioId,
                           const ENUM_DATASET dataset,const int minSampleSize,const double wilsonZ,
                           ScenarioStats &out)
  {
   ZeroMemory(out);
   out.scenarioId=scenarioId; out.dataset=dataset;

   double exitRs[]; ArrayResize(exitRs,0,1024);
   int levelHits[GSEA_R_LEVELS]; ArrayInitialize(levelHits,0);
   double sumMfe=0.0, sumMae=0.0; int mfeCount=0;
   double sumBarsToTarget=0.0; int barsToTargetCount=0;
   int wins=0, losses=0, n=0;
   int curStreak=0, curStreakSign=0, maxWinStreak=0, maxLossStreak=0;
   double equity=0.0, peak=0.0, maxDD=0.0;

   for(int i=0;i<total;i++)
     {
      if(occs[i].scenarioId!=scenarioId || occs[i].dataset!=dataset || !occs[i].outcomeResolved) continue;

      n++;
      int m=ArraySize(exitRs);
      ArrayResize(exitRs,m+1,1024);
      exitRs[m]=occs[i].exitR;

      for(int k=0;k<GSEA_R_LEVELS;k++) if(occs[i].hitLevel[k]) levelHits[k]++;

      bool isWin = occs[i].hitLevel[GSEA_WIN_LEVEL_INDEX];
      if(isWin) wins++; else losses++;

      sumMfe+=occs[i].mfeR; sumMae+=occs[i].maeR; mfeCount++;
      if(occs[i].barsToFirstTarget>=0){ sumBarsToTarget+=occs[i].barsToFirstTarget; barsToTargetCount++; }

      int sign = isWin? 1 : -1;
      if(curStreakSign==sign) curStreak++; else { curStreak=1; curStreakSign=sign; }
      if(sign>0) maxWinStreak=MathMax(maxWinStreak,curStreak); else maxLossStreak=MathMax(maxLossStreak,curStreak);

      equity+=occs[i].exitR;
      peak=MathMax(peak,equity);
      maxDD=MathMax(maxDD,peak-equity);
     }

   out.occurrences=n; out.wins=wins; out.losses=losses;
   out.winRate = (n>0)? (double)wins/n : 0.0;

   for(int k=0;k<GSEA_R_LEVELS;k++)
     {
      out.probR[k] = (n>0)? (double)levelHits[k]/n : 0.0;
      double lo,hiv;
      WilsonCI(levelHits[k],n,wilsonZ,lo,hiv);
      out.probR_ciLo[k]=lo; out.probR_ciHi[k]=hiv;
     }
   ComputePerLevelStats(levelHits,n,out.expectancyAtLevel,out.profitFactorAtLevel);

   double sumWin=0.0, sumLoss=0.0; int cw=0, cl=0;
   for(int i=0;i<ArraySize(exitRs);i++)
     {
      if(exitRs[i]>0.0){ sumWin+=exitRs[i]; cw++; }
      else { sumLoss+=exitRs[i]; cl++; }
     }
   out.avgWinR  = (cw>0)? sumWin/cw : 0.0;
   out.avgLossR = (cl>0)? sumLoss/cl : 0.0;  // signed (negative); display as magnitude where the spec shows "Average Loss"
   out.avgR     = ArrayMean(exitRs);
   out.medianR  = ArrayMedian(exitRs);
   out.expectancyR = out.avgR; // == P(win)*avgWin + P(loss)*avgLossR over this sample, i.e. the spec #15 formula
   out.profitFactor = (sumLoss!=0.0)? (sumWin/MathAbs(sumLoss)) : ((sumWin>0.0)? GSEA_MAX_PF : 0.0);
   out.maxDrawdownR = maxDD;
   out.maxWinStreak=maxWinStreak; out.maxLossStreak=maxLossStreak;
   out.avgMFE_R = (mfeCount>0)? sumMfe/mfeCount : 0.0;
   out.avgMAE_R = (mfeCount>0)? sumMae/mfeCount : 0.0;
   out.avgBarsToTarget = (barsToTargetCount>0)? sumBarsToTarget/barsToTargetCount : 0.0;
   out.sufficientSample = (n>=minSampleSize);
   out.status = out.sufficientSample? STATUS_CANDIDATE : STATUS_INSUFFICIENT_DATA;
  }

#endif // __GSEA_PROBABILITYENGINE_MQH__
