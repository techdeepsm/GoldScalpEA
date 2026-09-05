//+------------------------------------------------------------------+
//| RankingEngine.mqh                                                   |
//| Transparent, multi-factor scenario ranking (spec #28). Every        |
//| component of the score is stored on the result and can be shown    |
//| individually - there is no single opaque number hiding the trade-  |
//| offs. Complexity is penalised, not rewarded (spec #27/#52).         |
//+------------------------------------------------------------------+
#ifndef __GSEA_RANKINGENGINE_MQH__
#define __GSEA_RANKINGENGINE_MQH__

#include "../Core/Types.mqh"
#include "ConfluenceEngine.mqh" // GSEA_P2R_INDEX

struct RankingWeights
  {
   int    sampleCap;                  // sample size at which the sample score saturates to 1.0
   double expectancyCap;              // expectancy (R) mapping to a score of 1.0
   double pfRangeAboveOne;            // profit factor range above 1.0 mapping to a score of 1.0
   double ddCap;                      // max drawdown (R) at which the drawdown score bottoms at 0.0
   double wSample, wExpectancy, wProb, wPF, wDrawdown, wStability;
   double complexityPenaltyPerComponent;
  };

struct RankingResult
  {
   string scenarioId;
   double sampleScore;
   double expectancyScore;
   double probScore;
   double pfScore;
   double drawdownScore;
   double stabilityScore;
   double complexityPenalty;
   double totalScore;
  };

double NormalizeSample(const int n,const int cap)
  {
   if(cap<=0) return 0.0;
   double v = MathLog(1.0+MathMax(0,n))/MathLog(1.0+cap);
   return MathMax(0.0,MathMin(1.0,v));
  }

double Clamp01(const double v) { return MathMax(0.0,MathMin(1.0,v)); }

void RankScenario(const ScenarioDef &def,const ScenarioStats &stats,const double walkForwardPassRate,
                   const RankingWeights &w,RankingResult &out)
  {
   ZeroMemory(out);
   out.scenarioId=def.id;
   out.sampleScore      = NormalizeSample(stats.occurrences,w.sampleCap);
   out.expectancyScore  = (w.expectancyCap>0.0)? Clamp01(stats.expectancyR/w.expectancyCap) : 0.0;
   out.probScore        = Clamp01(stats.probR[GSEA_P2R_INDEX]);
   out.pfScore          = (w.pfRangeAboveOne>0.0)? Clamp01((stats.profitFactor-1.0)/w.pfRangeAboveOne) : 0.0;
   out.drawdownScore    = (w.ddCap>0.0)? Clamp01(1.0-stats.maxDrawdownR/w.ddCap) : 0.0;
   out.stabilityScore   = Clamp01(walkForwardPassRate);
   out.complexityPenalty= def.depth*w.complexityPenaltyPerComponent;

   out.totalScore = w.wSample*out.sampleScore + w.wExpectancy*out.expectancyScore + w.wProb*out.probScore
                   + w.wPF*out.pfScore + w.wDrawdown*out.drawdownScore + w.wStability*out.stabilityScore
                   - out.complexityPenalty;
  }

// Simple descending insertion sort - ranking lists are at most a few hundred entries.
void SortRankingResultsDesc(RankingResult &arr[],const int count)
  {
   for(int i=1;i<count;i++)
     {
      RankingResult key=arr[i];
      int j=i-1;
      while(j>=0 && arr[j].totalScore<key.totalScore){ arr[j+1]=arr[j]; j--; }
      arr[j+1]=key;
     }
  }

#endif // __GSEA_RANKINGENGINE_MQH__
