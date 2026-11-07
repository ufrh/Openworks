--!strict
local Environment={}
Environment.__index=Environment
Environment.Center=Vector3.new(120,200,0)
function Environment.new() return setmetatable({root=nil},Environment) end
function Environment:show()
 if self.root then return end
 local root=Instance.new("Folder")
 root.Name="OPENWORKS_LocalAssemblyStage"
 root.Parent=workspace
 local floor=Instance.new("Part")
 floor.Name="AssemblyStageFloor"
 floor.Size=Vector3.new(80,.1,80)
 floor.Position=Environment.Center-Vector3.new(0,.08,0)
 floor.Anchored=true
 floor.CanCollide=false
 floor.CanQuery=false
 floor.CanTouch=false
 floor.CastShadow=false
 floor.Color=Color3.fromRGB(28,37,43)
 floor.Material=Enum.Material.SmoothPlastic
 floor.Parent=root
 self.root=root
end
function Environment:hide()
 if self.root then self.root:Destroy() self.root=nil end
end
function Environment:Destroy() self:hide() end
return Environment
