//+------------------------------------------------------------------+
//| FeatureSnapshot.mqh                                                |
//| Wires every engine together into one per-bar FeatureSnapshot.      |
//| Ordering inside BuildSnapshot() is deliberate: structure runs      |
//| before liquidity's equal-level scan (which reads structure's       |
//| swings), and HTF/context bias is advanced from a monotonic cursor  |
//| over independently-timestamped H1/M15 bars strictly OLDER than the |
//| confirmation bar being built - never equal to or newer than it.    |
//+------------------------------------------------------------------+
#ifndef __GSEA_FEATURESNAPSHOT_MQH__
#define __GSEA_FEATURESNAPSHOT_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Engines/MarketContext.mqh"
#include "../Engines/SessionEngine.mqh"
#include "../Engines/StructureEngine.mqh"
#include "../Engines/LiquidityEngine.mqh"
#include "../Engines/VolatilityEngine.mqh"
#include "../Engines/DisplacementEngine.mqh"
#include "../Engines/FVGEngine.mqh"

struct FeatureBuilderConfig
  {
   int    swingLeft, swingRight;
   double retestTolerancePts;
   double eqLevelTolerancePts;
   int    atrPeriod;
   double atrLowPct, atrHighPct;
   double atrExpansionMult, atrCompressionMult;
   double vwapDevMult;
   int    dispLookback;
   double dispMult, dispBodyRatio, dispCompMult, dispExpMult, dispWickRatio;
   double fvgMinSizePts, fvgRetracePct;
   double extremeZonePct;         // fraction of a reference range considered "extreme" for mean reversion
   int    orMinutes;
   SessionWindow asianWin, londonWin, nyWin;
  };

class CFeatureSnapshotBuilder
  {
private:
   string             m_symbol;
   ENUM_TIMEFRAMES    m_tfHTF, m_tfContext, m_tfConfirm;
   FeatureBuilderConfig m_cfg;

   CMarketContext     m_market;
   CSessionEngine     m_session;
   CLiquidityEngine   m_liquidity;
   CStructureEngine   m_structConfirm;
   CStructureEngine   m_structHTF;
   CStructureEngine   m_structContext;
   CVolatilityEngine  m_volConfirm;
   CDisplacementEngine m_disp;
   CFVGEngine         m_fvg;

   MqlRates           m_htfBars[];
   MqlRates           m_ctxBars[];
   int                m_htfCursor, m_ctxCursor;

   ENUM_BIAS          m_cachedHtfBias;
   ENUM_TREND_REGIME  m_cachedCtxTrend;

   bool               m_havePrev;
   double             m_prevOpen,m_prevHigh,m_prevLow,m_prevClose;

   ENUM_BIAS BiasFromTrend(const int trend) const
     {
      if(trend>0) return BIAS_BULLISH;
      if(trend<0) return BIAS_BEARISH;
      return BIAS_NEUTRAL;
     }

   // Advance the HTF/context structure engines using any buffered bars whose CLOSE time (open+period)
   // is at or before mBarTime. Comparing close time, not open time, is what prevents an H1 bar that
   // opened before but has not yet finished forming from leaking its (unknown) close into bias.
   void AdvanceHTF(const datetime mBarTime)
     {
      bool b1,b2,b3,b4,b5,b6,b7,b8;
      int htfPeriodSec = PeriodSeconds(m_tfHTF);
      int ctxPeriodSec = PeriodSeconds(m_tfContext);
      int n = ArraySize(m_htfBars);
      while(m_htfCursor<n && (m_htfBars[m_htfCursor].time+htfPeriodSec) <= mBarTime)
        {
         m_structHTF.OnBar(m_htfBars[m_htfCursor].time,m_htfBars[m_htfCursor].high,
                            m_htfBars[m_htfCursor].low,m_htfBars[m_htfCursor].close,
                            b1,b2,b3,b4,b5,b6,b7,b8);
         m_cachedHtfBias = BiasFromTrend(m_structHTF.Trend());
         m_htfCursor++;
        }
      int m = ArraySize(m_ctxBars);
      while(m_ctxCursor<m && (m_ctxBars[m_ctxCursor].time+ctxPeriodSec) <= mBarTime)
        {
         m_structContext.OnBar(m_ctxBars[m_ctxCursor].time,m_ctxBars[m_ctxCursor].high,
                                m_ctxBars[m_ctxCursor].low,m_ctxBars[m_ctxCursor].close,
                                b1,b2,b3,b4,b5,b6,b7,b8);
         m_cachedCtxTrend = m_structContext.TrendRegime();
         m_ctxCursor++;
        }
     }

   void ResolveLevel(const ENUM_LEVEL_TYPE level,const datetime t,bool &isHighType,bool &valid,double &value) const
     {
      isHighType=false; valid=false; value=0.0;
      switch(level)
        {
         case LEVEL_ASIAN_HIGH: isHighType=true;  valid=m_session.IsAsianSealed();  value=m_session.AsianHigh(); break;
         case LEVEL_ASIAN_LOW:  isHighType=false; valid=m_session.IsAsianSealed();  value=m_session.AsianLow();  break;
         case LEVEL_LONDON_HIGH:isHighType=true;  valid=m_session.IsLondonSealed(); value=m_session.LondonHigh();break;
         case LEVEL_LONDON_LOW: isHighType=false; valid=m_session.IsLondonSealed(); value=m_session.LondonLow(); break;
         case LEVEL_NY_HIGH:    isHighType=true;  valid=m_session.IsNYSealed();     value=m_session.NYHigh();    break;
         case LEVEL_NY_LOW:     isHighType=false; valid=m_session.IsNYSealed();     value=m_session.NYLow();     break;
         case LEVEL_PDH: isHighType=true;  valid=m_liquidity.HasPDH(); value=m_liquidity.PDH(); break;
         case LEVEL_PDL: isHighType=false; valid=m_liquidity.HasPDH(); value=m_liquidity.PDL(); break;
         case LEVEL_PWH: isHighType=true;  valid=m_liquidity.HasPWH(); value=m_liquidity.PWH(); break;
         case LEVEL_PWL: isHighType=false; valid=m_liquidity.HasPWH(); value=m_liquidity.PWL(); break;
         case LEVEL_EQUAL_HIGH: isHighType=true;  valid=m_liquidity.HasEqualHigh(); value=m_liquidity.EqualHigh(); break;
         case LEVEL_EQUAL_LOW:  isHighType=false; valid=m_liquidity.HasEqualLow();  value=m_liquidity.EqualLow();  break;
         case LEVEL_OR_HIGH:
         case LEVEL_OR_LOW:
           {
            ENUM_SESSION s = SESSION_NONE;
            if(m_session.GetSession(t)==SESSION_NEWYORK || m_session.GetSession(t)==SESSION_LONDON_NY_OVERLAP)
               s = SESSION_NEWYORK;
            else if(m_session.GetSession(t)==SESSION_LONDON)
               s = SESSION_LONDON;
            else if(m_session.GetSession(t)==SESSION_ASIAN)
               s = SESSION_ASIAN;
            if(s!=SESSION_NONE && m_session.HasOpeningRange(s))
              {
               valid=true;
               isHighType = (level==LEVEL_OR_HIGH);
               value = isHighType? m_session.OpeningRangeHigh(s) : m_session.OpeningRangeLow(s);
              }
            break;
           }
         default: break;
        }
     }

public:
   bool Init(const string symbol,const ENUM_TIMEFRAMES tfHTF,const ENUM_TIMEFRAMES tfContext,
             const ENUM_TIMEFRAMES tfConfirm,const FeatureBuilderConfig &cfg)
     {
      m_symbol=symbol; m_tfHTF=tfHTF; m_tfContext=tfContext; m_tfConfirm=tfConfirm; m_cfg=cfg;
      if(!m_market.Init(symbol)) return false;
      m_session.Configure(cfg.asianWin,cfg.londonWin,cfg.nyWin,cfg.orMinutes);
      m_liquidity.Init(symbol,cfg.eqLevelTolerancePts);
      m_structConfirm.Configure(cfg.swingLeft,cfg.swingRight,cfg.retestTolerancePts,m_market.Point());
      m_structHTF.Configure(cfg.swingLeft,cfg.swingRight,cfg.retestTolerancePts,m_market.Point());
      m_structContext.Configure(cfg.swingLeft,cfg.swingRight,cfg.retestTolerancePts,m_market.Point());
      if(!m_volConfirm.Init(symbol,tfConfirm,cfg.atrPeriod,cfg.atrLowPct,cfg.atrHighPct,
                             cfg.atrExpansionMult,cfg.atrCompressionMult,cfg.vwapDevMult))
         return false;
      m_disp.Configure(cfg.dispLookback,cfg.dispMult,cfg.dispBodyRatio,cfg.dispCompMult,cfg.dispExpMult,cfg.dispWickRatio);
      m_fvg.Configure(cfg.fvgMinSizePts,m_market.Point(),cfg.fvgRetracePct);
      m_htfCursor=0; m_ctxCursor=0;
      m_cachedHtfBias=BIAS_NEUTRAL; m_cachedCtxTrend=REGIME_RANGING;
      m_havePrev=false;
      return true;
     }

   void Deinit() { m_volConfirm.Deinit(); }

   // Bulk-load H1/context history for a fixed date range (research mode single load).
   bool LoadHistoricalContext(const datetime start,const datetime stop)
     {
      int n1 = CopyRates(m_symbol,m_tfHTF,start,stop,m_htfBars);
      int n2 = CopyRates(m_symbol,m_tfContext,start,stop,m_ctxBars);
      m_htfCursor=0; m_ctxCursor=0;
      return (n1>0 && n2>0);
     }

   // Live mode: call once whenever a new HTF/context bar has just closed, appending it.
   void AppendHTFBar(const MqlRates &r)
     {
      int n=ArraySize(m_htfBars);
      ArrayResize(m_htfBars,n+1,256);
      m_htfBars[n]=r;
     }
   void AppendContextBar(const MqlRates &r)
     {
      int n=ArraySize(m_ctxBars);
      ArrayResize(m_ctxBars,n+1,256);
      m_ctxBars[n]=r;
     }

   CMarketContext*    Market()    { return GetPointer(m_market); }
   CSessionEngine*    Sessions()  { return GetPointer(m_session); }
   CLiquidityEngine*  Liquidity() { return GetPointer(m_liquidity); }
   CStructureEngine*  StructureConfirm() { return GetPointer(m_structConfirm); }
   CVolatilityEngine* VolatilityConfirm() { return GetPointer(m_volConfirm); }
   CFVGEngine*        FVG() { return GetPointer(m_fvg); }

   // Build the snapshot for one closed confirmation-TF bar. Must be called in chronological order.
   bool BuildSnapshot(const MqlRates &bar,const double spreadPtsOverride,FeatureSnapshot &out)
     {
      ZeroMemory(out);
      datetime t=bar.time;
      out.time=t; out.open=bar.open; out.high=bar.high; out.low=bar.low; out.close=bar.close;

      m_session.OnBar(t,bar.high,bar.low);
      m_liquidity.OnBar(t);
      AdvanceHTF(t);

      double atr=0.0;
      if(!m_volConfirm.GetAtrAt(t,atr)) atr=0.0;
      m_volConfirm.PushAtrSample(atr);
      out.atr=atr;
      out.volRegime = m_volConfirm.ClassifyRegime(atr);
      out.atrExtremeExpansion = m_volConfirm.IsExpansion(atr);
      m_volConfirm.UpdateVWAP(t,bar.high,bar.low,bar.close,(double)bar.tick_volume);
      double vwap=0,upper=0,lower=0;
      if(m_volConfirm.GetVWAP(vwap,upper,lower))
        {
         out.vwap=vwap; out.vwapUpperBand=upper; out.vwapLowerBand=lower;
         out.vwapPos = (bar.close>vwap)? VWAP_ABOVE : ((bar.close<vwap)? VWAP_BELOW : VWAP_AT);
         out.vwapDistPts = MathAbs(bar.close-vwap)/m_market.Point();
         out.vwapDevUpperTouch = (bar.high>=upper);
         out.vwapDevLowerTouch = (bar.low<=lower);
        }

      out.htfBias = m_cachedHtfBias;
      out.trendRegime = m_cachedCtxTrend;
      out.session = m_session.GetSession(t);
      MqlDateTime dts; TimeToStruct(t,dts);
      out.hour = dts.hour; out.dayOfWeek = dts.day_of_week;
      out.spreadPts = spreadPtsOverride;

      bool bosBull,bosBear,chochBull,chochBear,higherLow,lowerHigh,retestBull,retestBear;
      m_structConfirm.OnBar(t,bar.high,bar.low,bar.close,bosBull,bosBear,chochBull,chochBear,
                             higherLow,lowerHigh,retestBull,retestBear);
      out.bosBull=bosBull; out.bosBear=bosBear; out.chochBull=chochBull; out.chochBear=chochBear;
      out.higherLow=higherLow; out.lowerHigh=lowerHigh;
      out.structureRetestBull=retestBull; out.structureRetestBear=retestBear;

      m_liquidity.UpdateEqualLevels(m_structConfirm,m_market.Point());
      out.hasEqualHigh=m_liquidity.HasEqualHigh(); out.equalHigh=m_liquidity.EqualHigh();
      out.hasEqualLow=m_liquidity.HasEqualLow();   out.equalLow=m_liquidity.EqualLow();

      out.asianHigh=m_session.AsianHigh(); out.asianLow=m_session.AsianLow();
      out.pdh=m_liquidity.PDH(); out.pdl=m_liquidity.PDL();
      out.pwh=m_liquidity.PWH(); out.pwl=m_liquidity.PWL();
      out.londonHigh=m_session.LondonHigh(); out.londonLow=m_session.LondonLow();
      out.nyHigh=m_session.NYHigh(); out.nyLow=m_session.NYLow();

      ENUM_SESSION curSess=out.session;
      ENUM_SESSION orSess = (curSess==SESSION_NEWYORK||curSess==SESSION_LONDON_NY_OVERLAP)?SESSION_NEWYORK:
                            (curSess==SESSION_LONDON)?SESSION_LONDON:
                            (curSess==SESSION_ASIAN)?SESSION_ASIAN:SESSION_NONE;
      if(orSess!=SESSION_NONE && m_session.HasOpeningRange(orSess))
        {
         out.hasOR=true; out.orHigh=m_session.OpeningRangeHigh(orSess); out.orLow=m_session.OpeningRangeLow(orSess);
        }

      bool dBull,dBear,comp,exp,exh,wrBull,wrBear;
      m_disp.OnBar(bar.open,bar.high,bar.low,bar.close,dBull,dBear,comp,exp,exh,wrBull,wrBear);
      out.displacementBull=dBull; out.displacementBear=dBear;
      out.compression=comp; out.expansion=exp; out.exhaustion=exh;
      out.largeWickRejectionBull=wrBull; out.largeWickRejectionBear=wrBear;

      bool fBull,fBear,fBullR,fBearR,fBullF,fBearF;
      m_fvg.OnBar(bar.high,bar.low,bar.close,fBull,fBear,fBullR,fBearR,fBullF,fBearF);
      out.fvgBull=fBull; out.fvgBear=fBear;
      out.fvgBullRetracement=fBullR; out.fvgBearRetracement=fBearR;
      out.fvgBullFullFill=fBullF; out.fvgBearFullFill=fBearF;
      if(m_fvg.HasBullFVG()){ out.lastFvgBullTop=m_fvg.BullTop(); out.lastFvgBullBottom=m_fvg.BullBottom(); out.lastFvgBullMid=m_fvg.BullMid(); }
      if(m_fvg.HasBearFVG()){ out.lastFvgBearTop=m_fvg.BearTop(); out.lastFvgBearBottom=m_fvg.BearBottom(); out.lastFvgBearMid=m_fvg.BearMid(); }

      if(m_session.HasAsianRange() && m_session.AsianHigh()>m_session.AsianLow())
        {
         double rng=m_session.AsianHigh()-m_session.AsianLow();
         out.rangeExtremeHighAsian = (bar.close >= m_session.AsianHigh()-rng*m_cfg.extremeZonePct);
         out.rangeExtremeLowAsian  = (bar.close <= m_session.AsianLow()+rng*m_cfg.extremeZonePct);
        }
      if(m_liquidity.HasPDH() && m_liquidity.PDH()>m_liquidity.PDL())
        {
         double rng=m_liquidity.PDH()-m_liquidity.PDL();
         out.rangeExtremeHighPDay = (bar.close >= m_liquidity.PDH()-rng*m_cfg.extremeZonePct);
         out.rangeExtremeLowPDay  = (bar.close <= m_liquidity.PDL()+rng*m_cfg.extremeZonePct);
        }

      if(m_havePrev)
        {
         for(int li=0; li<=(int)LEVEL_OR_LOW; li++)
           {
            bool isHighType,valid; double value;
            ResolveLevel((ENUM_LEVEL_TYPE)li,t,isHighType,valid,value);
            if(!valid) continue;
            if(isHighType)
              {
               out.sweptHighLevel[li]        = FreshWickBreachUp(valid,value,m_prevHigh,bar.high);
               out.breakoutUpLevel[li]       = FreshCloseBreachUp(valid,value,m_prevClose,bar.close);
              }
            else
              {
               out.sweptLowLevel[li]         = FreshWickBreachDown(valid,value,m_prevLow,bar.low);
               out.breakoutDownLevel[li]     = FreshCloseBreachDown(valid,value,m_prevClose,bar.close);
              }
           }
        }

      m_prevOpen=bar.open; m_prevHigh=bar.high; m_prevLow=bar.low; m_prevClose=bar.close;
      m_havePrev=true;
      return true;
     }
  };

#endif // __GSEA_FEATURESNAPSHOT_MQH__
