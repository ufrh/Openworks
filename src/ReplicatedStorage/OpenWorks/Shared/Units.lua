-- Physical presentation is isolated from engineering data:
-- 1u = 1000 integer ticks, 1u renders as 0.25 Roblox studs.
local Units = {}

Units.TicksPerUnit = 1000
Units.StudsPerUnit = 0.25
Units.GridStepTicks = 250
Units.DefaultBlockTicks = 4000

function Units.ToStuds(ticks: number): number
    return ticks / Units.TicksPerUnit * Units.StudsPerUnit
end

function Units.ToTicks(studs: number): number
    return math.round(studs / Units.StudsPerUnit * Units.TicksPerUnit)
end

function Units.SnapTicks(ticks: number, stepTicks: number?): number
    local step = stepTicks or Units.GridStepTicks
    return math.round(ticks / step) * step
end

function Units.SnapStuds(studs: number): number
    return Units.ToStuds(Units.SnapTicks(Units.ToTicks(studs)))
end

function Units.IsFinite(value: any): boolean
    return type(value) == "number"
        and value == value and value > -math.huge and value < math.huge
end

return Units
