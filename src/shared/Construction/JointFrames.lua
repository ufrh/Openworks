--!strict
-- A joint's axis and its roll reference MUST both come from the housing.
-- Using global up to choose the transverse direction makes local-Y
-- DrilledBlock joints flip when the entire housing is rotated.
local Alignment = require(script.Parent:WaitForChild("AlignmentMath"))
local JointFrames = {}

function JointFrames.ForOpening(target: Model): CFrame?
    local localAxis = Alignment.TargetAxis(target)
    if not localAxis then return nil end

    -- Construct an orthonormal X-axis frame in the HOUSING LOCAL SPACE.
    -- The native Hinge/Prismatic constraint operates along Attachment.Axis X.
    local transverse
    if localAxis == Vector3.xAxis or localAxis == -Vector3.xAxis then
        transverse = Vector3.yAxis
    elseif localAxis == Vector3.yAxis or localAxis == -Vector3.yAxis then
        transverse = Vector3.zAxis
    else
        transverse = Vector3.xAxis
    end

    local x = localAxis.Unit
    local y = (transverse - x * x:Dot(transverse)).Unit
    local z = x:Cross(y)
    local localFrame = CFrame.fromMatrix(Vector3.zero, x, y, z)
    return target:GetPivot() * localFrame
end

return table.freeze(JointFrames)
