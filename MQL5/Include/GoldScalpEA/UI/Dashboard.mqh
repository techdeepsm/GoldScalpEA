//+------------------------------------------------------------------+
//| Dashboard.mqh                                                       |
//| On-chart panel covering Market / Active Scenario / Statistics /     |
//| Risk (spec #46). Plain OBJ_LABEL text lines on a background panel - |
//| every object is prefixed so Deinit() can clean up completely.       |
//+------------------------------------------------------------------+
#ifndef __GSEA_DASHBOARD_MQH__
#define __GSEA_DASHBOARD_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"

#define GSEA_DASH_PREFIX "GSEA_DASH_"

class CDashboard
  {
private:
   int m_x, m_y, m_lineHeight, m_lineCount;

   void Line(const string key,const string text,const color clr)
     {
      string name=GSEA_DASH_PREFIX+key;
      if(ObjectFind(0,name)<0)
        {
         ObjectCreate(0,name,OBJ_LABEL,0,0,0);
         ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
         ObjectSetInteger(0,name,OBJPROP_XDISTANCE,m_x);
         ObjectSetInteger(0,name,OBJPROP_YDISTANCE,m_y+m_lineCount*m_lineHeight);
         ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9);
         ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
         ObjectSetInteger(0,name,OBJPROP_BACK,false);
         ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
        }
      ObjectSetString(0,name,OBJPROP_TEXT,text);
      ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
      m_lineCount++;
     }

public:
   void Init(const int x=10,const int y=20,const int lineHeight=14)
     { m_x=x; m_y=y; m_lineHeight=lineHeight; m_lineCount=0; }

   void BeginFrame() { m_lineCount=0; }

   void Header(const string text) { Line(StringFormat("H%d",m_lineCount),"== "+text+" ==",clrKhaki); }
   void Row(const string text) { Line(StringFormat("R%d",m_lineCount),text,clrWhiteSmoke); }
   void RowColored(const string text,const color clr) { Line(StringFormat("R%d",m_lineCount),text,clr); }

   void Deinit()
     {
      int total=ObjectsTotal(0,0,OBJ_LABEL);
      for(int i=total-1;i>=0;i--)
        {
         string name=ObjectName(0,i,0,OBJ_LABEL);
         if(StringFind(name,GSEA_DASH_PREFIX)==0) ObjectDelete(0,name);
        }
     }
  };

// One place that assembles the whole panel's content each refresh, so the main EA file just
// hands over the numbers it already computed rather than duplicating layout logic.
void RenderDashboard(CDashboard &dash,
                      const string symbol,const double spreadPts,const ENUM_SESSION session,
                      const ENUM_BIAS htfBias,const ENUM_VOL_REGIME volRegime,const double atr,
                      const bool haveActive,const string activeId,const string activeName,
                      const ENUM_DIRECTION activeDir,const double activeEntry,const double activeSL,const double activeTP,
                      const int sample,const double p1R,const double p2R,const double p3R,
                      const double expectancy,const double profitFactor,
                      const double dailyPL,const double dailyRiskUsedPct,const int openTrades,
                      const double drawdownPct,const int consecutiveLosses,const ENUM_EA_MODE mode)
  {
   dash.BeginFrame();
   dash.Header("GoldScalpEA - "+(string)((mode==MODE_RESEARCH)?"RESEARCH":"LIVE"));
   dash.Header("Market");
   dash.Row(StringFormat("%s  Spread:%.1fpt  Session:%s",symbol,spreadPts,EnumToString(session)));
   dash.Row(StringFormat("HTF Bias:%s  Vol:%s  ATR:%.2f",EnumToString(htfBias),EnumToString(volRegime),atr));
   dash.Header("Active Scenario");
   if(haveActive)
     {
      dash.Row(StringFormat("%s %s [%s]",activeId,activeName,DirectionToString(activeDir)));
      dash.Row(StringFormat("Entry:%.2f  SL:%.2f  TP:%.2f",activeEntry,activeSL,activeTP));
     }
   else dash.Row("(none)");
   dash.Header("Statistics");
   dash.Row(StringFormat("Sample:%d  P(1R):%.1f%%  P(2R):%.1f%%  P(3R):%.1f%%",sample,p1R*100.0,p2R*100.0,p3R*100.0));
   dash.Row(StringFormat("Expectancy:%.2fR  ProfitFactor:%.2f",expectancy,profitFactor));
   dash.Header("Risk");
   dash.Row(StringFormat("Daily P/L:%.2f  Daily Risk Used:%.1f%%  Open Trades:%d",dailyPL,dailyRiskUsedPct,openTrades));
   dash.Row(StringFormat("Drawdown:%.1f%%  Consecutive Losses:%d",drawdownPct,consecutiveLosses));
  }

#endif // __GSEA_DASHBOARD_MQH__
