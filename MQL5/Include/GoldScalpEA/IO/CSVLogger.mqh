//+------------------------------------------------------------------+
//| CSVLogger.mqh                                                       |
//| Every export contains enough columns to reproduce and re-analyze    |
//| the result outside MT5 (spec #44). Written with FILE_COMMON so the  |
//| files land in one predictable shared folder                        |
//| (<Windows user>\AppData\Roaming\MetaQuotes\Terminal\Common\Files\)  |
//| regardless of whether this runs in the Strategy Tester (which       |
//| otherwise sandboxes file I/O per test agent), a live/demo chart, or |
//| which terminal instance - instead of a per-agent Tester subfolder.  |
//+------------------------------------------------------------------+
#ifndef __GSEA_CSVLOGGER_MQH__
#define __GSEA_CSVLOGGER_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Analytics/ConfluenceEngine.mqh"
#include "../Analytics/ValidationEngine.mqh"

string B(const bool v) { return v? "1":"0"; }

bool CSV_WriteOccurrences(const string filename,const ScenarioOccurrence &occs[],const int count)
  {
   int h=FileOpen(filename,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE) return false;
   FileWrite(h,"occurrence_id","scenario_id","detect_time","entry_time","direction","entry_price","sl_price",
             "tp_0_5R","tp_1R","tp_1_5R","tp_2R","tp_2_5R","tp_3R","tp_4R","r_distance",
             "session","htf_bias","vol_regime","atr_at_entry","spread_at_entry","hour","day_of_week","dataset",
             "outcome_resolved","hit_0_5R","hit_1R","hit_1_5R","hit_2R","hit_2_5R","hit_3R","hit_4R",
             "bars_to_stop","bars_to_first_target","mfe_r","mae_r","exit_r","stopped_out");
   for(int i=0;i<count;i++)
     {
      ScenarioOccurrence o=occs[i];
      FileWrite(h,o.occurrenceId,o.scenarioId,TimeToString(o.detectTime,TIME_DATE|TIME_MINUTES),
                TimeToString(o.entryTime,TIME_DATE|TIME_MINUTES),DirectionToString(o.direction),
                DoubleToString(o.entryPrice,5),DoubleToString(o.slPrice,5),
                DoubleToString(o.tpLevels[0],5),DoubleToString(o.tpLevels[1],5),DoubleToString(o.tpLevels[2],5),
                DoubleToString(o.tpLevels[3],5),DoubleToString(o.tpLevels[4],5),DoubleToString(o.tpLevels[5],5),
                DoubleToString(o.tpLevels[6],5),DoubleToString(o.rDistance,5),
                EnumToString(o.session),EnumToString(o.htfBias),EnumToString(o.volRegime),
                DoubleToString(o.atrAtEntry,5),DoubleToString(o.spreadAtEntry,1),o.hour,o.dayOfWeek,
                DatasetToString(o.dataset),B(o.outcomeResolved),
                B(o.hitLevel[0]),B(o.hitLevel[1]),B(o.hitLevel[2]),B(o.hitLevel[3]),B(o.hitLevel[4]),B(o.hitLevel[5]),B(o.hitLevel[6]),
                o.barsToStop,o.barsToFirstTarget,DoubleToString(o.mfeR,3),DoubleToString(o.maeR,3),
                DoubleToString(o.exitR,3),B(o.stoppedOut));
     }
   FileClose(h);
   return true;
  }

bool CSV_WriteStatsRow(const int h,const ScenarioStats &s)
  {
   return (FileWrite(h,s.scenarioId,DatasetToString(s.dataset),s.occurrences,s.wins,s.losses,
             DoubleToString(s.winRate*100.0,2),
             DoubleToString(s.probR[0]*100.0,2),DoubleToString(s.probR[1]*100.0,2),DoubleToString(s.probR[2]*100.0,2),
             DoubleToString(s.probR[3]*100.0,2),DoubleToString(s.probR[4]*100.0,2),DoubleToString(s.probR[5]*100.0,2),
             DoubleToString(s.probR[6]*100.0,2),
             DoubleToString(s.avgWinR,3),DoubleToString(s.avgLossR,3),DoubleToString(s.avgR,3),DoubleToString(s.medianR,3),
             DoubleToString(s.expectancyR,3),DoubleToString(s.profitFactor,3),DoubleToString(s.maxDrawdownR,3),
             s.maxWinStreak,s.maxLossStreak,DoubleToString(s.avgMFE_R,3),DoubleToString(s.avgMAE_R,3),
             DoubleToString(s.avgBarsToTarget,1),StatusToString(s.status),B(s.sufficientSample))>0);
  }

bool CSV_WriteSummary(const string filename,const ScenarioStats &stats[],const int count)
  {
   int h=FileOpen(filename,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE) return false;
   // expectancy_r/profit_factor here model running each trade to whichever R level is reached
   // first (the stop, or the far end) - NOT a single fixed take-profit. For the number that
   // corresponds to a real order with its TP fixed at one R level, see
   // <prefix>scenario_probability.csv's expectancy_r_if_tp_here / profit_factor_if_tp_here columns.
   FileWrite(h,"scenario_id","dataset","occurrences","wins","losses","win_rate_pct",
             "p_0_5R_pct","p_1R_pct","p_1_5R_pct","p_2R_pct","p_2_5R_pct","p_3R_pct","p_4R_pct",
             "avg_win_r","avg_loss_r","avg_r_run_to_completion","median_r","expectancy_r_run_to_completion",
             "profit_factor_run_to_completion","max_drawdown_r",
             "max_win_streak","max_loss_streak","avg_mfe_r","avg_mae_r","avg_bars_to_target","status","sufficient_sample");
   for(int i=0;i<count;i++) CSV_WriteStatsRow(h,stats[i]);
   FileClose(h);
   return true;
  }

bool CSV_WriteProbability(const string filename,const ScenarioStats &stats[],const int count)
  {
   int h=FileOpen(filename,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE) return false;
   FileWrite(h,"scenario_id","dataset","r_multiple","sample","probability_pct","ci_low_pct","ci_high_pct",
             "expectancy_r_if_tp_here","profit_factor_if_tp_here");
   for(int i=0;i<count;i++)
      for(int k=0;k<GSEA_R_LEVELS;k++)
         FileWrite(h,stats[i].scenarioId,DatasetToString(stats[i].dataset),DoubleToString(GSEA_R_MULTIPLES[k],1),
                   stats[i].occurrences,DoubleToString(stats[i].probR[k]*100.0,2),
                   DoubleToString(stats[i].probR_ciLo[k]*100.0,2),DoubleToString(stats[i].probR_ciHi[k]*100.0,2),
                   DoubleToString(stats[i].expectancyAtLevel[k],3),DoubleToString(stats[i].profitFactorAtLevel[k],3));
   FileClose(h);
   return true;
  }

bool CSV_WriteConfluence(const string filename,const ConfluenceComparison &rows[],const int count)
  {
   int h=FileOpen(filename,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE) return false;
   FileWrite(h,"parent_id","child_id","parent_sample","child_sample","parent_p1R_pct","child_p1R_pct",
             "parent_p2R_pct","child_p2R_pct","parent_expectancy_r","child_expectancy_r",
             "parent_pf","child_pf","child_sample_sufficient","improves_p2R","improves_expectancy",
             "improves_pf","overall_improved");
   for(int i=0;i<count;i++)
     {
      ConfluenceComparison c=rows[i];
      FileWrite(h,c.parentId,c.childId,c.parentSample,c.childSample,
                DoubleToString(c.parentP1R*100.0,2),DoubleToString(c.childP1R*100.0,2),
                DoubleToString(c.parentP2R*100.0,2),DoubleToString(c.childP2R*100.0,2),
                DoubleToString(c.parentExpectancy,3),DoubleToString(c.childExpectancy,3),
                DoubleToString(c.parentPF,3),DoubleToString(c.childPF,3),
                B(c.childSampleSufficient),B(c.improvesP2R),B(c.improvesExpectancy),
                B(c.improvesProfitFactor),B(c.overallImproved));
     }
   FileClose(h);
   return true;
  }

bool CSV_WriteValidation(const string filename,const string &scenarioIds[],const ENUM_SCENARIO_STATUS &statuses[],
                          const ScenarioStats &trainStats[],const ScenarioStats &validStats[],
                          const ScenarioStats &oosStats[],const double &walkForwardPassRates[],const int count)
  {
   int h=FileOpen(filename,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE) return false;
   FileWrite(h,"scenario_id","status","train_sample","train_expectancy_r","valid_sample","valid_expectancy_r",
             "oos_sample","oos_expectancy_r","walk_forward_pass_rate_pct");
   for(int i=0;i<count;i++)
      FileWrite(h,scenarioIds[i],StatusToString(statuses[i]),
                trainStats[i].occurrences,DoubleToString(trainStats[i].expectancyR,3),
                validStats[i].occurrences,DoubleToString(validStats[i].expectancyR,3),
                oosStats[i].occurrences,DoubleToString(oosStats[i].expectancyR,3),
                DoubleToString(walkForwardPassRates[i]*100.0,1));
   FileClose(h);
   return true;
  }

bool CSV_WriteTradeLog(const string filename,const ExecutedTrade &trades[],const int count)
  {
   int h=FileOpen(filename,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE) return false;
   FileWrite(h,"ticket","scenario_id","open_time","close_time","direction","open_price","close_price",
             "sl_price","tp_price","lots","profit","r_multiple");
   for(int i=0;i<count;i++)
     {
      ExecutedTrade t=trades[i];
      FileWrite(h,(long)t.ticket,t.scenarioId,TimeToString(t.openTime,TIME_DATE|TIME_MINUTES),
                TimeToString(t.closeTime,TIME_DATE|TIME_MINUTES),DirectionToString(t.direction),
                DoubleToString(t.openPrice,5),DoubleToString(t.closePrice,5),DoubleToString(t.slPrice,5),
                DoubleToString(t.tpPrice,5),DoubleToString(t.lots,2),DoubleToString(t.profit,2),
                DoubleToString(t.rMultiple,3));
     }
   FileClose(h);
   return true;
  }

#endif // __GSEA_CSVLOGGER_MQH__
