-- OPENWORKS / LIVE SHAFT-CENTRIC TRANSMISSION SMOKE TEST
-- Run from Roblox Studio's SERVER Command Bar during Play Solo.
-- It creates a completely isolated pair of 20T shafts on passive bearings,
-- drives the input with a native AngularVelocity motor, measures the output,
-- and cleans up. It does not alter your assembly, DataStores, or prefabs.
-- Requires the current dev code to be synced to the running Studio session.
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

assert(RunService:IsStudio() and RunService:IsRunning(),
    "Start Play Solo, then run this from the SERVER Command Bar")
local runtime = ServerScriptService:WaitForChild("Openworks"):WaitForChild("Runtime")
local Transmission = require(runtime:WaitForChild("GearTransmission"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GearMath = require(ReplicatedStorage
    :WaitForChild("Openworks"):WaitForChild("Construction")
    :WaitForChild("GearMath"))
local stock = ReplicatedStorage:FindFirstChild("OPENWORKS_PrimitiveLibrary_DRAFT")
local transmissionFolder=stock and stock:FindFirstChild("Transmission")
local gearTemplate=transmissionFolder and transmissionFolder:FindFirstChild("GearMesh_20T_S03")

local previous = workspace:FindFirstChild("OPENWORKS_TransmissionSmokeTest")
if previous then previous:Destroy() end
local world = Instance.new("Folder")
world.Name = "OPENWORKS_TransmissionSmokeTest"
world.Parent = workspace

local function makePart(name, cf, size, anchored)
    local part = Instance.new("Part")
    part.Name = name
    part.Shape = Enum.PartType.Cylinder
    part.Size = size
    part.CFrame = cf
    part.Anchored = anchored
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Material = Enum.Material.Metal
    part.Parent = world
    return part
end

local function makeModel(name, id, part)
    local model = Instance.new("Model")
    model.Name = name
    model:SetAttribute("InstanceId", id)
    part.Parent = model
    model.PrimaryPart = part
    model.Parent = world
    return model
end

local function setupShaft(suffix, position, color)
    local shaftPart = makePart("Geometry",CFrame.new(position),
        Vector3.new(3.5,0.375,0.375),false)
    shaftPart.Color=color
    local shaft = makeModel("Shaft", "test-shaft-"..suffix, shaftPart)
    shaft:SetAttribute("TemplateId","Shaft")
    local gear, gearPart
    if gearTemplate and gearTemplate:IsA("Model") and gearTemplate.PrimaryPart then
        -- Prefer the REAL precision gear prefab: the test then covers the
        -- current MeshPart pivots, sizing, and physics-root metadata.
        gear=gearTemplate:Clone()
        gear.Name="GearMesh_20T_S03"
        gear:SetAttribute("InstanceId","test-gear-"..suffix)
        gear.Parent=world
        gear:PivotTo(CFrame.new(position))
        gearPart=gear.PrimaryPart
        for _,part in ipairs(gear:GetDescendants()) do
            if part:IsA("BasePart") then
                part.Anchored=false
                part.CanCollide=false -- isolate torque from coarse collision
                part.CanTouch=false
                if part~=gearPart then
                    local internal=Instance.new("WeldConstraint")
                    internal.Name="InternalGearPrefab"
                    internal.Part0=gearPart
                    internal.Part1=part
                    internal.Parent=world
                end
            end
        end
    else
        -- Fallback diagnoses the transmission solver even if the user's
        -- session-scoped mesh assets are not currently generated.
        gearPart = makePart("Geometry",CFrame.new(position),
            Vector3.new(0.60,5.50,5.50),false)
        gearPart.Color = color
        gearPart.Transparency = 0.35
        gear = makeModel("GearMesh_20T_S03","test-gear-"..suffix,gearPart)
        gear:SetAttribute("GearKind","Spur")
        gear:SetAttribute("PrimitiveFamily","Gear")
        gear:SetAttribute("GearTeeth",20)
        gear:SetAttribute("GearModuleStuds",math.pi*0.25)
        gear:SetAttribute("BoreRadiusStuds",0.375)
        gear:SetAttribute("AxialAxis","X")
    end
    local weld = Instance.new("WeldConstraint")
    weld.Name = "RigidHubWeld"
    weld.Part0 = shaftPart
    weld.Part1 = gearPart
    weld.Parent = world
    local support = makePart("FixedBearing",CFrame.new(position),
        Vector3.new(0.2,0.2,0.2),true)
    support.Transparency = 1
    local a0 = Instance.new("Attachment")
    a0.Parent = support
    local a1 = Instance.new("Attachment")
    a1.Parent = shaftPart
    local hinge = Instance.new("HingeConstraint")
    hinge.Name="PassiveBearing"
    hinge.Attachment0 = a0
    hinge.Attachment1 = a1
    hinge.LimitsEnabled = false
    hinge.ActuatorType = Enum.ActuatorType.None
    hinge.Parent = world
    return shaft, gear, shaftPart
end

local y = 30
local pA = Vector3.new(0,y,0)
local pB = Vector3.new(0,y+5,0)
local shaftA,gearA,rootA = setupShaft("A",pA,Color3.fromRGB(80,145,215))
local shaftB,gearB,rootB = setupShaft("B",pB,Color3.fromRGB(224,160,65))
local compatible, reason = GearMath.AutoMeshStatus(gearA,gearB)
assert(compatible,"Gear math rejected an exact 20T S03 mesh: "..tostring(reason))

local graph = {
    models={shaftA,gearA,shaftB,gearB},
    edges={
        {kind="Weld",source=shaftA,target=gearA},
        {kind="Weld",source=shaftB,target=gearB},
    },
}
local copies = {
    ["test-shaft-A"] = shaftA,
    ["test-gear-A"] = gearA,
    ["test-shaft-B"] = shaftB,
    ["test-gear-B"] = gearB,
}
local joints=Instance.new("Folder")
joints.Name="PhysicsJoints"
joints.Parent=world
local transmission = Transmission.new(graph,copies,joints)
assert(transmission.Contacts==1,
    "Expected one shaft-centric gear mesh, detected "..transmission.Contacts)

local motorAttachment=Instance.new("Attachment")
motorAttachment.Parent=rootA
local motor=Instance.new("AngularVelocity")
motor.Name="DiagnosticInputMotor"
motor.Attachment0=motorAttachment
motor.RelativeTo=Enum.ActuatorRelativeTo.World
motor.MaxTorque=2500
motor.AngularVelocity=Vector3.new(2,0,0)
motor.Parent=world

-- Studio Command Bar runs on the server. Release network ownership to
-- keep torque measurement and motor/hinge solver on the same authority.
for _,root in ipairs({rootA,rootB}) do
    pcall(function() root:SetNetworkOwner(nil) end)
end
print("[OPENWORKS][GEAR TEST] 20T/S03 input drive ON; one physical mesh detected / "
    .. (if gearTemplate then "REAL precision prefab" else "fallback mock gear"))

local started=os.clock()
local bestA,bestB=0,0
local traceInterval=0
local ok, failure=pcall(function()
    while os.clock()-started<3.0 do
        local dt=RunService.Heartbeat:Wait()
        transmission:Step(dt)
        local a=rootA.AssemblyAngularVelocity.X
        local b=rootB.AssemblyAngularVelocity.X
        bestA=math.max(bestA,a)
        bestB=math.min(bestB,b)
        traceInterval+=dt
        if traceInterval>0.75 then
            traceInterval=0
            print(string.format("[OPENWORKS][GEAR TEST] Input %+0.3f rad/s | Output %+0.3f rad/s | contacts %d",
                a,b,transmission.Contacts))
        end
    end
end)
transmission:StopMotion()
world:Destroy()
if not ok then error("[OPENWORKS][GEAR TEST] Studio test errored: "..tostring(failure)) end
if bestA>0.25 and bestB< -0.25 then
    print(string.format("[OPENWORKS][GEAR TEST] PASS: real native physics drove the output shaft (input %.2f, output %.2f)",
        bestA,bestB))
else
    warn(string.format("[OPENWORKS][GEAR TEST] FAIL: input %.2f / output %.2f. Check passive bearing, AngularVelocity, transmission Torque, and network ownership.",bestA,bestB))
end
