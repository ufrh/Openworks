--!strict
-- Persistent manufacturing features derived from source operation history.
-- No arbitrary Roblox Attributes or geometrical inference from render meshes.
-- Assembly Q3 will verify final material openings/clearances before mating.
local Features={}
local function hole(node:any,operation:any):any?
 local center:Vector3
 local axis:Vector3
 if operation.kind=="Drill" then
  center=Vector3.new(
   operation.x-node.size.X*0.5,
   node.size.Y*0.5,
   operation.z-node.size.Z*0.5)
  axis=-Vector3.yAxis
 elseif operation.kind=="DrillFace" then
  center=operation.origin
  axis=-operation.normal.Unit
 else return nil end
 return {
  id="hole:"..tostring(operation.id),
  type="Hole",
  operationId=operation.id,
  componentLocalCenter=center,
  componentLocalAxis=axis,
  diameter=operation.diameter,
  depth=operation.depth,
  through=operation.through~=false,
  -- Candidate means the history produces a hole; a subsequent cut
  -- may modify it. Assembly validates it against the final compiled body.
  status="candidate",
 }
end
function Features.list(component:any):{any}
 local node=component.nodes and component.nodes[1]
 if not node then return {} end
 local results={}
 for _,operation in ipairs(component.operations or {}) do
  if operation.enabled~=false then
   local f=hole(node,operation)
   if f then table.insert(results,f) end
  end
 end
 return results
end
function Features.get(component:any,id:string):any?
 for _,feature in ipairs(Features.list(component)) do
  if feature.id==id then return feature end
 end
 return nil
end
function Features.worldFrame(component:any,feature:any):CFrame
 local node=assert(component.nodes[1])
 local rotation=node.rotation
 local pose=CFrame.new(node.position)*CFrame.fromOrientation(
  math.rad(rotation.X),math.rad(rotation.Y),math.rad(rotation.Z))
 local worldCenter=pose:PointToWorldSpace(feature.componentLocalCenter)
 local worldAxis=pose:VectorToWorldSpace(feature.componentLocalAxis)
 return CFrame.lookAt(worldCenter,worldCenter+worldAxis)
end
return Features
