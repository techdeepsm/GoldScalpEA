//+------------------------------------------------------------------+
//| ValidationEngine.mqh                                                |
//| Train/Validation/OOS separation, rolling walk-forward testing, and  |
//| the scenario status lifecycle. Candidate generation and parameter   |
//| choices elsewhere in this project only ever look at TRAIN and       |
//| VALIDATION stats; OOS numbers are computed here but are consumed    |
//| ONLY by EvaluateLifecycleOOS() as a final, one-way gate - nothing   |
//| feeds an OOS result back into scenario construction (spec #30).     |
//+------------------------------------------------------------------+
#ifndef __GSEA_VALIDATIONENGINE_MQH__
#define __GSEA_VALIDATIONENGINE_MQH__

#include "../Core/Types.mqh"
#include "ProbabilityEngine.mqh"

struct DatasetRanges
  {
   datetime trainStart, trainEnd;
   datetime validStart, validEnd;
   datetime oosStart,   oosEnd;
  };

// Single O(n) pass labelling every occurrence with which dataset window its entryTime falls in.
// Anything outside all three configured windows is EXCLUDED and never enters any statistic.
void ClassifyDatasets(ScenarioOccurrence &occs[],const int total,const DatasetRanges &r)
  {
   for(int i=0;i<total;i++)
     {
      datetime t=occs[i].entryTime;
      if(t>=r.trainStart && t<r.trainEnd) occs[i].dataset=DATASET_TRAIN;
      else if(t>=r.validStart && t<r.validEnd) occs[i].dataset=DATASET_VALIDATION;
      else if(t>=r.oosStart && t<r.oosEnd) occs[i].dataset=DATASET_OOS;
      else occs[i].dataset=DATASET_EXCLUDED;
     }
  }

// Same math as ComputeScenarioStats but filtered by an explicit [start,end) time range instead of
// a dataset label - used for walk-forward windows, which slice time far more finely than the
// three fixed train/validation/OOS windows.
void ComputeScenarioStatsRange(const ScenarioOccurrence &occs[],const int total,const string scenarioId,
                                const datetime rangeStart,const datetime rangeEnd,
                                const int minSampleSize,const double wilsonZ,ScenarioStats &out)
  {
   ZeroMemory(out);
   out.scenarioId=scenarioId;
   double exitRs[]; ArrayResize(exitRs,0,256);
   int levelHits[GSEA_R_LEVELS]; ArrayInitialize(levelHits,0);
   double sumMfe=0.0,sumMae=0.0; int mfeCount=0;
   double sumBarsToTarget=0.0; int barsToTargetCount=0;
   int wins=0,losses=0,n=0;

   for(int i=0;i<total;i++)
     {
      if(occs[i].scenarioId!=scenarioId) continue;
      if(occs[i].entryTime<rangeStart || occs[i].entryTime>=rangeEnd) continue;
      if(!occs[i].outcomeResolved) continue;
      n++;
      int m=ArraySize(exitRs); ArrayResize(exitRs,m+1,256); exitRs[m]=occs[i].exitR;
      for(int k=0;k<GSEA_R_LEVELS;k++) if(occs[i].hitLevel[k]) levelHits[k]++;
      bool isWin=occs[i].hitLevel[GSEA_WIN_LEVEL_INDEX];
      if(isWin) wins++; else losses++;
      sumMfe+=occs[i].mfeR; sumMae+=occs[i].maeR; mfeCount++;
      if(occs[i].barsToFirstTarget>=0){ sumBarsToTarget+=occs[i].barsToFirstTarget; barsToTargetCount++; }
     }

   out.occurrences=n; out.wins=wins; out.losses=losses;
   out.winRate=(n>0)? (double)wins/n : 0.0;
   for(int k=0;k<GSEA_R_LEVELS;k++)
     {
      out.probR[k]=(n>0)? (double)levelHits[k]/n : 0.0;
      double lo,hiv; WilsonCI(levelHits[k],n,wilsonZ,lo,hiv);
      out.probR_ciLo[k]=lo; out.probR_ciHi[k]=hiv;
     }
   ComputePerLevelStats(levelHits,n,out.expectancyAtLevel,out.profitFactorAtLevel);
   double sumWin=0.0,sumLoss=0.0; int cw=0,cl=0;
   for(int i=0;i<ArraySize(exitRs);i++){ if(exitRs[i]>0.0){ sumWin+=exitRs[i]; cw++; } else { sumLoss+=exitRs[i]; cl++; } }
   out.avgWinR=(cw>0)? sumWin/cw : 0.0;
   out.avgLossR=(cl>0)? sumLoss/cl : 0.0;
   out.avgR=ArrayMean(exitRs);
   out.medianR=ArrayMedian(exitRs);
   out.expectancyR=out.avgR;
   out.profitFactor=(sumLoss!=0.0)? (sumWin/MathAbs(sumLoss)) : ((sumWin>0.0)? GSEA_MAX_PF : 0.0);
   out.avgMFE_R=(mfeCount>0)? sumMfe/mfeCount : 0.0;
   out.avgMAE_R=(mfeCount>0)? sumMae/mfeCount : 0.0;
   out.avgBarsToTarget=(barsToTargetCount>0)? sumBarsToTarget/barsToTargetCount : 0.0;
   out.sufficientSample=(n>=minSampleSize);
   out.status = out.sufficientSample? STATUS_CANDIDATE : STATUS_INSUFFICIENT_DATA;
  }

datetime AddMonths(const datetime t,const int months)
  {
   MqlDateTime dt; TimeToStruct(t,dt);
   int totalMonths=(dt.mon-1)+months;
   int addYears=(int)MathFloor((double)totalMonths/12.0);
   int newMon=totalMonths-addYears*12;
   dt.year+=addYears; dt.mon=newMon+1;
   return StructToTime(dt);
  }

struct WalkForwardWindowResult
  {
   datetime testStart, testEnd;
   int      sample;
   double   expectancy;
   double   profitFactor;
   bool     passed;
  };

// Rolling walk-forward: an initial training block, then successive out-of-training test windows
// that each roll forward, re-using everything seen so far as "train" for the next window. A
// scenario is only "robust" (spec #31) if it repeatedly passes across many such unseen windows.
int RunWalkForward(const ScenarioOccurrence &occs[],const int total,const string scenarioId,
                    const datetime overallStart,const datetime overallEnd,
                    const int trainMonths,const int testMonths,
                    const int minSampleSize,const double wilsonZ,
                    WalkForwardWindowResult &results[])
  {
   ArrayResize(results,0);
   datetime cursor=AddMonths(overallStart,trainMonths);
   int guard=0;
   while(cursor<overallEnd && guard<60)
     {
      datetime testStart=cursor;
      datetime testEnd=AddMonths(testStart,testMonths);
      if(testEnd>overallEnd) testEnd=overallEnd;

      ScenarioStats st;
      ComputeScenarioStatsRange(occs,total,scenarioId,testStart,testEnd,minSampleSize,wilsonZ,st);

      WalkForwardWindowResult r;
      r.testStart=testStart; r.testEnd=testEnd;
      r.sample=st.occurrences; r.expectancy=st.expectancyR; r.profitFactor=st.profitFactor;
      r.passed = st.sufficientSample && st.expectancyR>0.0;

      int n=ArraySize(results); ArrayResize(results,n+1); results[n]=r;

      cursor=testEnd;
      guard++;
     }
   return ArraySize(results);
  }

double WalkForwardPassRate(const WalkForwardWindowResult &results[],const int count)
  {
   if(count==0) return 0.0;
   int passed=0;
   for(int i=0;i<count;i++) if(results[i].passed) passed++;
   return (double)passed/count;
  }

//------------------------------------------------------------ lifecycle thresholds & transitions
struct LifecycleThresholds
  {
   int    minSampleSize;
   double minExpectancy;              // e.g. 0.0
   double minProfitFactor;            // e.g. 1.0
   double validationRetentionRatio;   // validation expectancy must retain >= this fraction of train's
   double minWalkForwardPassRate;     // e.g. 0.5
   double degradeExpectancyRatio;     // rolling live expectancy below (validated * ratio) -> DEGRADED
   double retireExpectancy;           // rolling live expectancy at/below this -> RETIRED
  };

// TRAIN and VALIDATION are the only inputs here - this function is what candidate generation and
// parameter selection are allowed to react to (spec #30). OOS is deliberately a separate call.
//
// Gates on expectancyAtLevel[targetLevelIndex]/profitFactorAtLevel[targetLevelIndex], NOT the
// aggregate expectancyR/profitFactor fields - the aggregate ones model running a trade to
// whichever R level is reached first (stop or the far end), which is not what a live order with
// its take-profit fixed at targetLevelIndex will actually realize. targetLevelIndex should match
// whatever InpLiveTargetLevelIndex live execution is configured to use, so "VALIDATED" means
// "validated at the R level this EA will actually trade."
ENUM_SCENARIO_STATUS EvaluateLifecycleTrainValidation(const ScenarioStats &train,const ScenarioStats &validation,
                                                       const int targetLevelIndex,const LifecycleThresholds &th)
  {
   if(targetLevelIndex<0 || targetLevelIndex>=GSEA_R_LEVELS) return STATUS_REJECTED;
   if(!train.sufficientSample) return STATUS_INSUFFICIENT_DATA;
   double trainExp=train.expectancyAtLevel[targetLevelIndex], trainPF=train.profitFactorAtLevel[targetLevelIndex];
   if(trainExp<=th.minExpectancy || trainPF<th.minProfitFactor) return STATUS_REJECTED;
   if(!validation.sufficientSample) return STATUS_PROMISING;
   double validExp=validation.expectancyAtLevel[targetLevelIndex];
   if(validExp<=th.minExpectancy) return STATUS_REJECTED;
   if(validExp < trainExp*th.validationRetentionRatio) return STATUS_REJECTED;
   return STATUS_VALIDATING;
  }

// Final, one-way OOS gate. Only ever called once a scenario has reached VALIDATING; its result
// (VALIDATED or REJECTED) is terminal for this evaluation cycle and must not be used to go back
// and tweak the scenario's definition.
ENUM_SCENARIO_STATUS EvaluateLifecycleOOS(const ENUM_SCENARIO_STATUS currentStatus,const ScenarioStats &oos,
                                           const int targetLevelIndex,const double walkForwardPassRate,
                                           const LifecycleThresholds &th)
  {
   if(currentStatus!=STATUS_VALIDATING) return currentStatus;
   if(targetLevelIndex<0 || targetLevelIndex>=GSEA_R_LEVELS) return STATUS_REJECTED;
   if(!oos.sufficientSample) return STATUS_VALIDATING;
   if(walkForwardPassRate<th.minWalkForwardPassRate) return STATUS_REJECTED;
   if(oos.expectancyAtLevel[targetLevelIndex]<=th.minExpectancy || oos.profitFactorAtLevel[targetLevelIndex]<th.minProfitFactor)
      return STATUS_REJECTED;
   return STATUS_VALIDATED;
  }

// Spec #37: monitor a LIVE scenario's rolling performance against its validated baseline. Never
// retires on a handful of losses - both checks require the rolling sample to already be sizeable.
// rollingLive.expectancyR here is expected to be built directly from real ExecutedTrade.rMultiple
// values (a real trade always closes at its actual SL or actual TP), which is already an honest
// single-fixed-TP number - so it's compared against validatedBaseline's PER-LEVEL expectancy
// (same targetLevelIndex the live trades were actually opened with), not the aggregate field.
bool CheckDecay(const ScenarioStats &validatedBaseline,const ScenarioStats &rollingLive,
                 const int targetLevelIndex,const LifecycleThresholds &th,bool &shouldDegrade,bool &shouldRetire)
  {
   shouldDegrade=false; shouldRetire=false;
   if(targetLevelIndex<0 || targetLevelIndex>=GSEA_R_LEVELS) return false;
   if(!rollingLive.sufficientSample) return false;
   double baselineExp=validatedBaseline.expectancyAtLevel[targetLevelIndex];
   if(rollingLive.expectancyR < baselineExp*th.degradeExpectancyRatio) shouldDegrade=true;
   if(rollingLive.expectancyR <= th.retireExpectancy) shouldRetire=true;
   return true;
  }

#endif // __GSEA_VALIDATIONENGINE_MQH__
