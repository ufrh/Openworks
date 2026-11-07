--!strict
-- Client-local physical bodies in Free Mode. FORM's authoritative CAD mesh
-- stays in Edit coordinates; this layer owns separate world/assembly copies.
-- Q2/Q4 will replace this local representation with server-owned bodies.
local WorldProjection={}
WorldProjection.__index=WorldProjection

local function setBodyMode(entry:any,free:boolean)
 for _,part in ipairs(entry.model:GetDescendants()) do
  if part:IsA("BasePart") then
   part.Anchored=not free
   part.CanCollide=free
   part.CanTouch=free
   part.CanQuery=free
   if free then
    if part:IsA("MeshPart") or part:IsA("PartOperation") then
     -- Hull would fill openings. Roblox collision is still approximate.
     pcall(function()
      part.CollisionFidelity=Enum.CollisionFidelity.PreciseConvexDecomposition
     end)
    end
   else
    part.AssemblyLinearVelocity=Vector3.zero
    part.AssemblyAngularVelocity=Vector3.zero
   end
  end
 end
 if entry.detector then entry.detector.Enabled=free end
end

function WorldProjection.new(onSelect:((number)->())?)
 local root=Instance.new("Folder")
 root.Name="OPENWORKS_LocalWorldComponents"
 return setmetatable({
  root=root,cache={},mode=nil,onSelect=onSelect,
 },WorldProjection)
end

function WorldProjection:_saveFreePositions()
 if self.mode~="Free" or self.root.Parent==nil then return end
 for _,entry in pairs(self.cache) do
  if entry.model.Parent==self.root then
   -- Store displacement/rotation relative to the component's *unmoved*
   -- world pose, so a recompilation can replace the solid in place.
   entry.freeDelta=entry.model:GetPivot()*entry.basePivot:Inverse()
  end
 end
end

function WorldProjection:show(preview:any,document:any,workspaceData:any,targetCorner:Vector3?)
 if not workspaceData then self:clear() return end
 self:_saveFreePositions()
 local free=targetCorner==nil
 local live={}
 self.root.Parent=workspace
 for _,component in pairs(document.components) do
  local state=preview.states[component.id]
  local source=state and state.part
  local sourceModel=preview:getModel(component.id)
  -- Never expose a primitive/placeholder while the initial sketch compiles.
  if not sourceModel or not source or not source.Parent then continue end

  local entry=self.cache[component.id]
  local delta=entry and entry.freeDelta or CFrame.identity
  if entry and entry.source~=source then
   entry.model:Destroy()
   self.cache[component.id]=nil
   entry=nil
  end
  if not entry then
   local model=sourceModel:Clone()
   if not model then continue end
   model.Name=component.name
   model.Parent=self.root
   local solid=model:FindFirstChild("Solid",true)
   if not solid or not solid:IsA("BasePart") then
    model:Destroy()
    continue
   end
   local detector=Instance.new("DragDetector")
   detector.Name="OpenWorks_PhysicalDrag"
   detector.DragStyle=Enum.DragDetectorDragStyle.TranslatePlaneOrLine
   detector.ResponseStyle=Enum.DragDetectorResponseStyle.Physical
   detector.RunLocally=true
   detector.ApplyAtCenterOfMass=false
   detector.Responsiveness=12
   detector.MaxForce=math.clamp(solid:GetMass()*1200,500,100000)
   detector.MaxTorque=math.clamp(solid:GetMass()*900,250,60000)
   detector.Enabled=false
   detector.Parent=solid
   local componentId=component.id
   detector.DragStart:Connect(function()
    if self.mode=="Free" and self.onSelect then
     self.onSelect(componentId)
    end
   end)
   entry={
    model=model,detector=detector,source=source,
    basePivot=model:GetPivot(),freeDelta=delta,
   }
   self.cache[component.id]=entry
  end

  -- All translation from editing into the world uses the original component
  -- workspace origin; player-physics displacement is independent of geometry.
  local origin=component.worldOrigin or workspaceData.worldCorner
  local destination=if free then origin
   else targetCorner+(origin-workspaceData.worldCorner)
  local editOrigin=component.workspaceOrigin or workspaceData.editCorner
  local offset=destination-editOrigin
  local desiredBase=CFrame.new(offset)*sourceModel:GetPivot()
  -- Freeze before moving; otherwise an unanchored body would receive
  -- a large teleport-induced impulse on mode transitions.
  setBodyMode(entry,false)
  entry.model:PivotTo(if free then entry.freeDelta*desiredBase else desiredBase)
  if free then entry.basePivot=desiredBase end
  -- Only OpenWorks components become simulated/draggable. The assembly
  -- stage remains a nonphysical preview until Q3.
  setBodyMode(entry,free)
  live[component.id]=true
 end
 for id,entry in pairs(self.cache) do
  if not live[id] then
   entry.model:Destroy()
   self.cache[id]=nil
  end
 end
 self.mode=if free then "Free" else "Assembly"
end

function WorldProjection:clear()
 self:_saveFreePositions()
 self.mode=nil
 -- Suspend physics while in Edit, preserving its last world-space pose.
 for _,entry in pairs(self.cache) do setBodyMode(entry,false) end
 self.root.Parent=nil
end

function WorldProjection:Destroy()
 self:clear()
 for id,entry in pairs(self.cache) do
  entry.model:Destroy()
  self.cache[id]=nil
 end
 self.root:Destroy()
end
return WorldProjection
