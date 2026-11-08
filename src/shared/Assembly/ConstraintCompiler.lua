--!strict
-- The only module that turns installed relationship records into Roblox
-- joints. Temporary alignment is never allowed to call this compiler.
local Hardware=require(script.Parent.FastenerSystem)
local Compiler={}
local function frame(feature:any):CFrame
 local axis=feature.componentLocalAxis.Unit
 -- Hinge/Prismatic/Cylindrical constraints operate on Attachment.Axis,
 -- which is the attachment's local X axis (not local Z).
 local y=axis:Cross(Vector3.yAxis)
 if y.Magnitude<.02 then y=axis:Cross(Vector3.zAxis) end
 y=y.Unit
 return CFrame.fromMatrix(feature.componentLocalCenter,axis,y,
  axis:Cross(y).Unit)
end
local function attachment(part:BasePart,component:any,feature:any,
 name:string):Attachment
 local node=component.nodes[1]
 local rotated=CFrame.new(node.position)*CFrame.fromOrientation(
  math.rad(node.rotation.X),math.rad(node.rotation.Y),
  math.rad(node.rotation.Z))
 local sourceFrame=part:GetAttribute("OWSourceLocalFrame")
 if typeof(sourceFrame)~="CFrame" then sourceFrame=CFrame.identity end
 local a=Instance.new("Attachment")
 a.Name=name
 -- Source CSG part CFrame is relative to node pose, not to the
 -- component workbench's origin.
 a.CFrame=(rotated*sourceFrame):ToObjectSpace(rotated*frame(feature))
 a.Parent=part
 return a
end
function Compiler.compile(record:any,parts:any,components:any,
 features:any,parent:Instance):({Instance}?,string?)
 local ca=components[record.a.componentId]
 local cb=components[record.b.componentId]
 local a=parts[record.a.componentId]
 local b=parts[record.b.componentId]
 local fa=features[record.a.componentId] and
  features[record.a.componentId][record.a.featureId]
 local fb=features[record.b.componentId] and
  features[record.b.componentId][record.b.featureId]
 if not ca or not cb or not a or not b or not fa or not fb then
  return nil,"Joint source component/hole not published"
 end
 local att0=attachment(a,ca,fa,"OW_A_"..record.id)
 local att1=attachment(b,cb,fb,"OW_B_"..record.id)
 local out={att0,att1}
 local constraint:Instance
 if record.kind=="Rigid" then
  local weld=Instance.new("WeldConstraint")
  weld.Part0=a
  weld.Part1=b
  constraint=weld
 elseif record.kind=="Revolute" then
  local h=Instance.new("HingeConstraint")
  h.Attachment0=att0 h.Attachment1=att1
  h.LimitsEnabled=record.limits and record.limits.enabled==true or false
  if h.LimitsEnabled then
   h.LowerAngle=math.clamp(record.limits.min or -180,-180,180)
   h.UpperAngle=math.clamp(record.limits.max or 180,-180,180)
  end
  constraint=h
 elseif record.kind=="Prismatic" then
  local h=Instance.new("PrismaticConstraint")
  h.Attachment0=att0 h.Attachment1=att1
  constraint=h
 elseif record.kind=="Cylindrical" then
  local h=Instance.new("CylindricalConstraint")
  h.Attachment0=att0 h.Attachment1=att1
  constraint=h
 elseif record.kind=="Ball" then
  local h=Instance.new("BallSocketConstraint")
  h.Attachment0=att0 h.Attachment1=att1
  constraint=h
 else
  att0:Destroy() att1:Destroy()
  return nil,"Unsupported relationship"
 end
 constraint.Name="OW_Relationship_"..record.id
 constraint.Parent=parent
 table.insert(out,constraint)
 for _,object in ipairs(Hardware.create(record,a,fa,att0,parent)) do
  table.insert(out,object)
 end
 return out,nil
end
function Compiler.destroy(instances:{Instance}?)
 for _,obj in ipairs(instances or {}) do
  if obj.Parent then obj:Destroy() end
 end
end
return Compiler
