--!strict
-- Physics-only Assembly precision manipulator. Never writes CFrame of a
-- simulated workpiece: target changes drive bounded solver constraints.
local Players=game:GetService("Players")
local Manipulator={}
Manipulator.__index=Manipulator
local STEP=1/280 -- 1 mm placement increments
local ROTATION_STEP=math.rad(5)
local DIRECTIONS={
 [Enum.NormalId.Right]=Vector3.xAxis,
 [Enum.NormalId.Left]=-Vector3.xAxis,
 [Enum.NormalId.Top]=Vector3.yAxis,
 [Enum.NormalId.Bottom]=-Vector3.yAxis,
 [Enum.NormalId.Back]=Vector3.zAxis,
 [Enum.NormalId.Front]=-Vector3.zAxis,
}
local AXES={
 [Enum.Axis.X]=Vector3.xAxis,
 [Enum.Axis.Y]=Vector3.yAxis,
 [Enum.Axis.Z]=Vector3.zAxis,
}
function Manipulator.new()
 local ui=Players.LocalPlayer:WaitForChild("PlayerGui")
 local move=Instance.new("Handles")
 move.Name="OW_AssemblyMoveHandles"
 move.Style=Enum.HandlesStyle.Movement
 move.Faces=Faces.new(Enum.NormalId.Right,Enum.NormalId.Left,
  Enum.NormalId.Top,Enum.NormalId.Bottom,
  Enum.NormalId.Back,Enum.NormalId.Front)
 move.Color3=Color3.fromRGB(91,220,244)
 move.Visible=false
 move.Parent=ui
 local rotate=Instance.new("ArcHandles")
 rotate.Name="OW_AssemblyRotateHandles"
 rotate.Axes=Axes.new(Enum.Axis.X,Enum.Axis.Y,Enum.Axis.Z)
 rotate.Color3=Color3.fromRGB(245,185,98)
 rotate.Visible=false
 rotate.Parent=ui
 local self=setmetatable({
  part=nil,mode="Move",move=move,rotate=rotate,
  drag=nil,connections={},onActiveChanged=nil,
 },Manipulator)
 table.insert(self.connections,move.MouseButton1Down:Connect(function(face)
  self:_start("Move",face)
 end))
 table.insert(self.connections,move.MouseDrag:Connect(function(face,distance)
  self:_move(face,distance)
 end))
 table.insert(self.connections,move.MouseButton1Up:Connect(function()
  self:_stop()
 end))
 table.insert(self.connections,rotate.MouseButton1Down:Connect(function(axis)
  self:_start("Rotate",axis)
 end))
 table.insert(self.connections,rotate.MouseDrag:Connect(function(axis,angle)
  self:_rotate(axis,angle)
 end))
 table.insert(self.connections,rotate.MouseButton1Up:Connect(function()
  self:_stop()
 end))
 return self
end
function Manipulator:_stop()
 local drag=self.drag
 if not drag then return end
 self.drag=nil
 if drag.drive then drag.drive:Destroy() end
 if drag.attachment then drag.attachment:Destroy() end
 if self.onActiveChanged then self.onActiveChanged(false) end
end
function Manipulator:select(part:BasePart?)
 self:_stop()
 self.part=part
 self.move.Adornee=part
 self.rotate.Adornee=part
 self.move.Visible=part~=nil and self.mode=="Move"
 self.rotate.Visible=part~=nil and self.mode=="Rotate"
end
function Manipulator:setMode(mode:string)
 if mode~="Move" and mode~="Rotate" then return end
 self:_stop()
 self.mode=mode
 self.move.Visible=self.part~=nil and mode=="Move"
 self.rotate.Visible=self.part~=nil and mode=="Rotate"
end
function Manipulator:_start(kind:string,axis:any)
 local part=self.part
 if not part or not part.Parent or part.Anchored then return end
 self:_stop()
 local attachment=Instance.new("Attachment")
 attachment.Name="OW_PrecisionDriveAnchor"
 attachment.Parent=part
 local drive:Instance
 if kind=="Move" then
  local align=Instance.new("AlignPosition")
  align.Name="OW_PrecisionTranslation"
  align.Mode=Enum.PositionAlignmentMode.OneAttachment
  align.Attachment0=attachment
  align.Position=part.Position
  align.MaxForce=math.clamp(part:GetMass()*1000,160,18000)
  align.MaxVelocity=2
  align.Responsiveness=12
  align.RigidityEnabled=false
  align.ApplyAtCenterOfMass=true
  drive=align
 else
  local align=Instance.new("AlignOrientation")
  align.Name="OW_PrecisionRotation"
  align.Mode=Enum.OrientationAlignmentMode.OneAttachment
  align.Attachment0=attachment
  align.CFrame=part.CFrame
  align.MaxTorque=math.clamp(part:GetMass()*600,90,10000)
  align.MaxAngularVelocity=2
  align.Responsiveness=10
  align.RigidityEnabled=false
  drive=align
 end
 drive.Parent=part
 self.drag={drive=drive,attachment=attachment,part=part,
  start=part.CFrame,kind=kind,axis=axis}
 if self.onActiveChanged then self.onActiveChanged(true) end
end
function Manipulator:_move(face:Enum.NormalId,distance:number)
 local drag=self.drag
 if not drag or drag.kind~="Move" or not DIRECTIONS[face] then return end
 local direction=drag.start:VectorToWorldSpace(DIRECTIONS[face])
 local delta=math.round(distance/STEP)*STEP
 (drag.drive::AlignPosition).Position=drag.start.Position+direction*delta
end
function Manipulator:_rotate(axis:Enum.Axis,angle:number)
 local drag=self.drag
 if not drag or drag.kind~="Rotate" or not AXES[axis] then return end
 local snapped=math.round(angle/ROTATION_STEP)*ROTATION_STEP
 (drag.drive::AlignOrientation).CFrame=
  drag.start*CFrame.fromAxisAngle(AXES[axis],snapped)
end
function Manipulator:Destroy()
 self:select(nil)
 for _,connection in ipairs(self.connections) do connection:Disconnect() end
 self.move:Destroy()
 self.rotate:Destroy()
end
return Manipulator
