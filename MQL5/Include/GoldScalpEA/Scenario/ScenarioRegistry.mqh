//+------------------------------------------------------------------+
//| ScenarioRegistry.mqh                                               |
//| Central store of every scenario definition - preloaded S001-S082   |
//| plus anything the dynamic generator adds later. One flat array,    |
//| looked up by ID; parent/child relationships are just a string      |
//| field, so the tree is queryable without a separate data structure. |
//+------------------------------------------------------------------+
#ifndef __GSEA_SCENARIOREGISTRY_MQH__
#define __GSEA_SCENARIOREGISTRY_MQH__

#include "../Core/Types.mqh"

#define GSEA_MAX_SCENARIOS 4096

class CScenarioRegistry
  {
private:
   ScenarioDef m_defs[GSEA_MAX_SCENARIOS];
   int         m_count;

public:
   void Init() { m_count=0; }

   int Count() const { return m_count; }

   bool Add(const ScenarioDef &d)
     {
      if(m_count>=GSEA_MAX_SCENARIOS) return false;
      if(FindIndex(d.id)>=0) return false; // duplicate ID guard - deterministic IDs should never collide silently
      m_defs[m_count]=d;
      m_count++;
      return true;
     }

   int FindIndex(const string id) const
     {
      for(int i=0;i<m_count;i++) if(m_defs[i].id==id) return i;
      return -1;
     }

   bool Get(const string id,ScenarioDef &out) const
     {
      int i=FindIndex(id);
      if(i<0) return false;
      out=m_defs[i];
      return true;
     }

   bool GetAt(const int idx,ScenarioDef &out) const
     {
      if(idx<0 || idx>=m_count) return false;
      out=m_defs[idx];
      return true;
     }

   bool SetStatus(const string id,const ENUM_SCENARIO_STATUS status)
     {
      int i=FindIndex(id);
      if(i<0) return false;
      m_defs[i].status=status;
      return true;
     }

   bool SetEnabled(const string id,const bool enabled)
     {
      int i=FindIndex(id);
      if(i<0) return false;
      m_defs[i].enabled=enabled;
      return true;
     }

   // All direct children of a given parent ID (used for family / confluence comparisons).
   int GetChildren(const string parentId,string &outIds[]) const
     {
      ArrayResize(outIds,0);
      int n=0;
      for(int i=0;i<m_count;i++)
        {
         if(m_defs[i].parentId==parentId)
           {
            ArrayResize(outIds,n+1);
            outIds[n]=m_defs[i].id;
            n++;
           }
        }
      return n;
     }

   // Walk up parentId links to find the ultimate S0xx root of a scenario family.
   string GetRootId(const string id) const
     {
      string cur=id;
      for(int guard=0; guard<32; guard++)
        {
         int i=FindIndex(cur);
         if(i<0) return cur;
         if(m_defs[i].parentId=="") return cur;
         cur=m_defs[i].parentId;
        }
      return cur;
     }
  };

#endif // __GSEA_SCENARIOREGISTRY_MQH__
