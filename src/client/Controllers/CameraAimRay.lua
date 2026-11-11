--!strict
-- OPENWORKS locked-mouse freecam always aims through screen center.
-- This single ray is shared by Build, Edit, Assembly, Simulate and crank.
local Aim={}
function Aim.Ray(camera:Camera):Ray
    local center=camera.ViewportSize*0.5
    return camera:ViewportPointToRay(center.X,center.Y)
end
return table.freeze(Aim)
