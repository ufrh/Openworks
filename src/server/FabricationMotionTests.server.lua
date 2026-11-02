local StarterPlayer = game:GetService('StarterPlayer')
local scripts = StarterPlayer:WaitForChild('StarterPlayerScripts'):WaitForChild('Openworks')
local Motion = require(scripts:WaitForChild('FabricationMotion'))

local ring = {
    Vector3.new(0, 0.5, -2),
    Vector3.new(0, 0.5, 2),
    Vector3.new(0, -0.5, 2),
    Vector3.new(0, -0.5, -2),
}
local guide = {ring = ring, normal = Vector3.xAxis}
local plan, reason = Motion.sawPlan(guide, Vector3.new(0, 0.5, 0), Vector3.yAxis)
assert(plan, 'Cannot construct sample saw travel: ' .. tostring(reason))
assert(math.abs(plan.across - 4) < 0.001 and math.abs(plan.span - 1) < 0.001,
    'Saw travel must cover the cut width and material depth')

local enter = Motion.sawPose(plan, 0, 0)
local middle = Motion.sawPose(plan, 0.5, 0)
local exit = Motion.sawPose(plan, 1, 0)
assert((middle.Position - enter.Position):Dot(plan.forward) > 1,
    'Saw must feed forward along the planned cut')
assert((exit.Position - middle.Position):Dot(plan.forward) > 1,
    'Saw must continue feeding to the far side of the cut')
assert((exit.Position - enter.Position):Dot(plan.outward) < -plan.span,
    'Saw must penetrate the workpiece in addition to the forward feed')

local stroke = Motion.sawPose(plan, 0.5, math.pi / 2)
assert(math.abs((stroke.Position - middle.Position):Dot(plan.forward) - plan.stroke) < 0.0001,
    'Saw stroke must overlay forward travel without replacing feed')
assert((middle.RightVector - plan.forward).Magnitude < 0.0001,
    'Saw local +X axis must follow its blade stroke')
assert((middle.UpVector - plan.outward).Magnitude < 0.0001,
    'Saw local +Y axis must point outward from the metal')

print(string.format('[FABRICATION MOTION] Passed: %.2f stud cut feed, %.2f stud penetration, independent reciprocating stroke',
    plan.across, plan.span))
