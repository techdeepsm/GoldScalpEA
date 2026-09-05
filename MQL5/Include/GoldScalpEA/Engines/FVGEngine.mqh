//+------------------------------------------------------------------+
//| FVGEngine.mqh                                                      |
//| 3-bar Fair Value Gap detection, midpoint, retracement, full fill   |
//| and rejection tracking. A gap at bar i only ever compares bar i    |
//| against bar i-2 - both are closed by the time bar i closes, so     |
//| nothing here needs a future bar to fire.                           |
//+------------------------------------------------------------------+
#ifndef __GSEA_FVGENGINE_MQH__
#define __GSEA_FVGENGINE_MQH__

#include "../Core/Types.mqh"

class CFVGEngine
  {
private:
   double m_h2,m_l2,m_h1,m_l1;    // high/low of bar i-2 and i-1 (rolling)
   int    m_barsSeen;
   double m_minSizePts, m_point, m_retracePct;

   bool   m_bullActive; double m_bullTop,m_bullBottom,m_bullMid;
   bool   m_bearActive; double m_bearTop,m_bearBottom,m_bearMid;

public:
   void Configure(const double minSizePoints,const double point,const double retracePct)
     {
      m_minSizePts=minSizePoints; m_point=point; m_retracePct=retracePct;
      m_barsSeen=0; m_bullActive=false; m_bearActive=false;
      m_h2=m_l2=m_h1=m_l1=0.0;
      m_bullTop=m_bullBottom=m_bullMid=0.0;
      m_bearTop=m_bearBottom=m_bearMid=0.0;
     }

   void OnBar(const double high,const double low,const double close,
              bool &outFvgBull,bool &outFvgBear,
              bool &outFvgBullRetrace,bool &outFvgBearRetrace,
              bool &outFvgBullFullFill,bool &outFvgBearFullFill)
     {
      outFvgBull=false; outFvgBear=false;
      outFvgBullRetrace=false; outFvgBearRetrace=false;
      outFvgBullFullFill=false; outFvgBearFullFill=false;

      if(m_barsSeen>=2)
        {
         double minGap = m_minSizePts*m_point;
         // bullish FVG: bar i's low sits above bar i-2's high
         if(low - m_h2 >= minGap)
           {
            m_bullTop=low; m_bullBottom=m_h2; m_bullMid=(m_bullTop+m_bullBottom)/2.0;
            m_bullActive=true;
            outFvgBull=true;
           }
         // bearish FVG: bar i's high sits below bar i-2's low
         if(m_l2 - high >= minGap)
           {
            m_bearTop=m_l2; m_bearBottom=high; m_bearMid=(m_bearTop+m_bearBottom)/2.0;
            m_bearActive=true;
            outFvgBear=true;
           }
        }

      if(m_bullActive)
        {
         double retraceLevel = m_bullTop - (m_bullTop-m_bullBottom)*m_retracePct;
         if(low<=retraceLevel && close>m_bullBottom) outFvgBullRetrace=true;
         if(close<m_bullBottom){ outFvgBullFullFill=true; m_bullActive=false; }
        }
      if(m_bearActive)
        {
         double retraceLevel = m_bearBottom + (m_bearTop-m_bearBottom)*m_retracePct;
         if(high>=retraceLevel && close<m_bearTop) outFvgBearRetrace=true;
         if(close>m_bearTop){ outFvgBearFullFill=true; m_bearActive=false; }
        }

      m_h2=m_h1; m_l2=m_l1;
      m_h1=high; m_l1=low;
      if(m_barsSeen<2) m_barsSeen++;
     }

   bool   HasBullFVG() const { return m_bullActive; }
   bool   HasBearFVG() const { return m_bearActive; }
   double BullTop() const { return m_bullTop; }
   double BullBottom() const { return m_bullBottom; }
   double BullMid() const { return m_bullMid; }
   double BearTop() const { return m_bearTop; }
   double BearBottom() const { return m_bearBottom; }
   double BearMid() const { return m_bearMid; }
  };

#endif // __GSEA_FVGENGINE_MQH__
