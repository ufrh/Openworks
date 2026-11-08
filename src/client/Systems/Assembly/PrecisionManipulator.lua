--!strict
local Players=game:GetService('Players')
local Gizmo=require(script.Parent.Parent.Parent.Tools.Transform.TransformGizmo)
local Manipulator={}
Manipulator.__index=Manipulator
function Manipulator.new()
 local self=setmetatable({part=nil,component=nil,options={translationStep=1/280,rotationStep=5,world=false}},Manipulator)
 local document={}
 function document:applyTransform(component:any,_index:number,position:Vector3?,_size:any,rotation:Vector3?):boolean
  local node=component.nodes[1]
  node.position=position or node.position node.rotation=rotation or node.rotation
  local r=node.rotation
  if self.owner.part then self.owner.part.CFrame=CFrame.new(node.position)*CFrame.fromOrientation(math.rad(r.X),math.rad(r.Y),math.rad(r.Z)) end
  return true
 end
 document.owner=self
 self.gizmo=Gizmo.new(Players.LocalPlayer:WaitForChild('PlayerGui'),document,function(phase,_,_,changed)
  if phase=='begin' then
   self.start=self.part and self.part.CFrame
   if self.onActiveChanged then self.onActiveChanged(true) end
  elseif phase=='finish' then
   if self.onActiveChanged then self.onActiveChanged(false) end
   if changed and self.onCommit and self.part then self.onCommit(self.part.CFrame,self.start) end
  end
 end,self.options)
 return self
end
function Manipulator:select(part:BasePart?)
 if self.gizmo:isDragging() then self.gizmo.finish() end
 self.part=part
 if not part then self.component=nil self.gizmo:hide() return end
 local x,y,z=part.CFrame:ToOrientation()
 self.component={nodes={{position=part.Position,size=part.Size,
  rotation=Vector3.new(math.deg(x),math.deg(y),math.deg(z))}}}
 self.gizmo:show(self.component,1)
end
function Manipulator:setMode(mode:string) self.gizmo:setMode(mode) end
function Manipulator:capturesPoint(point:Vector2):boolean return self.gizmo:capturesPoint(point) end
function Manipulator:Destroy() self.gizmo:destroy() end
return Manipulator
