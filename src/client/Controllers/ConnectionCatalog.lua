--!strict
-- UI v2 Phase 4: one source of truth for connection *choices*.
-- The server remains authoritative for fit, overlap, clearance and materials.
-- This table filters only obvious incompatible UI choices; it does not
-- predict or bypass any physical validation.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local construction=ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("Construction")
local Alignment=require(construction:WaitForChild("AlignmentMath"))
local HandCrankMath=require(construction:WaitForChild("HandCrankMath"))
local Catalog={}

local LABELS={
    Bearing="Bearing · rotate",
    Slider="Slider · translate",
    Cylindrical="Cylindrical · rotate + slide",
    FreeFit="Fit only · no joint",
    Weld="Rigid weld",
    Spring="Spring",
    Bolt="Insert fitted bolt",
    CrankCoupling="Couple hand crank",
    Rotation="Independent gear mount",
    Rigid="Rigid gear mount",
    Adjust="Adjust depth / roll",
}
Catalog.Labels=table.freeze(LABELS)

function Catalog.Fit(kind)
    if kind=="Hub" then return {
        {id="Rotation",label=LABELS.Rotation},
        {id="Rigid",label=LABELS.Rigid},
    } end
    return {
        {id="Cylindrical",label=LABELS.Cylindrical},
        {id="Slider",label=LABELS.Slider},
        {id="Bearing",label=LABELS.Bearing},
        {id="FreeFit",label=LABELS.FreeFit},
        {id="__Adjust",label=LABELS.Adjust},
    }
end

function Catalog.Pair(first,second)
    if not first or not second or first==second then return {} end
    local options={}
    local function add(id)
        table.insert(options,{id=id,label=LABELS[id]})
    end
    local shaft=if Alignment.IsShaft(first) then first
        else if Alignment.IsShaft(second) then second else nil
    local hole=if shaft==first then second else first
    local bore=shaft~=nil and hole~=nil
        and Alignment.TargetAxis(hole)~=nil
    local gear=if first:GetAttribute("GearTeeth")~=nil then first
        else if second:GetAttribute("GearTeeth")~=nil then second else nil
    local axle=if gear==first then second else first
    local hub=gear~=nil and axle~=nil and Alignment.IsShaft(axle)
    -- One physically selected pair; prioritize types for matching hardware.
    if hub then
        add("Rotation")
        add("Rigid")
    elseif bore then
        add("Cylindrical")
        add("Bearing")
        add("Slider")
        add("FreeFit")
    end
    local crank=if HandCrankMath.IsCrank(first) then first
        else if HandCrankMath.IsCrank(second) then second else nil
    if crank and Alignment.IsShaft(if crank==first then second else first) then
        add("CrankCoupling")
    end
    if Alignment.TargetAxis(first) and Alignment.TargetAxis(second) then
        add("Bolt")
    end
    if not crank then
        add("Weld")
        add("Spring")
    end
    return options
end

function Catalog.Roles(first,second)
    local shaft=if Alignment.IsShaft(first) then first
        else if Alignment.IsShaft(second) then second else nil
    local opening=if shaft==first then second else first
    local gear=if first:GetAttribute("GearTeeth")~=nil then first
        else if second:GetAttribute("GearTeeth")~=nil then second else nil
    local axle=if gear==first then second else first
    local crank=if HandCrankMath.IsCrank(first) then first
        else if HandCrankMath.IsCrank(second) then second else nil
    return {
        shaft=shaft,opening=opening,gear=gear,axle=axle,
        crank=crank,crankShaft=if crank==first then second else first,
    }
end

return table.freeze(Catalog)
