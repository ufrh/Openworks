--!strict
local References=require(script.Parent.GeometryReferences)
local Profile=require(script.Parent.Parent.FORM.SketchBodyProfile)
local Resolver={}
Resolver.MinClearance=1/280
Resolver.MaxClearance=4/280
function Resolver.resolve(record:any,components:any,poses:any):(any?,string?)
 if type(record)~='table' or record.model~='BoreSupportV1' then
  return nil,'Unverified legacy connection; manufacture and validate support again'
 end
 local body,shaft=components[record.bodyId],components[record.shaftId]
 if not body or not shaft or body.id==shaft.id then return nil,'Missing independent body or shaft' end
 local bore=References.get(body,record.featureId)
 local cylinder=References.get(shaft,'shaft')
 if not bore or not bore.feature or not cylinder then return nil,'Missing bore or uncut cylindrical shaft' end
 local node=body.nodes[1]
 local active={}
 for _,op in ipairs(body.operations) do if op.enabled~=false then table.insert(active,op) end end
 if #active~=1 or active[1].kind~='Drill' or not bore.feature.through then
  return nil,'Support currently requires one through-drill in unmodified stock'
 end
 local center=bore.point
 local radius=bore.diameter*.5+Resolver.MinClearance
 if node.kind=='Block' then
  if math.abs(center.X)+radius>node.size.X*.5 or math.abs(center.Z)+radius>node.size.Z*.5 then
   return nil,'Bore lacks a continuous surrounding wall'
  end
 elseif node.kind=='SketchBody' then
  local ring=Profile.outline(node)
  local orientation=0
  for i,p in ipairs(ring) do local q=ring[i%#ring+1] orientation+=p.X*q.Y-q.X*p.Y end
  for i,p in ipairs(ring) do
   local q=ring[i%#ring+1]
   local e=q-p
   local distance=(e.X*(center.Z-p.Y)-e.Y*(center.X-p.X))*(if orientation>0 then 1 else -1)/e.Magnitude
   if distance<radius then return nil,'Bore support requires continuous convex stock around the hole' end
  end
 else return nil,'Unsupported housing stock for bearing validation' end
 local clearance=bore.diameter-cylinder.diameter
 if clearance<Resolver.MinClearance then return nil,'Oversized shaft or insufficient clearance (minimum 1 mm)' end
 if clearance>Resolver.MaxClearance then return nil,'Loose fit exceeds 4 mm diametral bearing approximation' end
 local bodyPose,shaftPose=poses[tostring(body.id)],poses[tostring(shaft.id)]
 if not bodyPose or not shaftPose then return nil,'Missing authored placement' end
 local a=References.world(bore,bodyPose)
 local b=References.world(cylinder,shaftPose)
 local cosine=math.abs(a.direction:Dot(b.direction))
 if cosine<.999999 then return nil,'Shaft and bore axes are not parallel' end
 local delta=b.point-a.point
 local axial=delta:Dot(a.direction)
 local radial=(delta-a.direction*axial).Magnitude
 if radial+math.sqrt(math.max(0,1-cosine*cosine))*cylinder.length*.5>clearance*.5-1e-5 then
  return nil,'Shaft centerline exceeds radial clearance'
 end
 local low=math.max(0,axial-cylinder.length*.5)
 local high=math.min(node.size.Y,axial+cylinder.length*.5)
 if high-low<math.min(node.size.Y*.5,cylinder.diameter) then
  return nil,'Insufficient axial engagement; shaft has left its support'
 end
 return {kind='Cylindrical',model='BoreSupportV1',bodyId=body.id,shaftId=shaft.id,
  featureId=record.featureId,point=a.point,direction=a.direction,
  translation=1,rotation=1,retained=false},nil
end
return Resolver
