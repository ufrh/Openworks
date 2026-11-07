--!strict
local Registry={}
Registry.__index=Registry
function Registry.new() return setmetatable({definitions={}},Registry) end
function Registry:register(id:string,definition:any)
 assert(self.definitions[id]==nil,"Duplicate tool "..id)
 assert(type(definition)=="table" and type(definition.category)=="string","Tool category required")
 self.definitions[id]=definition
end
function Registry:get(id:string):any return self.definitions[id] end
function Registry:available(id:string,mode:string):boolean
 local definition=self.definitions[id]
 return definition~=nil and definition.mode==mode
end
function Registry.standard()
 local self=Registry.new()
 for _,item in ipairs({
  {"Drill","Fabrication"},{"File","Fabrication"},{"Smooth","Fabrication"},
  {"Inset","Fabrication"},{"Saw","Fabrication"},{"Sketch","Sketch"},
  {"Measure","Inspection"},{"Move","Transform"},{"Scale","Transform"},{"Rotate","Transform"},
 }) do self:register(item[1],{mode="Edit",category=item[2]}) end
 return self
end
return Registry
