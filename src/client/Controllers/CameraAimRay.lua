--!strict
-- One aim ray for native free-cursor construction and held RMB/MMB camera.
-- ScreenPointToRay includes Roblox's top-bar inset for actual cursor
-- positions; the locked-pointer mode retains the precise center aim.
local UIS=game:GetService("UserInputService")
local Aim={}
function Aim.Ray(camera:Camera):Ray
    if UIS.MouseBehavior==Enum.MouseBehavior.LockCenter then
        local center=camera.ViewportSize*0.5
        return camera:ViewportPointToRay(center.X,center.Y)
    end
    local mouse=UIS:GetMouseLocation()
    return camera:ScreenPointToRay(mouse.X,mouse.Y)
end
return table.freeze(Aim)
