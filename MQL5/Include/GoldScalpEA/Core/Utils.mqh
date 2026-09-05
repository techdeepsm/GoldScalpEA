//+------------------------------------------------------------------+
//| Utils.mqh                                                         |
//| Generic math / string / hashing helpers with no trading logic.    |
//+------------------------------------------------------------------+
#ifndef __GSEA_UTILS_MQH__
#define __GSEA_UTILS_MQH__

#include "Types.mqh"

//------------------------------------------------------------ Wilson score interval
// Robust proportion confidence interval - safe for small samples and p near 0/1.
void WilsonCI(const int successes,const int n,const double z,double &lo,double &hi)
  {
   if(n<=0){ lo=0.0; hi=0.0; return; }
   double p = (double)successes/(double)n;
   double z2 = z*z;
   double denom = 1.0 + z2/n;
   double center = p + z2/(2.0*n);
   double margin = z*MathSqrt((p*(1.0-p)/n) + z2/(4.0*n*n));
   lo = (center-margin)/denom;
   hi = (center+margin)/denom;
   if(lo<0.0) lo=0.0;
   if(hi>1.0) hi=1.0;
  }

//------------------------------------------------------------ basic stats
double ArrayMedian(double &arr[])
  {
   int n=ArraySize(arr);
   if(n==0) return 0.0;
   double tmp[];
   ArrayResize(tmp,n);
   ArrayCopy(tmp,arr);
   ArraySort(tmp);
   if(n%2==1) return tmp[n/2];
   return (tmp[n/2-1]+tmp[n/2])/2.0;
  }

double ArrayMean(double &arr[])
  {
   int n=ArraySize(arr);
   if(n==0) return 0.0;
   double s=0.0;
   for(int i=0;i<n;i++) s+=arr[i];
   return s/n;
  }

//------------------------------------------------------------ deterministic hashing for dynamic scenario IDs
// FNV-1a 32-bit hash over a canonical string. Same definition -> same hash -> same ID, always.
uint FNV1aHash(const string s)
  {
   uint hash = 2166136261;
   int len = StringLen(s);
   for(int i=0;i<len;i++)
     {
      ushort c = StringGetCharacter(s,i);
      hash ^= c;
      hash *= 16777619;
     }
   return hash;
  }

//------------------------------------------------------------ canonical key for a set of component labels + parent
// Sorting components makes the key order-independent, so "A+B" and "B+A" collapse to one scenario.
string CanonicalComponentKey(string &components[],const int count,const string parentId,const ENUM_DIRECTION dir)
  {
   string tmp[];
   ArrayResize(tmp,count);
   for(int i=0;i<count;i++) tmp[i]=components[i];
   // simple insertion sort (arrays here are tiny, <= GSEA_MAX_COMPONENTS)
   for(int i=1;i<count;i++)
     {
      string key=tmp[i];
      int j=i-1;
      while(j>=0 && tmp[j]>key)
        {
         tmp[j+1]=tmp[j];
         j--;
        }
      tmp[j+1]=key;
     }
   string key = parentId + "|" + (string)dir + "|";
   for(int i=0;i<count;i++) key += tmp[i] + ",";
   return key;
  }

string MakeDynamicId(string &components[],const int count,const string parentId,const ENUM_DIRECTION dir)
  {
   string key = CanonicalComponentKey(components,count,parentId,dir);
   uint h = FNV1aHash(key);
   return StringFormat("D%08X",h);
  }

//------------------------------------------------------------ misc
double PointsToPrice(const double points,const double point){ return points*point; }

double PriceDistancePoints(const double a,const double b,const double point)
  {
   if(point<=0.0) return 0.0;
   return MathAbs(a-b)/point;
  }

int DirSign(const ENUM_DIRECTION d){ return (d==DIR_LONG)?1:-1; }

string DirectionToString(const ENUM_DIRECTION d){ return (d==DIR_LONG)?"LONG":"SHORT"; }

string StatusToString(const ENUM_SCENARIO_STATUS s)
  {
   switch(s)
     {
      case STATUS_CANDIDATE:         return "CANDIDATE";
      case STATUS_INSUFFICIENT_DATA: return "INSUFFICIENT_DATA";
      case STATUS_PROMISING:         return "PROMISING";
      case STATUS_VALIDATING:        return "VALIDATING";
      case STATUS_VALIDATED:         return "VALIDATED";
      case STATUS_LIVE:              return "LIVE";
      case STATUS_DEGRADED:          return "DEGRADED";
      case STATUS_REJECTED:          return "REJECTED";
      case STATUS_RETIRED:           return "RETIRED";
     }
   return "UNKNOWN";
  }

string DatasetToString(const ENUM_DATASET d)
  {
   switch(d)
     {
      case DATASET_TRAIN:      return "TRAIN";
      case DATASET_VALIDATION: return "VALIDATION";
      case DATASET_OOS:        return "OOS";
      case DATASET_EXCLUDED:   return "EXCLUDED";
     }
   return "?";
  }

double GSEA_R_MULTIPLES[GSEA_R_LEVELS] = {0.5,1.0,1.5,2.0,2.5,3.0,4.0};

#endif // __GSEA_UTILS_MQH__
