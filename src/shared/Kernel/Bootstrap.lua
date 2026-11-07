--!strict
local Lifecycle=require(script.Parent.Lifecycle)
local Registry=require(script.Parent.Registry)
local Bootstrap={}
Bootstrap.__index=Bootstrap
function Bootstrap.new()
 return setmetatable({registry=Registry.new(),started={}},Bootstrap)
end
function Bootstrap:add(name:string,instance:any)
 self.registry:register(name,instance)
end
function Bootstrap:start(context:any):(boolean,string?)
 for _,name in ipairs(self.registry.order) do
  local service=self.registry:get(name)
  local ok,err=pcall(function()Lifecycle.start(service,context)end)
  if not ok then
   self:stop()
   return false,"Service "..name.." failed: "..tostring(err)
  end
  table.insert(self.started,service)
 end
 return true,nil
end
function Bootstrap:stop()
 for i=#self.started,1,-1 do
  pcall(function()Lifecycle.stop(self.started[i])end)
  self.started[i]=nil
 end
end
function Bootstrap:destroy()
 self:stop()
 for _,name in ipairs(self.registry.order) do
  pcall(function()Lifecycle.destroy(self.registry:get(name))end)
 end
 self.registry:clear()
end
return Bootstrap
