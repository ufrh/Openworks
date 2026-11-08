--!strict
-- Authoritative geometric acceptance for an actual manufactured shaft
-- placed through two separate drilled components. Does not move bodies.
local Matcher=require(script.Parent.FeatureMatcher)
local Fit={}
Fit.MIN_CLEARANCE=1/280 -- one millimeter radial/diametral budget in studs
local MAX_ANGULAR_ERROR=math.rad(9)
local MAX_CENTER_ERROR=2/280
local function fin(v:number):boolean
 return v==v and v~=math.huge and v~=-math.huge
end
local function finiteFrame(frame:CFrame):boolean
 for _,n in ipairs({frame:GetComponents()}) do
  if not fin(n) then return false end
 end
 return true
end
function Fit.validate(fa:any,fb:any,relativeB:CFrame,
 sourceA:CFrame,sourceB:CFrame,
 shaftSize:Vector3,shaftRelative:CFrame):(boolean,string?)
 if typeof(relativeB)~="CFrame" or typeof(shaftRelative)~="CFrame"
  or typeof(sourceA)~="CFrame" or typeof(sourceB)~="CFrame"
  or typeof(shaftSize)~="Vector3"
  or not finiteFrame(relativeB) or not finiteFrame(shaftRelative) then
  return false,"Invalid shaft/part placement"
 end
 if not fa or not fb or not fa.through or not fb.through
  or not Matcher.compatible(fa,fb) then
  return false,"Two compatible through-bores are required"
 end
 local diameter=shaftSize.X
 local length=shaftSize.Y
 if diameter<=0 or length<=0 then return false,"Invalid manufactured shaft" end
 -- Diameter must be smaller than BOTH bores; it cannot occupy their walls.
 if diameter+Fit.MIN_CLEARANCE>math.min(fa.diameter,fb.diameter) then
  return false,"Shaft is too wide: manufacture a smaller diameter with clearance"
 end
 local matched,reason=Matcher.validateRelative(fa,fb,relativeB,sourceA,sourceB)
 if not matched then return false,reason end
 local frameA=sourceA:Inverse()*Matcher.frame(fa)
 local frameB=relativeB*sourceB:Inverse()*Matcher.frame(fb)
 local axis=shaftRelative.XVector.Unit
 local center=shaftRelative.Position
 for _,pair in ipairs({
  {frame=frameA,feature=fa},{frame=frameB,feature=fb},
 }) do
  local bore=pair.frame
  local boreAxis=bore.ZVector.Unit
  local angle=math.acos(math.clamp(math.abs(axis:Dot(boreAxis)),-1,1))
  if angle>Fit.MAX_ANGULAR_ERROR then
   return false,"Shaft must be physically parallel to both drilled bores"
  end
  local separation=bore.Position-center
  local along=separation:Dot(axis)
  local radial=(separation-axis*along).Magnitude
  local radialLimit=math.min(Fit.MAX_CENTER_ERROR,
   math.max(Fit.MIN_CLEARANCE/2,pair.feature.diameter*.5-diameter*.5))
  if radial>radialLimit then
   return false,"Shaft centerline misses a bore; use precision handles"
  end
  -- Merely touching the hole opening is not shaft engagement. The
  -- manufactured cylinder must reach inward along both drilled bores.
  local engagement=math.min(pair.feature.depth*.5,.15)
  local inside=bore.Position+boreAxis*engagement
  local insideAlong=(inside-center):Dot(axis)
  if math.abs(along)>length*.5-.01
   or math.abs(insideAlong)>length*.5-.01 then
   return false,"Shaft does not physically enter both bores deeply enough"
  end
 end
 return true,nil
end
return Fit
