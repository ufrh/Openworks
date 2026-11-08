--!strict
-- Q3 fastener representation. Manufactured joint constraints govern motion;
-- simplified fasteners visualize retained hardware without falsely claiming
-- collision-accurate thread or pin contact simulation.
local Hardware={}
local function shaftFrame(world:CFrame):CFrame
 local axis=world.XVector.Unit
 local y=axis:Cross(Vector3.yAxis)
 if y.Magnitude<.02 then y=axis:Cross(Vector3.zAxis) end
 y=y.Unit
 return CFrame.fromMatrix(world.Position,axis,y,axis:Cross(y).Unit)
end
local function cylinder(owner:BasePart,name:string,diameter:number,
 length:number,pose:CFrame,container:Instance):{Instance}
 local part=Instance.new("Part")
 part.Name=name
 part.Shape=Enum.PartType.Cylinder
 part.Size=Vector3.new(length,diameter,diameter)
 part.CFrame=pose
 part.Anchored=true
 part.CanCollide=false
 part.CanTouch=false
 part.CanQuery=false
 part.Massless=true
 part.Material=Enum.Material.Metal
 part.Color=Color3.fromRGB(208,216,223)
 part.Parent=container
 local weld=Instance.new("WeldConstraint")
 weld.Name=name.."_Retention"
 weld.Part0=owner
 weld.Part1=part
 weld.Parent=container
 part.Anchored=false
 return {part,weld}
end
function Hardware.create(record:any,part:BasePart,feature:any,
 attachment:Attachment,container:Instance):{Instance}
 if record.kind~="Rigid" and record.kind~="Revolute" then return {} end
 local world=shaftFrame(attachment.WorldCFrame)
 local diameter=math.clamp(feature.diameter*.72,.014,1)
 local length=math.clamp(feature.depth*1.5,.1,2)
 local pieces=cylinder(part,
  if record.kind=="Rigid" then "OW_BoltShaft" else "OW_PinShaft",
  diameter,length,world,container)
 local headPose=world*CFrame.new(-length*.5-.025,0,0)
 local head=cylinder(part,
  if record.kind=="Rigid" then "OW_BoltHead" else "OW_PinHead",
  diameter*1.7,.06,headPose,container)
 for _,object in ipairs(head) do table.insert(pieces,object) end
 return pieces
end
return Hardware
