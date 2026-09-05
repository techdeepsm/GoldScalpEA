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

// targetLevelIndex should match InpLiveTargetLevelIndex, so "does this improve the parent" is
// judged at the R level this EA would actually trade, using expectancyAtLevel/profitFactorAtLevel
// rather than the aggregate "run to whichever level is reached first" fields.
void CompareConfluence(const ScenarioStats &parentStats,const ScenarioStats &childStats,
                        const int minSampleSize,const int targetLevelIndex,ConfluenceComparison &out)
  {
   ZeroMemory(out);
   int lvl = (targetLevelIndex>=0 && targetLevelIndex<GSEA_R_LEVELS)? targetLevelIndex : GSEA_P2R_INDEX;
   out.parentId=parentStats.scenarioId; out.childId=childStats.scenarioId;
   out.parentSample=parentStats.occurrences; out.childSample=childStats.occurrences;
   out.parentP1R=parentStats.probR[GSEA_WIN_LEVEL_INDEX]; out.childP1R=childStats.probR[GSEA_WIN_LEVEL_INDEX];
   out.parentP2R=parentStats.probR[GSEA_P2R_INDEX];       out.childP2R=childStats.probR[GSEA_P2R_INDEX];
   out.parentExpectancy=parentStats.expectancyAtLevel[lvl]; out.childExpectancy=childStats.expectancyAtLevel[lvl];
   out.parentPF=parentStats.profitFactorAtLevel[lvl]; out.childPF=childStats.profitFactorAtLevel[lvl];

   out.childSampleSufficient = (childStats.occurrences>=minSampleSize);
   out.improvesP2R          = out.childSampleSufficient && (childStats.probR[GSEA_P2R_INDEX] > parentStats.probR[GSEA_P2R_INDEX]);
   out.improvesExpectancy   = out.childSampleSufficient && (out.childExpectancy > out.parentExpectancy);
   out.improvesProfitFactor = out.childSampleSufficient && (out.childPF > out.parentPF);
   out.overallImproved      = out.improvesExpectancy && out.improvesP2R;
  }

#endif // __GSEA_CONFLUENCEENGINE_MQH__
