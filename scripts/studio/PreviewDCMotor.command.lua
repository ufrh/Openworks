-- Paste this entire script into Roblox Studio's EDIT-mode Command Bar
-- after syncing OpenWorks dev. Generates a preview AND registers DCMotor
-- in OPENWORKS_PrimitiveLibrary_DRAFT/Actuators.
-- IMPORTANT: temporary preview content is NOT a permanent mesh asset.
local AssetService = game:GetService("AssetService")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerScriptService")
local Geometry = require(RS.Openworks.Construction.MotorMeshGeometry)
local MotorLibrary = require(SS.Openworks.Runtime.MotorLibrary)
local prefab = MotorLibrary.Ensure(true)
local published = prefab:GetAttribute("PublishedMotorVisual") == true
if not published then
    local palette = {
        RearCan = Color3.fromRGB(118,126,132),
        Housing = Color3.fromRGB(187,190,191),
        Endbell = Color3.fromRGB(150,158,163),
    }
    local prepared = {}
    local ok,reason = pcall(function()
        for _,key in ipairs(Geometry.Keys) do
            local mesh,tris = Geometry.Build(key)
            local baked,status,staticContent = pcall(function()
                return AssetService:CreateDataModelContentAsync(Content.fromObject(mesh))
            end)
            mesh:Destroy()
            assert(baked and status==Enum.CreateContentResult.Success and staticContent,
                "Motor preview bake failed for "..key..": "..tostring(status))
            local part = AssetService:CreateMeshPartAsync(staticContent, {
                CollisionFidelity=Enum.CollisionFidelity.Box,
                RenderFidelity=Enum.RenderFidelity.Precise,
            })
            part.Name="Visual_"..key
            part.CFrame=CFrame.new(Geometry.Offsets[key])
            part.Color=palette[key]
            part.Material=Enum.Material.Metal
            part.DoubleSided=false
            part.Anchored=true
            part.CanCollide=false
            part.CanQuery=false
            part.CanTouch=false
            part.Massless=true
            part:SetAttribute("OpenworksCollisionMode","VisualOnly")
            part:SetAttribute("OpenworksKeepFactoryAppearance",true)
            table.insert(prepared,part)
            print("[OW MOTOR] "..key.." | "..tris.." triangles | volume + normals")
        end
    end)
    if not ok then
        for _,part in ipairs(prepared) do part:Destroy() end
        error("Motor mesh authoring failed: "..tostring(reason))
    end
    for _,part in ipairs(prefab:GetChildren()) do
        if part.Name:match("^Fallback") then part:Destroy() end
    end
    for _,part in ipairs(prepared) do part.Parent=prefab end
    print("[OW MOTOR] Detailed temporary EditableMesh prefab installed in Actuators.")
    print("[OW MOTOR] Use the Publish DC Motor Studio plugin before relying on saved assets.")
end
local old=workspace:FindFirstChild("OW_Motor_EditableMesh_Prototype")
if old then old:Destroy() end
local shown=prefab:Clone()
shown.Name="OW_Motor_EditableMesh_Prototype"
shown.Parent=workspace
shown:PivotTo(CFrame.new(0,8,0))
print("[OW MOTOR] View model in Workspace. Real primitive: ReplicatedStorage/"
    .."OPENWORKS_PrimitiveLibrary_DRAFT/Actuators/DCMotor")
