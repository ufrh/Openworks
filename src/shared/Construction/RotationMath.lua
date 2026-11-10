--!strict
-- Explicit world-axis 90-degree rotations around geometric body centers.
-- Do not accumulate player turns as local Euler angles.
local Grid = require(script.Parent:WaitForChild("GridMath"))
local RotationMath = {}
local AXES = {X=Vector3.xAxis,Y=Vector3.yAxis,Z=Vector3.zAxis}

function RotationMath.Axis(name)
    return AXES[name]
end

function RotationMath.MatchSteps(rotation)
    for x=0,3 do
        for y=0,3 do
            for z=0,3 do
                local steps={x=x,y=y,z=z}
                local r=Grid.Rotation(steps)
                if r.RightVector:Dot(rotation.RightVector)>0.99999
                    and r.UpVector:Dot(rotation.UpVector)>0.99999 then
                    return steps
                end
            end
        end
    end
    return nil
end

function RotationMath.Delta(axisName,direction,center)
    local axis=AXES[axisName]
    if not axis or (direction~=1 and direction~=-1) then return nil end
    return CFrame.new(center)
        * CFrame.fromAxisAngle(axis,direction*math.pi/2)
        * CFrame.new(-center)
end

function RotationMath.RotateCF(cf,axisName,direction,center)
    local delta=RotationMath.Delta(axisName,direction,center)
    return if delta then delta*cf else nil
end

return table.freeze(RotationMath)
