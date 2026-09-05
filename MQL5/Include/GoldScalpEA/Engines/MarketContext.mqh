//+------------------------------------------------------------------+
//| MarketContext.mqh                                                  |
//| Broker/symbol normalization. Nothing in here assumes XAUUSD's      |
//| point size, digits or contract spec on any particular broker.      |
//+------------------------------------------------------------------+
#ifndef __GSEA_MARKETCONTEXT_MQH__
#define __GSEA_MARKETCONTEXT_MQH__

#include "../Core/Types.mqh"

class CMarketContext
  {
private:
   string   m_symbol;
   int      m_digits;
   double   m_point;
   double   m_tickSize;
   double   m_tickValue;
   double   m_lotStep;
   double   m_lotMin;
   double   m_lotMax;
   double   m_stopLevelPts;
   double   m_freezeLevelPts;
   double   m_contractSize;

public:
   bool Init(const string symbol)
     {
      m_symbol = symbol;
      if(!SymbolSelect(m_symbol,true))
         return false;
      m_digits        = (int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS);
      m_point         = SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      m_tickSize      = SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE);
      m_tickValue     = SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_VALUE);
      m_lotStep       = SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP);
      m_lotMin        = SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN);
      m_lotMax        = SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MAX);
      m_stopLevelPts  = (double)SymbolInfoInteger(m_symbol,SYMBOL_TRADE_STOPS_LEVEL);
      m_freezeLevelPts= (double)SymbolInfoInteger(m_symbol,SYMBOL_TRADE_FREEZE_LEVEL);
      m_contractSize  = SymbolInfoDouble(m_symbol,SYMBOL_TRADE_CONTRACT_SIZE);
      if(m_point<=0.0 || m_tickSize<=0.0)
         return false;
      return true;
     }

   string Symbol() const { return m_symbol; }
   int    Digits() const { return m_digits; }
   double Point()  const { return m_point; }
   double TickSize() const { return m_tickSize; }
   double TickValue() const { return m_tickValue; }
   double LotStep() const { return m_lotStep; }
   double LotMin()  const { return m_lotMin; }
   double LotMax()  const { return m_lotMax; }
   double StopLevelPoints()   const { return m_stopLevelPts; }
   double FreezeLevelPoints() const { return m_freezeLevelPts; }
   double ContractSize() const { return m_contractSize; }

   double NormalizePrice(const double price) const
     {
      if(m_tickSize<=0.0) return NormalizeDouble(price,m_digits);
      double steps = MathRound(price/m_tickSize);
      return NormalizeDouble(steps*m_tickSize,m_digits);
     }

   double NormalizeVolume(const double volume) const
     {
      double v = volume;
      if(m_lotStep>0.0)
         v = MathRound(v/m_lotStep)*m_lotStep;
      v = MathMax(m_lotMin,MathMin(m_lotMax,v));
      return NormalizeDouble(v,2);
     }

   double CurrentSpreadPoints() const
     {
      double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
      double ask=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
      if(m_point<=0.0) return 0.0;
      return (ask-bid)/m_point;
     }

   double PointsToPrice(const double points) const { return points*m_point; }
   double PriceToPoints(const double price)  const { return (m_point>0.0)? price/m_point : 0.0; }

   // Value in account currency of a given price distance for a given lot size.
   double PriceDistanceToMoney(const double priceDistance,const double lots) const
     {
      if(m_tickSize<=0.0) return 0.0;
      double ticks = priceDistance/m_tickSize;
      return ticks*m_tickValue*lots;
     }

   // Minimum safe stop distance in price terms, respecting broker stop/freeze levels.
   double MinStopDistancePrice() const
     {
      double lvl = MathMax(m_stopLevelPts,m_freezeLevelPts);
      return lvl*m_point;
     }
  };

#endif // __GSEA_MARKETCONTEXT_MQH__
