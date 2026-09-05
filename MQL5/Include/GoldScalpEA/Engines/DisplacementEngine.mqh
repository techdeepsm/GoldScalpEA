//+------------------------------------------------------------------+
//| DisplacementEngine.mqh                                             |
//| Displacement, compression, expansion, exhaustion and large-wick    |
//| rejection - all measured against a rolling baseline of PRIOR bar   |
//| ranges only, so the current bar never inflates its own baseline.   |
//+------------------------------------------------------------------+
#ifndef __GSEA_DISPLACEMENTENGINE_MQH__
#define __GSEA_DISPLACEMENTENGINE_MQH__

#include "../Core/Types.mqh"

#define GSEA_RANGE_RING 64

class CDisplacementEngine
  {
private:
   double m_ring[GSEA_RANGE_RING];
   int    m_count, m_head, m_lookback;
   double m_dispMult, m_bodyRatio;
   double m_compMult, m_expMult;
   double m_wickRatio;
   int    m_lastDir1, m_lastDir2;         // direction of the two previous bars, for exhaustion
   double m_lastBody1, m_lastBody2;

   double RingMean() const
     {
      if(m_count==0) return 0.0;
      double s=0.0;
      int n=MathMin(m_count,m_lookback);
      for(int i=0;i<n;i++)
        {
         int idx=(m_head-1-i+GSEA_RANGE_RING*2)%GSEA_RANGE_RING;
         s+=m_ring[idx];
        }
      return s/n;
     }

public:
   void Configure(const int lookback,const double dispMult,const double bodyRatio,
                  const double compMult,const double expMult,const double wickRatio)
     {
      m_lookback=MathMin(lookback,GSEA_RANGE_RING);
      m_dispMult=dispMult; m_bodyRatio=bodyRatio;
      m_compMult=compMult; m_expMult=expMult; m_wickRatio=wickRatio;
      m_count=0; m_head=0; m_lastDir1=0; m_lastDir2=0; m_lastBody1=0; m_lastBody2=0;
     }

   void OnBar(const double open,const double high,const double low,const double close,
              bool &outDisplacementBull,bool &outDisplacementBear,
              bool &outCompression,bool &outExpansion,bool &outExhaustion,
              bool &outWickRejBull,bool &outWickRejBear)
     {
      outDisplacementBull=false; outDisplacementBear=false;
      outCompression=false; outExpansion=false; outExhaustion=false;
      outWickRejBull=false; outWickRejBear=false;

      double range = high-low;
      double body  = MathAbs(close-open);
      double baseline = RingMean();

      if(m_count>=MathMax(5,m_lookback/2) && baseline>0.0)
        {
         double bodyToRange = (range>0.0)? body/range : 0.0;
         if(close>open && range>=baseline*m_dispMult && bodyToRange>=m_bodyRatio) outDisplacementBull=true;
         if(close<open && range>=baseline*m_dispMult && bodyToRange>=m_bodyRatio) outDisplacementBear=true;
         if(range<=baseline*m_compMult) outCompression=true;
         if(range>=baseline*m_expMult)  outExpansion=true;

         double upperWick = high-MathMax(open,close);
         double lowerWick = MathMin(open,close)-low;
         if(range>0.0)
           {
            if(lowerWick/range>=m_wickRatio && close>=open) outWickRejBull=true;
            if(upperWick/range>=m_wickRatio && close<=open) outWickRejBear=true;
           }

         // 3-candle exhaustion: two prior bars trending the same direction with sizable bodies,
         // followed by a current bar whose body collapses relative to both - a stalling signature.
         if(m_lastDir1!=0 && m_lastDir1==m_lastDir2 && m_lastBody1>0.0 && m_lastBody2>0.0)
           {
            bool priorTrendUp = (m_lastDir1>0);
            bool priorTrendDown = (m_lastDir1<0);
            bool thisBodySmall = (body <= MathMin(m_lastBody1,m_lastBody2)*0.5);
            if((priorTrendUp||priorTrendDown) && thisBodySmall)
               outExhaustion=true;
           }
        }

      m_ring[m_head]=range;
      m_head=(m_head+1)%GSEA_RANGE_RING;
      if(m_count<GSEA_RANGE_RING) m_count++;

      m_lastDir2=m_lastDir1;
      m_lastBody2=m_lastBody1;
      m_lastDir1 = (close>open)? 1 : ((close<open)? -1 : 0);
      m_lastBody1 = body;
     }
  };

#endif // __GSEA_DISPLACEMENTENGINE_MQH__
