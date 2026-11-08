--!strict
-- Physical fasteners are manufactured components. This compiler never
-- spawns a decorative pin or bolt and never disables part collisions.
local Compiler={}
local function frame(feature:any):CFrame
 local axis=feature.componentLocalAxis.Unit
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
 local source=part:GetAttribute("OWSourceLocalFrame")
 if typeof(source)~="CFrame" then source=CFrame.identity end
 local a=Instance.new("Attachment")
 a.Name=name
 a.CFrame=(rotated*source):ToObjectSpace(rotated*frame(feature))
 a.Parent=part
 return a
end
local function weld(a:BasePart,b:BasePart,name:string,parent:Instance):WeldConstraint
 local w=Instance.new("WeldConstraint")
 w.Name=name w.Part0=a w.Part1=b w.Parent=parent
 return w
end
function Compiler.compile(record:any,parts:any,components:any,
 features:any,parent:Instance):({Instance}?,string?)
 local ca=components[record.a.componentId]
 local cb=components[record.b.componentId]
 local cs=components[record.shaftId]
 local a=parts[record.a.componentId]
 local b=parts[record.b.componentId]
 local shaft=parts[record.shaftId]
 local fa=features[record.a.componentId] and
  features[record.a.componentId][record.a.featureId]
 local fb=features[record.b.componentId] and
  features[record.b.componentId][record.b.featureId]
 if not ca or not cb or not cs or not a or not b or not shaft
  or not fa or not fb or cs.nodes[1].kind~="Cylinder" then
  return nil,"Joint requires two drilled bodies and the manufactured shaft"
 end
 if record.kind~="Rigid" and record.kind~="Revolute" then
  return nil,"Unsupported physical connection"
 end
 local attA=attachment(a,ca,fa,"OW_A_"..record.id)
 local attB=attachment(b,cb,fb,"OW_B_"..record.id)
 local attS=Instance.new("Attachment")
 attS.Name="OW_Shaft_"..record.id
 attS.CFrame=shaft.CFrame:ToObjectSpace(attB.WorldCFrame)
 attS.Parent=shaft
 local objects={attA,attB,attS}
 -- Shaft is mechanically fixed to the first body. The second body
 -- either locks onto the shaft or rotates on it as a bearing.
 table.insert(objects,weld(a,shaft,"OW_ShaftRetention_"..record.id,parent))
 if record.kind=="Rigid" then
  table.insert(objects,weld(shaft,b,"OW_RigidThroughShaft_"..record.id,parent))
 else
  local hinge=Instance.new("HingeConstraint")
  hinge.Name="OW_ShaftBearing_"..record.id
  hinge.Attachment0=attS
  hinge.Attachment1=attB
  hinge.LimitsEnabled=record.limits and record.limits.enabled==true or false
  if hinge.LimitsEnabled then
   hinge.LowerAngle=math.clamp(record.limits.min or -180,-180,180)
   hinge.UpperAngle=math.clamp(record.limits.max or 180,-180,180)
  end
  hinge.Parent=parent
  table.insert(objects,hinge)
 end
 return objects,nil
end
function Compiler.destroy(objects:{Instance}?)
 for _,obj in ipairs(objects or {}) do
  if obj.Parent then obj:Destroy() end
 end
end
return Compiler
