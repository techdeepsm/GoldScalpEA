//+------------------------------------------------------------------+
//| SessionEngine.mqh                                                  |
//| Session windows are configured in broker SERVER time (TimeTradeServer|
//| / bar time from CopyRates, which MT5 always expresses in server    |
//| time). MQL5 has no IANA timezone database, so true "timezone-aware"|
//| behaviour is achieved by exposing the broker's UTC offset as an    |
//| input and letting every session boundary be specified relative to |
//| server time; the EA does not guess at DST conventions for you.     |
//+------------------------------------------------------------------+
#ifndef __GSEA_SESSIONENGINE_MQH__
#define __GSEA_SESSIONENGINE_MQH__

#include "../Core/Types.mqh"

struct SessionWindow
  {
   int startHour, startMin;
   int endHour,   endMin;
  };

struct SessionAccumulator
  {
   string   dayKey;      // yyyy.mm.dd anchor of the session currently accumulating
   double   high, low;
   bool     active;
   bool     sealed;       // window finished for this day - value is final and safe to reference
   datetime windowStart;
   datetime windowEnd;
  };

class CSessionEngine
  {
private:
   SessionWindow        m_asian, m_london, m_ny;
   int                  m_orMinutes;              // opening-range length in minutes, per session
   SessionAccumulator   m_asianAcc, m_londonAcc, m_nyAcc;
   SessionAccumulator   m_orAsian, m_orLondon, m_orNy;

   string DayKey(const datetime t) const
     {
      MqlDateTime dt; TimeToStruct(t,dt);
      return StringFormat("%04d.%02d.%02d",dt.year,dt.mon,dt.day);
     }

   bool InWindow(const datetime t,const SessionWindow &w,datetime &winStart,datetime &winEnd) const
     {
      MqlDateTime dt; TimeToStruct(t,dt);
      int minuteOfDay = dt.hour*60+dt.min;
      int startM = w.startHour*60+w.startMin;
      int endM   = w.endHour*60+w.endMin;
      MqlDateTime d0=dt; d0.hour=0; d0.min=0; d0.sec=0;
      datetime dayStart = StructToTime(d0);
      if(startM<=endM)
        {
         winStart = dayStart+startM*60;
         winEnd   = dayStart+endM*60;
         return (minuteOfDay>=startM && minuteOfDay<endM);
        }
      else
        {
         // wraps midnight
         if(minuteOfDay>=startM)
           {
            winStart = dayStart+startM*60;
            winEnd   = dayStart+24*60*60+endM*60;
            return true;
           }
         if(minuteOfDay<endM)
           {
            winStart = dayStart-24*60*60+startM*60;
            winEnd   = dayStart+endM*60;
            return true;
           }
         return false;
        }
     }

   void UpdateAccumulator(SessionAccumulator &acc,const bool inWindow,const datetime winStart,const datetime winEnd,
                           const datetime barTime,const double high,const double low)
     {
      string key = DayKey(winStart);
      if(acc.dayKey!=key)
        {
         acc.dayKey  = key;
         acc.high    = -DBL_MAX;
         acc.low     =  DBL_MAX;
         acc.active  = false;
         acc.sealed  = false;
         acc.windowStart = winStart;
         acc.windowEnd   = winEnd;
        }
      if(inWindow)
        {
         acc.active = true;
         if(high>acc.high) acc.high = high;
         if(low<acc.low)   acc.low  = low;
        }
      else if(acc.active && !acc.sealed && barTime>=winEnd)
        {
         acc.sealed = true;
        }
     }

public:
   void Configure(const SessionWindow &asian,const SessionWindow &london,const SessionWindow &ny,const int orMinutes)
     {
      m_asian=asian; m_london=london; m_ny=ny; m_orMinutes=orMinutes;
      ZeroMemory(m_asianAcc); ZeroMemory(m_londonAcc); ZeroMemory(m_nyAcc);
      ZeroMemory(m_orAsian);  ZeroMemory(m_orLondon);  ZeroMemory(m_orNy);
     }

   // Call once per confirmation-timeframe CLOSED bar, in chronological order.
   void OnBar(const datetime barTime,const double high,const double low)
     {
      datetime ws,we;
      bool inA = InWindow(barTime,m_asian, ws,we); UpdateAccumulator(m_asianAcc, inA,ws,we,barTime,high,low);
      bool inL = InWindow(barTime,m_london,ws,we); UpdateAccumulator(m_londonAcc,inL,ws,we,barTime,high,low);
      bool inN = InWindow(barTime,m_ny,    ws,we); UpdateAccumulator(m_nyAcc,    inN,ws,we,barTime,high,low);

      UpdateOpeningRange(m_orAsian, m_asianAcc, inA, barTime, high, low);
      UpdateOpeningRange(m_orLondon,m_londonAcc,inL, barTime, high, low);
      UpdateOpeningRange(m_orNy,    m_nyAcc,    inN, barTime, high, low);
     }

   void UpdateOpeningRange(SessionAccumulator &orAcc,const SessionAccumulator &sessAcc,const bool inWindow,
                            const datetime barTime,const double high,const double low)
     {
      if(orAcc.dayKey!=sessAcc.dayKey)
        {
         orAcc.dayKey = sessAcc.dayKey;
         orAcc.high = -DBL_MAX; orAcc.low = DBL_MAX;
         orAcc.active=false; orAcc.sealed=false;
         orAcc.windowStart = sessAcc.windowStart;
         orAcc.windowEnd   = sessAcc.windowStart + m_orMinutes*60;
        }
      if(inWindow && barTime<orAcc.windowEnd)
        {
         orAcc.active=true;
         if(high>orAcc.high) orAcc.high=high;
         if(low<orAcc.low)   orAcc.low=low;
        }
      else if(orAcc.active && !orAcc.sealed && barTime>=orAcc.windowEnd)
        {
         orAcc.sealed=true;
        }
     }

   ENUM_SESSION GetSession(const datetime t) const
     {
      datetime ws,we;
      bool inL = InWindow(t,m_london,ws,we);
      bool inN = InWindow(t,m_ny,ws,we);
      bool inA = InWindow(t,m_asian,ws,we);
      if(inL && inN) return SESSION_LONDON_NY_OVERLAP;
      if(inL) return SESSION_LONDON;
      if(inN) return SESSION_NEWYORK;
      if(inA) return SESSION_ASIAN;
      return SESSION_NONE;
     }

   // "Sealed" session extremes are safe to use as a liquidity level - the window that formed them
   // has already fully closed, so referencing them can never leak future information.
   bool   HasAsianRange()  const { return m_asianAcc.sealed || m_asianAcc.active; }
   bool   IsAsianSealed()  const { return m_asianAcc.sealed; }
   double AsianHigh() const { return m_asianAcc.high; }
   double AsianLow()  const { return m_asianAcc.low; }
   bool   HasLondonRange() const { return m_londonAcc.sealed || m_londonAcc.active; }
   bool   IsLondonSealed() const { return m_londonAcc.sealed; }
   double LondonHigh() const { return m_londonAcc.high; }
   double LondonLow()  const { return m_londonAcc.low; }
   bool   HasNYRange() const { return m_nyAcc.sealed || m_nyAcc.active; }
   bool   IsNYSealed() const { return m_nyAcc.sealed; }
   double NYHigh() const { return m_nyAcc.high; }
   double NYLow()  const { return m_nyAcc.low; }

   bool   HasOpeningRange(const ENUM_SESSION s) const
     {
      if(s==SESSION_ASIAN)  return m_orAsian.sealed;
      if(s==SESSION_LONDON) return m_orLondon.sealed;
      if(s==SESSION_NEWYORK)return m_orNy.sealed;
      return false;
     }
   double OpeningRangeHigh(const ENUM_SESSION s) const
     {
      if(s==SESSION_ASIAN)  return m_orAsian.high;
      if(s==SESSION_LONDON) return m_orLondon.high;
      if(s==SESSION_NEWYORK)return m_orNy.high;
      return 0.0;
     }
   double OpeningRangeLow(const ENUM_SESSION s) const
     {
      if(s==SESSION_ASIAN)  return m_orAsian.low;
      if(s==SESSION_LONDON) return m_orLondon.low;
      if(s==SESSION_NEWYORK)return m_orNy.low;
      return 0.0;
     }
  };

#endif // __GSEA_SESSIONENGINE_MQH__
