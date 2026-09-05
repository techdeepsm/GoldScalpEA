//+------------------------------------------------------------------+
//| RiskManager.mqh                                                     |
//| All the "should we even consider trading right now" gates, kept     |
//| separate from execution mechanics. Conservative-by-default: every   |
//| trade needs a stop, sizing comes from tick value (never a guess),   |
//| and every limit here is a configurable input, not a hardcoded rule. |
//+------------------------------------------------------------------+
#ifndef __GSEA_RISKMANAGER_MQH__
#define __GSEA_RISKMANAGER_MQH__

#include "../Core/Types.mqh"
#include "../Engines/MarketContext.mqh"

struct RiskConfig
  {
   bool   useRiskPercent;        // true = risk % of equity, false = fixed lot
   double riskPercent;
   double fixedLot;
   double maxDailyLossAmount;    // account currency, positive number
   int    maxTradesPerDay;
   int    maxSimultaneousTrades;
   int    maxTradesPerScenario;
   int    maxConsecutiveLosses;
   int    cooldownMinutesAfterLoss;
   double maxSpreadPoints;
   double maxAccountDrawdownPct; // emergency-disable threshold, % of peak equity
  };

class CRiskManager
  {
private:
   RiskConfig m_cfg;
   string     m_dayKey;
   double     m_dailyPL;
   int        m_dailyTradeCount;
   string     m_scenarioIds[256];
   int        m_scenarioCounts[256];
   int        m_scenarioSlots;
   int        m_consecutiveLosses;
   datetime   m_lastLossTime;
   double     m_equityPeak;
   bool       m_emergencyDisabled;
   string     m_disableReason;

   string DayKey(const datetime t) const
     { MqlDateTime dt; TimeToStruct(t,dt); return StringFormat("%04d.%02d.%02d",dt.year,dt.mon,dt.day); }

   int FindScenarioSlot(const string id)
     {
      for(int i=0;i<m_scenarioSlots;i++) if(m_scenarioIds[i]==id) return i;
      if(m_scenarioSlots<256){ m_scenarioIds[m_scenarioSlots]=id; m_scenarioCounts[m_scenarioSlots]=0; return m_scenarioSlots++; }
      return -1;
     }

public:
   void Init(const RiskConfig &cfg)
     {
      m_cfg=cfg; m_dayKey=""; m_dailyPL=0.0; m_dailyTradeCount=0; m_scenarioSlots=0;
      m_consecutiveLosses=0; m_lastLossTime=0; m_equityPeak=0.0;
      m_emergencyDisabled=false; m_disableReason="";
     }

   void OnTick(const datetime now,const double equity)
     {
      string dk=DayKey(now);
      if(dk!=m_dayKey)
        {
         m_dayKey=dk; m_dailyPL=0.0; m_dailyTradeCount=0; m_scenarioSlots=0;
        }
      if(equity>m_equityPeak) m_equityPeak=equity;
      if(m_equityPeak>0.0 && m_cfg.maxAccountDrawdownPct>0.0)
        {
         double ddPct = (m_equityPeak-equity)/m_equityPeak*100.0;
         if(ddPct>=m_cfg.maxAccountDrawdownPct && !m_emergencyDisabled)
           {
            m_emergencyDisabled=true;
            m_disableReason=StringFormat("Account drawdown %.2f%% >= limit %.2f%%",ddPct,m_cfg.maxAccountDrawdownPct);
           }
        }
     }

   void OnTradeClosed(const string scenarioId,const double profit,const double rMultiple,const datetime closeTime)
     {
      m_dailyPL+=profit;
      if(rMultiple<0.0){ m_consecutiveLosses++; m_lastLossTime=closeTime; }
      else m_consecutiveLosses=0;
     }

   void OnTradeOpened(const string scenarioId)
     {
      m_dailyTradeCount++;
      int slot=FindScenarioSlot(scenarioId);
      if(slot>=0) m_scenarioCounts[slot]++;
     }

   void EmergencyDisable(const string reason) { m_emergencyDisabled=true; m_disableReason=reason; }
   void EmergencyEnable() { m_emergencyDisabled=false; m_disableReason=""; }
   bool IsEmergencyDisabled() const { return m_emergencyDisabled; }
   string DisableReason() const { return m_disableReason; }
   double DailyPL() const { return m_dailyPL; }
   int    ConsecutiveLosses() const { return m_consecutiveLosses; }

   bool CanTrade(const datetime now,const string scenarioId,const double currentSpreadPoints,
                 const int openPositionsCount,string &reasonOut)
     {
      if(m_emergencyDisabled){ reasonOut="emergency disabled: "+m_disableReason; return false; }
      if(m_cfg.maxDailyLossAmount>0.0 && m_dailyPL<=-m_cfg.maxDailyLossAmount)
        { reasonOut="daily loss limit reached"; return false; }
      if(m_cfg.maxTradesPerDay>0 && m_dailyTradeCount>=m_cfg.maxTradesPerDay)
        { reasonOut="max trades per day reached"; return false; }
      if(m_cfg.maxSimultaneousTrades>0 && openPositionsCount>=m_cfg.maxSimultaneousTrades)
        { reasonOut="max simultaneous trades reached"; return false; }
      int slot=FindScenarioSlot(scenarioId);
      if(m_cfg.maxTradesPerScenario>0 && slot>=0 && m_scenarioCounts[slot]>=m_cfg.maxTradesPerScenario)
        { reasonOut="max trades for this scenario reached"; return false; }
      if(m_cfg.maxConsecutiveLosses>0 && m_consecutiveLosses>=m_cfg.maxConsecutiveLosses)
        {
         if(m_cfg.cooldownMinutesAfterLoss>0 && now<m_lastLossTime+m_cfg.cooldownMinutesAfterLoss*60)
           { reasonOut="cooling down after consecutive losses"; return false; }
        }
      if(m_cfg.maxSpreadPoints>0.0 && currentSpreadPoints>m_cfg.maxSpreadPoints)
        { reasonOut="spread too wide"; return false; }
      return true;
     }

   // Sizing derives from tick value, never assumed - see MQL5 skill guidance on stop/lot maths.
   double CalcLotSize(const double balanceOrEquity,const double slDistancePrice,CMarketContext *mkt) const
     {
      if(!m_cfg.useRiskPercent) return mkt.NormalizeVolume(m_cfg.fixedLot);
      double riskAmount = balanceOrEquity*m_cfg.riskPercent/100.0;
      double perLotLoss = mkt.PriceDistanceToMoney(slDistancePrice,1.0);
      if(perLotLoss<=0.0) return mkt.LotMin();
      double lots = riskAmount/perLotLoss;
      return mkt.NormalizeVolume(lots);
     }
  };

#endif // __GSEA_RISKMANAGER_MQH__
