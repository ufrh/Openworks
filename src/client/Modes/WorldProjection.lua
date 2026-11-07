--!strict
-- Cached client-only world/assembly representations. Original FORM meshes
-- remain in Edit coordinates; this service never moves their source Parts.
-- Hide instead of cloning and destroying every time a mode changes.
local WorldProjection={}
WorldProjection.__index=WorldProjection
function WorldProjection.new()
 local root=Instance.new("Folder")
 root.Name="OPENWORKS_LocalWorldComponents"
 -- Remain unparented until a mode needs projections.
 return setmetatable({root=root,cache={}},WorldProjection)
end
function WorldProjection:show(preview:any,document:any,workspaceData:any,targetCorner:Vector3?)
 if not workspaceData then self:clear() return end
 self.root.Parent=workspace
 local live={}
 for _,component in pairs(document.components) do
  local sourceModel=preview:getModel(component.id)
  if not sourceModel then continue end
  local state=preview.states[component.id]
  local currentPart=state and state.part
  local key=tostring(component.revision)..":"..tostring(state and state.key)
  local cached=self.cache[component.id]
  if cached and (cached.source~=currentPart or cached.key~=key) then
   cached.model:Destroy()
   cached=nil
   self.cache[component.id]=nil
  end
  if not cached then
   local clone=sourceModel:Clone()
   if not clone then continue end
   clone.Name=component.name
   clone.Parent=self.root
   for _,part in ipairs(clone:GetDescendants()) do
    if part:IsA("BasePart") then
     part.Anchored=true
     part.CanCollide=false
     part.CanQuery=false -- Do not intercept Free-mode ground grid raycasts
     part.CanTouch=false
     part.CastShadow=true
    end
   end
   cached={model=clone,source=currentPart,key=key,offset=Vector3.zero}
   self.cache[component.id]=cached
  end
  local origin=component.worldOrigin or workspaceData.worldCorner
  local destination=if targetCorner
   then targetCorner+(origin-workspaceData.worldCorner)
   else origin
  local offset=destination-(component.workspaceOrigin or workspaceData.editCorner)
  local change=offset-cached.offset
  if change.Magnitude>1e-7 then
   local shift=CFrame.new(change)
   for _,part in ipairs(cached.model:GetDescendants()) do
    if part:IsA("BasePart") then part.CFrame=shift*part.CFrame end
   end
   cached.offset=offset
  end
  live[component.id]=true
 end
 for id,entry in pairs(self.cache) do
  if not live[id] then entry.model:Destroy() self.cache[id]=nil end
 end
end
function WorldProjection:clear()
 -- Mode exit should never synchronously destroy large manufactured meshes.
 self.root.Parent=nil
end
function WorldProjection:Destroy()
 for id,entry in pairs(self.cache) do
  entry.model:Destroy()
  self.cache[id]=nil
 end
 self.root:Destroy()
end
return WorldProjection
