--!strict
-- Free Mode uses the standard Roblox character camera at a fixed distance.
-- Only the character camera's zoom is locked; CAD cameras have their own lens.
local Players=game:GetService("Players")
local FreeMode={}
FreeMode.__index=FreeMode
local FIXED_ZOOM=12
function FreeMode.new(bridge:any)
 return setmetatable({bridge=bridge,savedZoom=nil,elapsed=0},FreeMode)
end
function FreeMode:Enter(_context:any)
 self.bridge.enterFree()
 local player=Players.LocalPlayer
 if not self.savedZoom then
  self.savedZoom={min=player.CameraMinZoomDistance,max=player.CameraMaxZoomDistance}
 end
 -- Respect Roblox's min <= max invariant while setting the fixed range.
 player.CameraMinZoomDistance=math.min(player.CameraMinZoomDistance,FIXED_ZOOM)
 player.CameraMaxZoomDistance=FIXED_ZOOM
 player.CameraMinZoomDistance=FIXED_ZOOM
end
function FreeMode:Exit()
 if not self.savedZoom then return end
 local player=Players.LocalPlayer
 local limits=self.savedZoom
 -- Raise max before min to avoid clamping a restored larger minimum.
 player.CameraMaxZoomDistance=math.max(limits.max,limits.min,FIXED_ZOOM)
 player.CameraMinZoomDistance=limits.min
 player.CameraMaxZoomDistance=limits.max
 self.savedZoom=nil
end
function FreeMode:Update(dt:number)
 self.elapsed+=dt
 if self.elapsed>=.8 then
  self.elapsed=0
  if self.bridge.refreshFree then self.bridge.refreshFree() end
 end
end
return FreeMode
