-- OPENWORKS / LIVE SHAFT-TO-HOLE SMART-FIT SMOKE TEST
-- Run from Roblox Studio's SERVER Command Bar during Play Solo.
-- Builds disposable test copies well above the plot. Does not modify saves,
-- the player's own construction, or mechanical relationships.
local RunService=game:GetService("RunService")
assert(RunService:IsStudio() and RunService:IsRunning(),
    "Start Play Solo, then run this from the SERVER Command Bar")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Construction=ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction")
local Registry=require(Construction:WaitForChild("PrimitiveRegistry"))
local Smart=require(Construction:WaitForChild("SmartPlacement"))
local Alignment=require(Construction:WaitForChild("AlignmentMath"))
local Bore=require(Construction:WaitForChild("BoreClearance"))
local MultiFit=require(Construction:WaitForChild("MultiFitMath"))
local Grid=require(Construction:WaitForChild("GridMath"))

local function template(name)
    local entry=Registry.Get(name)
    assert(entry and entry.Model and entry.Model.PrimaryPart,
        "Missing registered primitive: "..name)
    return entry.Model
end
local old=workspace:FindFirstChild("OPENWORKS_BoreSnapSmokeTest")
if old then old:Destroy() end
local world=Instance.new("Folder")
world.Name="OPENWORKS_BoreSnapSmokeTest"
world.Parent=workspace

local function spawn(name,position,id)
    local model=template(name):Clone()
    model:SetAttribute("TemplateId",name)
    model:SetAttribute("InstanceId",id)
    model.Parent=world
    model:PivotTo(CFrame.new(position))
    return model
end
local home=Vector3.new(0,180,0)
local ok,err=pcall(function()
    local shaft=spawn("Shaft",home+Vector3.new(0.12,0,0),
        "OPENWORKS_Preflight")
    local hole=spawn("DrilledBlock_1U_D098",home,
        "bore-test-hole")
    assert(Alignment.IsShaft(shaft),"Default Shaft must be recognized")
    assert(Alignment.TargetAxis(shaft)==nil,
        "A solid Shaft must not report AxialAxis as a hollow opening")
    assert(Alignment.TargetAxis(hole)~=nil,
        "Drilled block must report a real bore axis")
    assert(Bore.CanInsert(shaft,hole),
        "Dedicated 0.95U Shaft must fit default 0.98U hole")

    local match=Smart.Find(shaft,{hole},nil,nil,nil,{hole},hole)
    assert(match and match.kind=="Bore" and not match.reverse,
        "Default shaft/hole did NOT produce a forward Bore snap")
    shaft:PivotTo(match.cf)
    assert(Bore.ShaftFits(shaft,hole),
        "Forward snap pose failed actual bore clearance after positioning")
    assert(MultiFit.Check(shaft,hole),
        "Forward snap is missing a verified shaft/hole pair")
    print("[OPENWORKS][BORE TEST] PASS: dedicated Shaft -> drilled hole")

    local reverseHole=spawn("DrilledBlock_1U_D098",
        home+Vector3.new(4,0,0.12),"OPENWORKS_Preflight")
    local fixedShaft=spawn("Shaft",home+Vector3.new(4,0,0),
        "bore-test-fixed-shaft")
    local reversed=Smart.Find(reverseHole,{fixedShaft},nil,nil,
        nil,{fixedShaft},fixedShaft)
    assert(reversed and reversed.kind=="Bore" and reversed.reverse,
        "Drilled hole -> fixed Shaft did NOT produce reverse Bore snap")
    reverseHole:PivotTo(reversed.cf)
    assert(Bore.ShaftFits(fixedShaft,reverseHole)
        and MultiFit.Check(reverseHole,fixedShaft),
        "Reverse Bore snap failed physical geometry checks")
    print("[OPENWORKS][BORE TEST] PASS: drilled hole -> fixed shaft")

    local cylinderEntry=Registry.Get("Cylinder")
    if cylinderEntry and cylinderEntry.Model and cylinderEntry.Model.PrimaryPart then
        local cylinder=spawn("Cylinder",home+Vector3.new(8,0.12,0),
            "OPENWORKS_Preflight")
        local drilled=spawn("DrilledBlock_1U_D098",
            home+Vector3.new(8,0,0),"bore-test-snug")
        local originalDiameter=math.max(
            cylinder.PrimaryPart.Size.Y,cylinder.PrimaryPart.Size.Z)
        local auto=Smart.Find(cylinder,{drilled},nil,nil,nil,{drilled},drilled)
        assert(auto and auto.kind=="Bore",
            "Generic Cylinder did not acquire the default drilled opening")
        cylinder:PivotTo(auto.cf)
        assert(Bore.ShaftFits(cylinder,drilled),
            "Near-fit cylinder did not fit after auto-snug")
        if originalDiameter>=Bore.OpeningDiameter(drilled) then
            assert(type(auto.snugDiameter)=="number",
                "Overwide default Cylinder did not request snug sizing")
            local u=auto.snugDiameter/Grid.Unit
            assert(math.abs(u*20-math.round(u*20))<0.0001,
                "Auto-snug diameter is not on the server's 0.05U grid")
        end
        print("[OPENWORKS][BORE TEST] PASS: generic Cylinder -> drilled hole")
    else
        print("[OPENWORKS][BORE TEST] SKIP: no legacy Cylinder template")
    end
end)
world:Destroy()
if not ok then error("[OPENWORKS][BORE TEST] FAIL: "..tostring(err),0) end
print("[OPENWORKS][BORE TEST] All live snap geometry checks passed")
