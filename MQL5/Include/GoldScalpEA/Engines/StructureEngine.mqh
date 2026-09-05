//+------------------------------------------------------------------+
//| StructureEngine.mqh                                                |
//| Swing points, BOS, CHOCH, HH/HL/LH/LL and structure retest.        |
//| A swing point at bar i is only confirmed once 'right' bars have    |
//| closed after it - this lag is what makes swing detection safe      |
//| against look-ahead bias: nothing about bar i's swing status is     |
//| known until bar i+right has closed.                                |
//+------------------------------------------------------------------+
#ifndef __GSEA_STRUCTUREENGINE_MQH__
#define __GSEA_STRUCTUREENGINE_MQH__

#include "../Core/Types.mqh"

struct SwingPoint
  {
   datetime time;
   double   price;
   bool     broken;     // true once price has closed through it (used up for BOS/CHOCH)
  };

#define GSEA_SWING_BUFFER 64

class CStructureEngine
  {
private:
   int    m_left, m_right;
   double m_retestTolerancePts;
   double m_point;

   // ring buffers of confirmed swings, newest at the end
   SwingPoint m_swingHighs[GSEA_SWING_BUFFER];
   SwingPoint m_swingLows[GSEA_SWING_BUFFER];
   int        m_shCount, m_slCount;

   // raw bar history needed to test "is bar i a fractal swing" once i+right bars have closed
   double   m_h[]; double m_l[]; datetime m_t[];
   int      m_barsSeen;

   int      m_trend;              // 1 = up, -1 = down, 0 = undefined
   double   m_lastBrokenLevel;    // price of the swing most recently broken by BOS/CHOCH
   int      m_lastBrokenDir;      // 1 = broken upward (bullish break), -1 = broken downward
   bool     m_haveBrokenLevel;

   void PushSwingHigh(const datetime t,const double p)
     {
      if(m_shCount<GSEA_SWING_BUFFER)
        {
         m_swingHighs[m_shCount].time=t; m_swingHighs[m_shCount].price=p; m_swingHighs[m_shCount].broken=false;
         m_shCount++;
        }
      else
        {
         for(int i=1;i<GSEA_SWING_BUFFER;i++) m_swingHighs[i-1]=m_swingHighs[i];
         m_swingHighs[GSEA_SWING_BUFFER-1].time=t; m_swingHighs[GSEA_SWING_BUFFER-1].price=p; m_swingHighs[GSEA_SWING_BUFFER-1].broken=false;
        }
     }
   void PushSwingLow(const datetime t,const double p)
     {
      if(m_slCount<GSEA_SWING_BUFFER)
        {
         m_swingLows[m_slCount].time=t; m_swingLows[m_slCount].price=p; m_swingLows[m_slCount].broken=false;
         m_slCount++;
        }
      else
        {
         for(int i=1;i<GSEA_SWING_BUFFER;i++) m_swingLows[i-1]=m_swingLows[i];
         m_swingLows[GSEA_SWING_BUFFER-1].time=t; m_swingLows[GSEA_SWING_BUFFER-1].price=p; m_swingLows[GSEA_SWING_BUFFER-1].broken=false;
        }
     }

public:
   void Configure(const int left,const int right,const double retestTolerancePts,const double point)
     {
      m_left=left; m_right=right; m_retestTolerancePts=retestTolerancePts; m_point=point;
      m_shCount=0; m_slCount=0; m_barsSeen=0; m_trend=0;
      m_haveBrokenLevel=false; m_lastBrokenLevel=0.0; m_lastBrokenDir=0;
      ArrayResize(m_h,0); ArrayResize(m_l,0); ArrayResize(m_t,0);
     }

   bool HasSufficientHistory() const { return m_barsSeen > m_left+m_right; }

   // Feed one closed bar. Outputs booleans that apply to THIS bar only (edge-triggered), since a
   // caller assembling a FeatureSnapshot wants "did this happen on this bar", not a persistent state.
   void OnBar(const datetime t,const double high,const double low,const double close,
              bool &outBosBull,bool &outBosBear,bool &outChochBull,bool &outChochBear,
              bool &outHigherLow,bool &outLowerHigh,
              bool &outRetestBull,bool &outRetestBear)
     {
      outBosBull=false; outBosBear=false; outChochBull=false; outChochBear=false;
      outHigherLow=false; outLowerHigh=false; outRetestBull=false; outRetestBear=false;

      int n = ArraySize(m_h);
      ArrayResize(m_h,n+1,4096); ArrayResize(m_l,n+1,4096); ArrayResize(m_t,n+1,4096);
      m_h[n]=high; m_l[n]=low; m_t[n]=t;
      m_barsSeen++;

      // a candidate fractal at index (n-right) can now be confirmed, since bars up to n exist
      int cand = n-m_right;
      if(cand>=m_left)
        {
         bool isHigh=true, isLow=true;
         for(int k=1;k<=m_left;k++){ if(m_h[cand-k]>=m_h[cand]) isHigh=false; if(m_l[cand-k]<=m_l[cand]) isLow=false; }
         for(int k=1;k<=m_right;k++){ if(m_h[cand+k]>=m_h[cand]) isHigh=false; if(m_l[cand+k]<=m_l[cand]) isLow=false; }
         if(isHigh)
           {
            PushSwingHigh(m_t[cand],m_h[cand]);
           }
         if(isLow)
           {
            PushSwingLow(m_t[cand],m_l[cand]);
            if(m_slCount>=2)
              {
               double prevLow = m_swingLows[m_slCount-2].price;
               if(m_swingLows[m_slCount-1].price>prevLow) outHigherLow=true;
              }
           }
         if(isHigh && m_shCount>=2)
           {
            double prevHigh = m_swingHighs[m_shCount-2].price;
            if(m_swingHighs[m_shCount-1].price<prevHigh) outLowerHigh=true;
           }
        }

      // BOS / CHOCH: does this bar's CLOSE break the most recent unbroken swing high/low?
      for(int i=m_shCount-1;i>=0;i--)
        {
         if(!m_swingHighs[i].broken && close>m_swingHighs[i].price)
           {
            m_swingHighs[i].broken=true;
            bool isChoch = (m_trend==-1);
            if(isChoch) outChochBull=true; else outBosBull=true;
            m_trend=1;
            m_lastBrokenLevel=m_swingHighs[i].price; m_lastBrokenDir=1; m_haveBrokenLevel=true;
            break; // only the nearest unbroken level triggers the event
           }
        }
      for(int i=m_slCount-1;i>=0;i--)
        {
         if(!m_swingLows[i].broken && close<m_swingLows[i].price)
           {
            m_swingLows[i].broken=true;
            bool isChoch = (m_trend==1);
            if(isChoch) outChochBear=true; else outBosBear=true;
            m_trend=-1;
            m_lastBrokenLevel=m_swingLows[i].price; m_lastBrokenDir=-1; m_haveBrokenLevel=true;
            break;
           }
        }

      // Structure retest: price returns to the last broken level after a break, without closing back through it.
      if(m_haveBrokenLevel)
        {
         double tolPrice = m_retestTolerancePts*m_point;
         if(m_lastBrokenDir==1 && low<=m_lastBrokenLevel+tolPrice && close>m_lastBrokenLevel)
            outRetestBull=true;
         if(m_lastBrokenDir==-1 && high>=m_lastBrokenLevel-tolPrice && close<m_lastBrokenLevel)
            outRetestBear=true;
        }
     }

   int Trend() const { return m_trend; } // 1 up, -1 down, 0 undefined
   ENUM_TREND_REGIME TrendRegime() const { return (m_trend!=0)? REGIME_TRENDING : REGIME_RANGING; }

   bool GetLatestSwingHigh(double &price,datetime &time) const
     { if(m_shCount==0) return false; price=m_swingHighs[m_shCount-1].price; time=m_swingHighs[m_shCount-1].time; return true; }
   bool GetLatestSwingLow(double &price,datetime &time) const
     { if(m_slCount==0) return false; price=m_swingLows[m_slCount-1].price; time=m_swingLows[m_slCount-1].time; return true; }

   int SwingHighCount() const { return m_shCount; }
   int SwingLowCount()  const { return m_slCount; }
   double SwingHighAt(const int idxFromNewest) const
     { int i=m_shCount-1-idxFromNewest; return (i>=0 && i<m_shCount)? m_swingHighs[i].price : 0.0; }
   double SwingLowAt(const int idxFromNewest) const
     { int i=m_slCount-1-idxFromNewest; return (i>=0 && i<m_slCount)? m_swingLows[i].price : 0.0; }
   datetime SwingHighTimeAt(const int idxFromNewest) const
     { int i=m_shCount-1-idxFromNewest; return (i>=0 && i<m_shCount)? m_swingHighs[i].time : 0; }
   datetime SwingLowTimeAt(const int idxFromNewest) const
     { int i=m_slCount-1-idxFromNewest; return (i>=0 && i<m_slCount)? m_swingLows[i].time : 0; }
  };

#endif // __GSEA_STRUCTUREENGINE_MQH__
