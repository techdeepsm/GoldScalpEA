//+------------------------------------------------------------------+
//| LiquidityEngine.mqh                                                |
//| Previous-day/week extremes, equal highs/lows, and the generic      |
//| "fresh breach" tests shared by every sweep / breakout / false      |
//| breakout scenario. PDH/PDL/PWH/PWL are read from the prior fully   |
//| CLOSED D1/W1 bar only, so they can never leak the current day's or |
//| week's still-forming range.                                       |
//+------------------------------------------------------------------+
#ifndef __GSEA_LIQUIDITYENGINE_MQH__
#define __GSEA_LIQUIDITYENGINE_MQH__

#include "../Core/Types.mqh"
#include "StructureEngine.mqh"

class CLiquidityEngine
  {
private:
   string   m_symbol;
   string   m_dayKey, m_weekKey;
   double   m_pdh,m_pdl,m_pwh,m_pwl;
   bool     m_hasPdh,m_hasPwh;
   double   m_eqHigh, m_eqLow;
   bool     m_hasEqHigh, m_hasEqLow;
   double   m_eqTolerancePts;

   string DayKey(const datetime t) const
     { MqlDateTime dt; TimeToStruct(t,dt); return StringFormat("%04d.%02d.%02d",dt.year,dt.mon,dt.day); }
   string WeekKey(const datetime t) const
     {
      int weekNum = (int)(t/86400/7);
      return StringFormat("W%d",weekNum);
     }

public:
   void Init(const string symbol,const double eqTolerancePts)
     {
      m_symbol=symbol; m_eqTolerancePts=eqTolerancePts;
      m_dayKey=""; m_weekKey="";
      m_hasPdh=false; m_hasPwh=false;
      m_hasEqHigh=false; m_hasEqLow=false;
      m_pdh=m_pdl=m_pwh=m_pwl=0.0;
      m_eqHigh=m_eqLow=0.0;
     }

   // Call once per closed confirmation-TF bar, chronologically. Uses date-anchored bar lookups
   // (iBarShift against barTime) rather than shift-from-now, so a fast manual replay loop over
   // historical data resolves "yesterday" / "last week" relative to barTime, not relative to the
   // terminal's real clock.
   void OnBar(const datetime barTime)
     {
      string dk=DayKey(barTime);
      if(dk!=m_dayKey)
        {
         m_dayKey=dk;
         int idx = iBarShift(m_symbol,PERIOD_D1,barTime,false);
         if(idx>=0)
           {
            double h = iHigh(m_symbol,PERIOD_D1,idx+1);
            double l = iLow(m_symbol,PERIOD_D1,idx+1);
            if(h>0.0 && l>0.0){ m_pdh=h; m_pdl=l; m_hasPdh=true; }
           }
        }
      string wk=WeekKey(barTime);
      if(wk!=m_weekKey)
        {
         m_weekKey=wk;
         int idx = iBarShift(m_symbol,PERIOD_W1,barTime,false);
         if(idx>=0)
           {
            double h = iHigh(m_symbol,PERIOD_W1,idx+1);
            double l = iLow(m_symbol,PERIOD_W1,idx+1);
            if(h>0.0 && l>0.0){ m_pwh=h; m_pwl=l; m_hasPwh=true; }
           }
        }
     }

   void UpdateEqualLevels(const CStructureEngine &structure,const double point)
     {
      double tol = m_eqTolerancePts*point;
      m_hasEqHigh=false; m_hasEqLow=false;
      int shN = structure.SwingHighCount();
      for(int i=0;i<shN-1 && i<8;i++)
        {
         double a = structure.SwingHighAt(i);
         double b = structure.SwingHighAt(i+1);
         if(MathAbs(a-b)<=tol){ m_eqHigh=MathMax(a,b); m_hasEqHigh=true; break; }
        }
      int slN = structure.SwingLowCount();
      for(int i=0;i<slN-1 && i<8;i++)
        {
         double a = structure.SwingLowAt(i);
         double b = structure.SwingLowAt(i+1);
         if(MathAbs(a-b)<=tol){ m_eqLow=MathMin(a,b); m_hasEqLow=true; break; }
        }
     }

   bool   HasPDH() const { return m_hasPdh; }
   bool   HasPWH() const { return m_hasPwh; }
   double PDH() const { return m_pdh; }
   double PDL() const { return m_pdl; }
   double PWH() const { return m_pwh; }
   double PWL() const { return m_pwl; }
   bool   HasEqualHigh() const { return m_hasEqHigh; }
   bool   HasEqualLow()  const { return m_hasEqLow; }
   double EqualHigh() const { return m_eqHigh; }
   double EqualLow()  const { return m_eqLow; }
  };

//------------------------------------------------------------ stateless fresh-breach tests
// "Fresh" means the previous bar had not already violated the level - this is what turns a
// continuously-true condition into a single edge-triggered detection event.
bool FreshWickBreachUp(const bool levelValid,const double level,const double prevHigh,const double curHigh)
  { return levelValid && curHigh>level && prevHigh<=level; }

bool FreshWickBreachDown(const bool levelValid,const double level,const double prevLow,const double curLow)
  { return levelValid && curLow<level && prevLow>=level; }

bool FreshCloseBreachUp(const bool levelValid,const double level,const double prevClose,const double curClose)
  { return levelValid && curClose>level && prevClose<=level; }

bool FreshCloseBreachDown(const bool levelValid,const double level,const double prevClose,const double curClose)
  { return levelValid && curClose<level && prevClose>=level; }

#endif // __GSEA_LIQUIDITYENGINE_MQH__
