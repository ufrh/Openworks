-- OPENWORKS | V4 DC MOTOR MANUAL EXPORT STAGING (NO PLUGIN)
-- Run AFTER PreviewDCMotor.command.lua in Studio Edit mode.
-- Creates six MeshPart copies at the WORLD ORIGIN for individual OBJ export.
-- Each copy has CFrame.identity to avoid baking the preview's (0,8,0)
-- placement or the original section transform into uploaded vertex coordinates.
local src=workspace:FindFirstChild("OW_Motor_EditableMesh_Prototype")
    or workspace:FindFirstChild("OW_DC_Motor_V4")
assert(src and src:IsA("Model"),
    "Generate the V4 Workspace motor preview first")
local old=workspace:FindFirstChild("OW_Motor_ManualExports")
if old then old:Destroy() end
local out=Instance.new("Folder")
out.Name="OW_Motor_ManualExports"
out.Parent=workspace

local names={"RearCan","Armature","Housing","Endbell","Bearing","Bushing"}
for _,key in ipairs(names) do
    local source=src:FindFirstChild("Visual_"..key)
        or src:FindFirstChild(({
            RearCan="01_RearSteelCan",
            Armature="02_Armature",
            Housing="03_MainHousing",
            Endbell="04_FrontEndbell",
            Bearing="05_BearingCollar",
            Bushing="06_BrassBushing",
        })[key])
    assert(source and source:IsA("MeshPart"),
        "Missing mesh section "..key.."; rebuild detailed V4 preview")
    local copy=source:Clone()
    copy.Name=key.."_EXPORT_OBJ"
    copy.CFrame=CFrame.identity
    copy.CanCollide=false
    copy.CanQuery=false
    copy.Anchored=true
    copy.Parent=out
end
print("[OW MOTOR] Six export sections staged at Workspace.OW_Motor_ManualExports")
print("[OW MOTOR] Export each *_EXPORT_OBJ separately as a .obj file.")
print("[OW MOTOR] Import with Scale Unit=Studs and no axis correction.")
print("[OW MOTOR] Record each imported MESH asset ID, not the overall model ID.")
