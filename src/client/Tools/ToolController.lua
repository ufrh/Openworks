--!strict
local Controller={}
Controller.__index=Controller
function Controller.new(registry:any)
 return setmetatable({registry=registry,active=nil,mode="Free"},Controller)
end
function Controller:setMode(mode:string)
 if self.mode~=mode then self:clear() self.mode=mode end
end
function Controller:activate(id:string,tool:any?):(boolean,string?)
 if not self.registry:available(id,self.mode) then
  return false,"Tool "..id.." unavailable in "..self.mode.." mode"
 end
 self:clear()
 self.active={id=id,instance=tool}
 if tool and tool.Enter then tool:Enter() end
 return true,nil
end
function Controller:clear()
 local active=self.active
 self.active=nil
 if active and active.instance and active.instance.Exit then active.instance:Exit() end
end
function Controller:get():string? return if self.active then self.active.id else nil end
function Controller:destroy() self:clear() end
return Controller
