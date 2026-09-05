//+------------------------------------------------------------------+
//| ExecutionEngine.mqh                                                 |
//| Live scenario eligibility, selection among simultaneously-firing    |
//| scenarios, and order placement. Only scenarios that are VALIDATED   |
//| (or promoted to LIVE) and pass every configured threshold are ever  |
//| tradeable - unvalidated research scenarios never reach this file's  |
//| execution path (spec #34/#60/#61).                                  |
//+------------------------------------------------------------------+
#ifndef __GSEA_EXECUTIONENGINE_MQH__
#define __GSEA_EXECUTIONENGINE_MQH__

#include <Trade/Trade.mqh>
#include "../Core/Types.mqh"
#include "../Engines/MarketContext.mqh"
#include "../Analytics/RankingEngine.mqh"

struct LiveEligibilityConfig
  {
   int    minSampleSize;
   int    targetLevelIndex;      // which GSEA_R_MULTIPLES index gates entry and becomes the live TP
   double minProbAtTarget;
   double minExpectancy;
   double minProfitFactor;
   double maxDrawdownR;
   double maxSpreadPoints;
   bool   allowDegraded;         // whether a DEGRADED (previously validated) scenario may still fire
  };

bool IsEligibleForLive(const ScenarioDef &def,const ScenarioStats &stats,const LiveEligibilityConfig &cfg,
                        const double currentSpreadPts,string &reasonOut)
  {
   bool statusOk = (def.status==STATUS_VALIDATED || def.status==STATUS_LIVE ||
                    (cfg.allowDegraded && def.status==STATUS_DEGRADED));
   if(!statusOk){ reasonOut="status "+StatusToString(def.status)+" not eligible"; return false; }
   if(!def.enabled){ reasonOut="scenario disabled"; return false; }
   if(stats.occurrences<cfg.minSampleSize){ reasonOut="sample below minimum"; return false; }
   if(cfg.targetLevelIndex<0 || cfg.targetLevelIndex>=GSEA_R_LEVELS){ reasonOut="bad target level index"; return false; }
   if(stats.probR[cfg.targetLevelIndex]<cfg.minProbAtTarget){ reasonOut="probability below threshold"; return false; }
   if(stats.expectancyR<=cfg.minExpectancy){ reasonOut="expectancy below threshold"; return false; }
   if(stats.profitFactor<cfg.minProfitFactor){ reasonOut="profit factor below threshold"; return false; }
   if(stats.maxDrawdownR>cfg.maxDrawdownR){ reasonOut="drawdown above threshold"; return false; }
   if(currentSpreadPts>cfg.maxSpreadPoints){ reasonOut="spread above threshold"; return false; }
   return true;
  }

// Among everything that fired this bar, keep only eligible occurrences and return the index of
// the one with the highest ranking score. Ties broken by higher sample size (more evidence).
int SelectBestEligible(const ScenarioOccurrence &occs[],const int count,
                        const ScenarioDef &defs[],const ScenarioStats &stats[],
                        const RankingResult &ranks[],const LiveEligibilityConfig &cfg,
                        const double currentSpreadPts,string &reasonLog[])
  {
   int best=-1; double bestScore=-DBL_MAX;
   ArrayResize(reasonLog,count);
   for(int i=0;i<count;i++)
     {
      string reason="";
      bool ok=IsEligibleForLive(defs[i],stats[i],cfg,currentSpreadPts,reason);
      reasonLog[i]=ok? "eligible" : reason;
      if(!ok) continue;
      if(ranks[i].totalScore>bestScore || (ranks[i].totalScore==bestScore && (best<0 || stats[i].occurrences>stats[best].occurrences)))
        {
         bestScore=ranks[i].totalScore;
         best=i;
        }
     }
   return best;
  }

// Places the trade for one occurrence, normalizing price/volume and respecting broker stop
// distance. Returns true and fills outTicket on success; on failure the retcode is logged by
// the caller via trade.ResultRetcodeDescription().
bool ExecuteOccurrence(CTrade &trade,CMarketContext *mkt,const ScenarioOccurrence &occ,
                        const int targetLevelIndex,const double lots,const ulong magic,
                        const string comment,ulong &outTicket)
  {
   outTicket=0;
   double sl = mkt.NormalizePrice(occ.slPrice);
   double tp = mkt.NormalizePrice(occ.tpLevels[targetLevelIndex]);
   double price = (occ.direction==DIR_LONG)? SymbolInfoDouble(mkt.Symbol(),SYMBOL_ASK)
                                            : SymbolInfoDouble(mkt.Symbol(),SYMBOL_BID);
   double minDist = mkt.MinStopDistancePrice();
   if(occ.direction==DIR_LONG)
     {
      if(price-sl<minDist) sl=mkt.NormalizePrice(price-minDist);
      if(tp-price<minDist) tp=mkt.NormalizePrice(price+minDist);
     }
   else
     {
      if(sl-price<minDist) sl=mkt.NormalizePrice(price+minDist);
      if(price-tp<minDist) tp=mkt.NormalizePrice(price-minDist);
     }
   double vol = mkt.NormalizeVolume(lots);
   trade.SetExpertMagicNumber(magic);

   bool sent = (occ.direction==DIR_LONG)? trade.Buy(vol,mkt.Symbol(),0.0,sl,tp,comment)
                                         : trade.Sell(vol,mkt.Symbol(),0.0,sl,tp,comment);
   if(!sent) return false;
   if(trade.ResultRetcode()!=TRADE_RETCODE_DONE && trade.ResultRetcode()!=TRADE_RETCODE_PLACED)
      return false;
   // The opening deal's ticket IS the resulting position's identifier (POSITION_IDENTIFIER /
   // DEAL_POSITION_ID on every later deal against that position) - NOT trade.ResultOrder(), which
   // is a separate order-ticket sequence and will not match up when the position is later closed.
   outTicket=trade.ResultDeal();
   return true;
  }

// Filters open positions by symbol AND magic number - required on netting accounts and whenever
// more than one EA/magic shares the account (skill checklist item).
int CountOpenPositions(const string symbol,const ulong magic)
  {
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=magic) continue;
      count++;
     }
   return count;
  }

#endif // __GSEA_EXECUTIONENGINE_MQH__
