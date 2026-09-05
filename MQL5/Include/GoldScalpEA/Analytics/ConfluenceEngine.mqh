//+------------------------------------------------------------------+
//| ConfluenceEngine.mqh                                                |
//| Answers "did adding this condition actually help?" by comparing a  |
//| child scenario's stats against its immediate parent's - measured,  |
//| never assumed (spec #17/#24). The comparison rule is intentionally |
//| simple and fully visible: no single opaque score decides it.       |
//+------------------------------------------------------------------+
#ifndef __GSEA_CONFLUENCEENGINE_MQH__
#define __GSEA_CONFLUENCEENGINE_MQH__

#include "../Core/Types.mqh"
#include "ProbabilityEngine.mqh" // GSEA_WIN_LEVEL_INDEX

#define GSEA_P2R_INDEX 3 // index of 2.0R inside GSEA_R_MULTIPLES

struct ConfluenceComparison
  {
   string parentId, childId;
   int    parentSample, childSample;
   double parentP1R, childP1R;
   double parentP2R, childP2R;
   double parentExpectancy, childExpectancy;
   double parentPF, childPF;
   bool   childSampleSufficient;
   bool   improvesP2R;
   bool   improvesExpectancy;
   bool   improvesProfitFactor;
   bool   overallImproved;      // transparent rule: expectancy AND P(2R) both improve on a sufficient sample
  };

void CompareConfluence(const ScenarioStats &parentStats,const ScenarioStats &childStats,
                        const int minSampleSize,ConfluenceComparison &out)
  {
   ZeroMemory(out);
   out.parentId=parentStats.scenarioId; out.childId=childStats.scenarioId;
   out.parentSample=parentStats.occurrences; out.childSample=childStats.occurrences;
   out.parentP1R=parentStats.probR[GSEA_WIN_LEVEL_INDEX]; out.childP1R=childStats.probR[GSEA_WIN_LEVEL_INDEX];
   out.parentP2R=parentStats.probR[GSEA_P2R_INDEX];       out.childP2R=childStats.probR[GSEA_P2R_INDEX];
   out.parentExpectancy=parentStats.expectancyR; out.childExpectancy=childStats.expectancyR;
   out.parentPF=parentStats.profitFactor; out.childPF=childStats.profitFactor;

   out.childSampleSufficient = (childStats.occurrences>=minSampleSize);
   out.improvesP2R          = out.childSampleSufficient && (childStats.probR[GSEA_P2R_INDEX] > parentStats.probR[GSEA_P2R_INDEX]);
   out.improvesExpectancy   = out.childSampleSufficient && (childStats.expectancyR > parentStats.expectancyR);
   out.improvesProfitFactor = out.childSampleSufficient && (childStats.profitFactor > parentStats.profitFactor);
   out.overallImproved      = out.improvesExpectancy && out.improvesP2R;
  }

#endif // __GSEA_CONFLUENCEENGINE_MQH__
