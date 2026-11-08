--!strict
-- A joint is an explicit installed/declared relationship, never an
-- inference from spatial proximity or an arbitrary drilled through-hole.
local Graph={}
Graph.__index=Graph
Graph.Types={
 Rigid={translation=0,rotation=0,hardware="Bolt"},
 Revolute={translation=0,rotation=1,hardware="Pin"},
 Prismatic={translation=1,rotation=0,hardware="Guide"},
 Cylindrical={translation=1,rotation=1,hardware="Sleeve"},
 Ball={translation=0,rotation=3,hardware="Socket"},
}
function Graph.new()
 return setmetatable({joints={},nextId=0},Graph)
end
local function validRef(ref:any):boolean
 return type(ref)=="table" and type(ref.componentId)=="number"
  and type(ref.featureId)=="string" and #ref.featureId<=96
end
function Graph:add(kind:string,a:any,b:any,limits:any?):(any?,string?)
 if not Graph.Types[kind] then return nil,"Unknown relationship" end
 if not validRef(a) or not validRef(b) or
  a.componentId==b.componentId then
  return nil,"Relationship needs different components and real feature IDs"
 end
 for _,joint in pairs(self.joints) do
  if (joint.a.componentId==a.componentId and
   joint.b.componentId==b.componentId) or
   (joint.a.componentId==b.componentId and
   joint.b.componentId==a.componentId) then
   return nil,"One mechanical relationship per component pair in Q3"
  end
 end
 self.nextId+=1
 local id=self.nextId
 local joint={id=id,kind=kind,
  a={componentId=a.componentId,featureId=a.featureId},
  b={componentId=b.componentId,featureId=b.featureId},
  limits=limits or {},installed=true,actuation={enabled=false,speed=0,torque=0}}
 self.joints[id]=joint
 return joint,nil
end
function Graph:remove(id:number):boolean
 if not self.joints[id] then return false end
 self.joints[id]=nil
 return true
end
function Graph:removeComponent(id:number)
 for jointId,joint in pairs(self.joints) do
  if joint.a.componentId==id or joint.b.componentId==id then
   self.joints[jointId]=nil
  end
 end
end
function Graph:list():{any}
 local result={}
 for _,joint in pairs(self.joints) do table.insert(result,joint) end
 table.sort(result,function(a,b)return a.id<b.id end)
 return result
end
function Graph:restore(source:any)
 self.joints={}
 self.nextId=0
 if type(source)~="table" then return end
 for _,j in ipairs(source) do
  if type(j)=="table" and Graph.Types[j.kind]
   and validRef(j.a) and validRef(j.b)
   and j.a.componentId~=j.b.componentId
   and type(j.id)=="number" and j.id>0 and j.id%1==0
   and not self.joints[j.id] then
   self.joints[j.id]={
    id=j.id,kind=j.kind,
    a={componentId=j.a.componentId,featureId=j.a.featureId},
    b={componentId=j.b.componentId,featureId=j.b.featureId},
    limits=if type(j.limits)=="table" then table.clone(j.limits) else {},
    installed=true,
    actuation=if type(j.actuation)=="table" then table.clone(j.actuation)
     else {enabled=false,speed=0,torque=0},
   }
   self.nextId=math.max(self.nextId,j.id)
  end
 end
end
return Graph
