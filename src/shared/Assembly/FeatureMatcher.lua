--!strict
-- Pure, deterministic matching: authored hole axes/diameters, not mesh IDs.
-- No force, snapping or permanent constraint is created by this module.
local Matcher={}
local MAX_ANGLE=math.rad(20)
local function valid(f:any):boolean
 return type(f)=="table" and f.type=="Hole" and
  typeof(f.componentLocalCenter)=="Vector3" and
  typeof(f.componentLocalAxis)=="Vector3" and
  type(f.diameter)=="number" and f.diameter>0
end
local function frame(f:any):CFrame
 local axis=f.componentLocalAxis.Unit
 local x=axis:Cross(Vector3.yAxis)
 if x.Magnitude<.02 then x=axis:Cross(Vector3.xAxis) end
 x=x.Unit
 return CFrame.fromMatrix(f.componentLocalCenter,x,axis:Cross(x).Unit,axis)
end
Matcher.frame=frame
-- Server verification of stage-authored relative body pose. Source
-- CSG frames are material-local, so never assume a manufactured mesh
-- is centered at the node origin.
function Matcher.validateRelative(fa:any,fb:any,relative:CFrame,
 sourceA:CFrame,sourceB:CFrame):(boolean,string?)
 if not Matcher.compatible(fa,fb) then
  return false,"Incompatible bore diameters"
 end
 local a=sourceA:Inverse()*frame(fa)
 local b=relative*sourceB:Inverse()*frame(fb)
 local axisA=a.ZVector.Unit
 local axisB=b.ZVector.Unit
 local angle=math.acos(math.clamp(math.abs(axisA:Dot(axisB)),-1,1))
 local separation=b.Position-a.Position
 local along=separation:Dot(axisA)
 local lateral=(separation-axisA*along).Magnitude
 if angle>math.rad(16) then return false,"Bore axes are not parallel" end
 if lateral>math.max(0.05,math.min(fa.diameter,fb.diameter)*0.35) then
  return false,"Bore centerlines miss their clearance tolerance"
 end
 if math.abs(along)>math.max(0.65,fa.depth+fb.depth+.2) then
  return false,"Hole openings are too far apart for installation"
 end
 return true,nil
end
function Matcher.compatible(a:any,b:any):boolean
 if not valid(a) or not valid(b) then return false end
 -- Through and blind holes are both candidates, not threaded features.
 local mismatch=math.abs(a.diameter-b.diameter)
 return mismatch<=math.max(0.025,math.min(a.diameter,b.diameter)*0.12)
end
function Matcher.candidates(a:{any},b:{any},poseA:CFrame,poseB:CFrame,
 radius:number?):{any}
 local distanceLimit=radius or 2
 local results={}
 for _,fa in ipairs(a) do
  for _,fb in ipairs(b) do
   if not Matcher.compatible(fa,fb) then continue end
   local wa=poseA:PointToWorldSpace(fa.componentLocalCenter)
   local wb=poseB:PointToWorldSpace(fb.componentLocalCenter)
   local sep=(wa-wb).Magnitude
   if sep>distanceLimit then continue end
   local na=poseA:VectorToWorldSpace(fa.componentLocalAxis).Unit
   local nb=poseB:VectorToWorldSpace(fb.componentLocalAxis).Unit
   local angle=math.acos(math.clamp(math.abs(na:Dot(nb)),-1,1))
   if angle>MAX_ANGLE then continue end
   table.insert(results,{
    a=fa,b=fb,distance=sep,angle=angle,
    score=sep+angle*0.35+math.abs(fa.diameter-fb.diameter),
   })
  end
 end
 table.sort(results,function(x,y)
  if x.score==y.score then
   return x.a.id..x.b.id<y.a.id..y.b.id
  end
  return x.score<y.score
 end)
 return results
end
-- Match a hole pair, then use the second separated pair to fix the
-- otherwise-free twist around the primary bore axis. One rigid target pose
-- is returned; never apply independent competing aligners to each hole.
function Matcher.pattern(a:{any},b:{any},poseA:CFrame,poseB:CFrame,
 radius:number?):any?
 local pairs=Matcher.candidates(a,b,poseA,poseB,radius)
 if #pairs==0 then return nil end
 local first=pairs[1]
 local fa,fb=first.a,first.b
 local axisA=poseA:VectorToWorldSpace(fa.componentLocalAxis).Unit
 local axisB=poseB:VectorToWorldSpace(fb.componentLocalAxis).Unit
 local rotate=CFrame.fromAxisAngle(axisB:Cross(axisA).Magnitude>.0001
  and axisB:Cross(axisA).Unit or Vector3.xAxis,
  math.acos(math.clamp(axisB:Dot(axisA),-1,1)))
 if axisB:Dot(axisA)<-.9999 then
  rotate=CFrame.fromAxisAngle(
   math.abs(axisB.Y)<.95 and Vector3.yAxis or Vector3.xAxis,math.pi)
 end
 local centerB=poseB:PointToWorldSpace(fb.componentLocalCenter)
 local centerA=poseA:PointToWorldSpace(fa.componentLocalCenter)
 local target=CFrame.new(centerA)*rotate*CFrame.new(-centerB)*poseB
 local matched={first}
 local bestResidual=math.huge
 local second:any=nil
 for i=2,#pairs do
  local pair=pairs[i]
  if pair.a.id==fa.id or pair.b.id==fb.id then continue end
  local pa=poseA:PointToWorldSpace(pair.a.componentLocalCenter)
  local pb=target:PointToWorldSpace(pair.b.componentLocalCenter)
  local va=(pa-centerA)
  local vb=(pb-centerA)
  local vaPlane=va-axisA*va:Dot(axisA)
  local vbPlane=vb-axisA*vb:Dot(axisA)
  if vaPlane.Magnitude<.1 or vbPlane.Magnitude<.1 then continue end
  local residual=math.abs(vaPlane.Magnitude-vbPlane.Magnitude)
  if residual<bestResidual and residual<math.max(.04,fa.diameter*.4) then
   bestResidual=residual
   second={pair=pair,va=vaPlane,vb=vbPlane}
  end
 end
 if second then
  local va=second.va.Unit
  local vb=second.vb.Unit
  local twist=math.atan2(axisA:Dot(vb:Cross(va)),vb:Dot(va))
  target=CFrame.new(centerA)*CFrame.fromAxisAngle(axisA,twist)*
   CFrame.new(-centerA)*target
  table.insert(matched,second.pair)
 end
 -- Extra holes join the same pattern only if the SINGLE solved rigid
 -- target also fits their centers within bore clearance.
 local usedA={[fa.id]=true}
 local usedB={[fb.id]=true}
 if second then
  usedA[second.pair.a.id]=true
  usedB[second.pair.b.id]=true
 end
 for _,pair in ipairs(pairs) do
  if usedA[pair.a.id] or usedB[pair.b.id] then continue end
  local wa=poseA:PointToWorldSpace(pair.a.componentLocalCenter)
  local wb=target:PointToWorldSpace(pair.b.componentLocalCenter)
  if (wa-wb).Magnitude<=math.max(.04,pair.a.diameter*.35) then
   table.insert(matched,pair)
   usedA[pair.a.id]=true usedB[pair.b.id]=true
  end
 end
 return {targetPose=target,pairs=matched,score=first.score,
  axis=axisA,hasTwistAnchor=second~=nil}
end
return Matcher
