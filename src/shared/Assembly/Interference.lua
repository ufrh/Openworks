--!strict
local Geometry=game:GetService('GeometryService')
local Volume=require(script.Parent.Parent.FORM.MaterialVolume)
local Interference={}
Interference.LinearTolerance=1e-4
Interference.VolumeTolerance=1e-8
function Interference.separated(a:BasePart,b:BasePart):boolean
 local axes={a.CFrame.XVector,a.CFrame.YVector,a.CFrame.ZVector,
  b.CFrame.XVector,b.CFrame.YVector,b.CFrame.ZVector}
 for i=1,3 do for j=4,6 do
  local cross=axes[i]:Cross(axes[j])
  if cross.Magnitude>1e-8 then table.insert(axes,cross.Unit) end
 end end
 local delta=b.Position-a.Position
 local function radius(p:BasePart,v:Vector3):number
  return .5*(math.abs(p.CFrame.XVector:Dot(v))*p.Size.X+
   math.abs(p.CFrame.YVector:Dot(v))*p.Size.Y+math.abs(p.CFrame.ZVector:Dot(v))*p.Size.Z)
 end
 for _,axis in ipairs(axes) do
  if math.abs(delta:Dot(axis))>=radius(a,axis)+radius(b,axis)-Interference.LinearTolerance then return true end
 end
 return false
end
function Interference.pair(a:BasePart,b:BasePart):(boolean,string?)
 if Interference.separated(a,b) then return true,nil end
 if a:IsA('Part') and b:IsA('Part') and a.Shape==Enum.PartType.Block and b.Shape==Enum.PartType.Block then
  return false,'Solid penetration (oriented block test)'
 end
 local ok,pieces=pcall(function()
  return Geometry:IntersectAsync(a,{b},{SplitApart=true,
   CollisionFidelity=Enum.CollisionFidelity.PreciseConvexDecomposition})
 end)
 if not ok then return false,'Cannot certify clearance: CSG intersection unavailable' end
 local penetration,uncertain=false,false
 for _,piece in ipairs(pieces) do
  local success,volume,exact=pcall(Volume.fromPartAsync,piece)
  if not success then uncertain=true
  elseif volume>Interference.VolumeTolerance then
   penetration=true
   if not exact then uncertain=true end
  end
  piece:Destroy()
 end
 if penetration then return false,if uncertain then
  'Possible penetration (collision-volume estimate); placement rejected' else 'Solid penetration (CSG mesh volume)' end
 if uncertain then return false,'Cannot certify intersection volume' end
 return true,nil
end
return Interference
