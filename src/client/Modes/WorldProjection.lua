--!strict
-- Client-local physical bodies in Free Mode. FORM's authoritative CAD mesh
-- stays in Edit coordinates; this layer owns separate world/assembly copies.
-- Q2/Q4 will replace this local representation with server-owned bodies.
local Players=game:GetService("Players")
local WorldProjection={}
WorldProjection.__index=WorldProjection

local function setBodyMode(entry:any,simulated:boolean)
 for _,part in ipairs(entry.model:GetDescendants()) do
  if part:IsA("BasePart") then
   part.Anchored=not simulated
   part.CanCollide=simulated
   part.CanTouch=simulated
   part.CanQuery=simulated
   if simulated then
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
 if entry.detector then entry.detector.Enabled=simulated end
end

function WorldProjection.new(onSelect:((number)->())?)
 local root=Instance.new("Folder")
 root.Name="OPENWORKS_LocalWorldComponents"
 return setmetatable({
  root=root,cache={},published={},mode=nil,onSelect=onSelect,
 },WorldProjection)
end

function WorldProjection:_savePositions()
 if self.root.Parent==nil then return end
 for _,entry in pairs(self.cache) do
  if entry.model.Parent==self.root then
   -- Store displacement/rotation relative to the component's *unmoved*
   -- world pose, so a recompilation can replace the solid in place.
   if self.mode=="Free" and entry.basePivot then
    entry.freeDelta=entry.model:GetPivot()*entry.basePivot:Inverse()
   elseif self.mode=="Assembly" and entry.stageBasePivot then
    entry.stageDelta=entry.model:GetPivot()*entry.stageBasePivot:Inverse()
   end
  end
 end
end

function WorldProjection:show(preview:any,document:any,workspaceData:any,
 targetCorner:Vector3?,simulateAssembly:boolean?)
 if not workspaceData then self:clear() return end
 self:_savePositions()
 local free=targetCorner==nil
 local simulated=free or simulateAssembly==true
 local live={}
 self.root.Parent=workspace
 local serverRoot=workspace:FindFirstChild("OPENWORKS_Published")
 local serverBucket=serverRoot and
  serverRoot:FindFirstChild(tostring(Players.LocalPlayer.UserId))
 for _,component in pairs(document.components) do
  -- Prefer replicated server-owned physics to local cloned Free bodies.
  local replicated=if free and serverBucket then
   serverBucket:FindFirstChild("Component_"..component.id) else nil
  if replicated and replicated:IsA("BasePart") then
   local prior=self.cache[component.id]
   if prior then prior.model:Destroy() self.cache[component.id]=nil end
   local tracked=self.published[component.id]
   if not tracked or tracked.part~=replicated or not tracked.connection then
    if tracked and tracked.connection then tracked.connection:Disconnect() end
    local detector=replicated:FindFirstChildOfClass("DragDetector")
    local connection=if detector then detector.DragStart:Connect(function()
     if self.mode=="Free" and self.onSelect then
      self.onSelect(component.id,"Free")
     end
    end) else nil
    self.published[component.id]={part=replicated,connection=connection}
   end
   live[component.id]=true
   continue
  end
  local state=preview.states[component.id]
  local source=state and state.part
  local sourceModel=preview:getModel(component.id)
  -- Never expose a primitive/placeholder while the initial sketch compiles.
  if not sourceModel or not source or not source.Parent then continue end

  local entry=self.cache[component.id]
  local delta=entry and (if free then entry.freeDelta else entry.stageDelta)
   or CFrame.identity
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
    if (self.mode=="Free" or self.mode=="Assembly") and self.onSelect then
     self.onSelect(componentId,self.mode)
    end
   end)
   entry={
    model=model,detector=detector,source=source,
    basePivot=model:GetPivot(),freeDelta=if free then delta else CFrame.identity,
    stageBasePivot=model:GetPivot(),stageDelta=if not free then delta else CFrame.identity,
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
  -- On an unchanged Free body, leave physics completely untouched. Other
  -- CSG jobs finishing must not interrupt an active physical drag.
  local matchingMode=self.mode==(if free then "Free" else "Assembly")
  local sameBase=if free then entry.basePivot==desiredBase
   else entry.stageBasePivot==desiredBase
  if not (matchingMode and simulated and entry.detector.Enabled and sameBase) then
   -- Freeze before moving; otherwise teleporting an unanchored body
   -- between the world and Assembly would inject unwanted impulses.
   setBodyMode(entry,false)
   entry.model:PivotTo(delta*desiredBase)
   if free then entry.basePivot=desiredBase
   else entry.stageBasePivot=desiredBase end
   setBodyMode(entry,simulated)
  end
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
 self:_savePositions()
 self.mode=nil
 -- Suspend physics while in Edit, preserving its last world-space pose.
 for _,entry in pairs(self.cache) do setBodyMode(entry,false) end
 self.root.Parent=nil
end

function WorldProjection:Destroy()
 self:clear()
 for _,item in pairs(self.published) do
  if item.connection then item.connection:Disconnect() end
 end
 table.clear(self.published)
 for id,entry in pairs(self.cache) do
  entry.model:Destroy()
  self.cache[id]=nil
 end
 self.root:Destroy()
end
return WorldProjection
