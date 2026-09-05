//+------------------------------------------------------------------+
//| VolatilityEngine.mqh                                               |
//| ATR, ATR regime (percentile vs its own recent history), ATR        |
//| expansion/compression, and a session-anchored VWAP with deviation  |
//| bands. All state is updated incrementally, one closed bar at a     |
//| time - no full-history rescans on every tick.                      |
//+------------------------------------------------------------------+
#ifndef __GSEA_VOLATILITYENGINE_MQH__
#define __GSEA_VOLATILITYENGINE_MQH__

#include "../Core/Types.mqh"

#define GSEA_ATR_HIST_LEN 500

class CVolatilityEngine
  {
private:
   int      m_atrHandle;
   int      m_atrPeriod;
   double   m_atrRing[GSEA_ATR_HIST_LEN];
   int      m_atrRingCount, m_atrRingHead;
   double   m_lowPct, m_highPct;      // regime percentile thresholds, e.g. 0.33 / 0.66
   double   m_expansionMult, m_compressionMult;

   // session-anchored VWAP accumulators
   string   m_vwapDayKey;
   double   m_sumPV, m_sumV, m_sumPPV;   // sum(price*vol), sum(vol), sum(price*price*vol) for stddev
   double   m_vwapDevMult;

   string DayKey(const datetime t) const
     {
      MqlDateTime dt; TimeToStruct(t,dt);
      return StringFormat("%04d.%02d.%02d",dt.year,dt.mon,dt.day);
     }

public:
   bool Init(const string symbol,const ENUM_TIMEFRAMES tf,const int atrPeriod,
             const double lowPct,const double highPct,
             const double expansionMult,const double compressionMult,const double vwapDevMult)
     {
      m_atrPeriod=atrPeriod; m_lowPct=lowPct; m_highPct=highPct;
      m_expansionMult=expansionMult; m_compressionMult=compressionMult;
      m_vwapDevMult=vwapDevMult;
      m_atrRingCount=0; m_atrRingHead=0;
      m_vwapDayKey=""; m_sumPV=0.0; m_sumV=0.0; m_sumPPV=0.0;
      m_atrHandle = iATR(symbol,tf,atrPeriod);
      return (m_atrHandle!=INVALID_HANDLE);
     }

   void Deinit()
     {
      if(m_atrHandle!=INVALID_HANDLE) IndicatorRelease(m_atrHandle);
     }

   // Date-anchored lookup (NOT shift-from-now): this is what makes the same call correct both
   // for live incremental use and for a fast manual replay loop over historical bars, since ATR
   // is purely backward-looking and querying by the bar's own open time can never see the future.
   bool GetAtrAt(const datetime barTime,double &atrOut)
     {
      double buf[];
      if(CopyBuffer(m_atrHandle,0,barTime,1,buf)<1) return false;
      atrOut=buf[0];
      return true;
     }

   void PushAtrSample(const double atr)
     {
      m_atrRing[m_atrRingHead]=atr;
      m_atrRingHead=(m_atrRingHead+1)%GSEA_ATR_HIST_LEN;
      if(m_atrRingCount<GSEA_ATR_HIST_LEN) m_atrRingCount++;
     }

   double AtrRingMean() const
     {
      if(m_atrRingCount==0) return 0.0;
      double s=0.0;
      for(int i=0;i<m_atrRingCount;i++) s+=m_atrRing[i];
      return s/m_atrRingCount;
     }

   ENUM_VOL_REGIME ClassifyRegime(const double atr) const
     {
      if(m_atrRingCount<20) return VOL_MEDIUM; // not enough history yet, avoid false certainty
      double sorted[GSEA_ATR_HIST_LEN];
      for(int i=0;i<m_atrRingCount;i++) sorted[i]=m_atrRing[i];
      // simple insertion sort - buffer is small and this runs once per bar, not per tick
      for(int i=1;i<m_atrRingCount;i++)
        {
         double key=sorted[i]; int j=i-1;
         while(j>=0 && sorted[j]>key){ sorted[j+1]=sorted[j]; j--; }
         sorted[j+1]=key;
        }
      int lowIdx  = (int)MathFloor(m_lowPct*(m_atrRingCount-1));
      int highIdx = (int)MathFloor(m_highPct*(m_atrRingCount-1));
      double lowThresh  = sorted[lowIdx];
      double highThresh = sorted[highIdx];
      if(atr<=lowThresh)  return VOL_LOW;
      if(atr>=highThresh) return VOL_HIGH;
      return VOL_MEDIUM;
     }

   bool IsExpansion(const double atr) const
     {
      double m=AtrRingMean();
      return (m>0.0 && atr>=m*m_expansionMult);
     }
   bool IsCompression(const double atr) const
     {
      double m=AtrRingMean();
      return (m>0.0 && atr<=m*m_compressionMult);
     }

   // VWAP: resets at the start of each new trading day (server-time calendar day).
   void UpdateVWAP(const datetime barTime,const double high,const double low,const double close,const double volume)
     {
      string key=DayKey(barTime);
      if(key!=m_vwapDayKey)
        {
         m_vwapDayKey=key; m_sumPV=0.0; m_sumV=0.0; m_sumPPV=0.0;
        }
      double typical=(high+low+close)/3.0;
      double v = MathMax(volume,1.0);
      m_sumPV  += typical*v;
      m_sumV   += v;
      m_sumPPV += typical*typical*v;
     }

   bool GetVWAP(double &vwap,double &upperBand,double &lowerBand) const
     {
      if(m_sumV<=0.0) return false;
      vwap = m_sumPV/m_sumV;
      double variance = MathMax(0.0,(m_sumPPV/m_sumV) - vwap*vwap);
      double sd = MathSqrt(variance);
      upperBand = vwap + m_vwapDevMult*sd;
      lowerBand = vwap - m_vwapDevMult*sd;
      return true;
     }
  };

#endif // __GSEA_VOLATILITYENGINE_MQH__
