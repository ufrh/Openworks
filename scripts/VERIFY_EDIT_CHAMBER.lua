--!strict
-- Run on the Studio CLIENT command bar after syncing OpenWorks.
local Players=game:GetService("Players")
local client=Players.LocalPlayer.PlayerScripts:WaitForChild("Openworks")
local Environment=require(client.Modes.EditEnvironment)
local Workspace=require(client.Modes.EditWorkspace)
local BlenderCamera=require(client.Experience.Cameras.BlenderCamera)
local room=Environment.new()
room:show()
local center,size=Environment.Center,Environment.Size
assert(size==Vector3.new(40,20,40),"Fixed chamber dimension changed")
local floor=room.root:FindFirstChild("ChamberFloor")
local ceiling=room.root:FindFirstChild("BlueCeiling")
assert(floor and ceiling,"Six-sided Edit Chamber is missing its floor or roof")
assert(math.abs(floor.Position.Y-(center.Y-size.Y/2))<0.001,
 "Construction grid should not sit on the chamber floor")
assert(math.abs(ceiling.Position.Y-(center.Y+size.Y/2))<0.001,
 "Ceiling must be above the workspace by half the room height")
local sealed={ChamberFloor=1,BlueCeiling=1,BlueWallX=2,BlueWallZ=2}
for name,expected in pairs(sealed) do
 local found=0
 for _,part in ipairs(room.root:GetChildren()) do
  if part.Name==name then
   found+=1
   assert(part.Transparency==0,"Chamber surface is not opaque: "..name)
   assert(not part.CastShadow and not part.CanCollide and not part.CanQuery)
  end
 end
 assert(found==expected,"Sealed room has an opening at "..name)
end
local work=Workspace.new(Vector3.new(18,0,10),
 Vector3.new(2,1,3),"Centered test")
assert(work.center==center and math.abs(work.editCorner.Y-center.Y)<1e-5,
 "Grid must be at the exact vertical midpoint of the chamber")
local camera=BlenderCamera.new(function()end,function()end)
camera:setFocusTarget(center)
camera:setRoomBounds(center,size)
camera:setView("Top")
camera:frameBounds(CFrame.new(center),Vector3.new(2,0.05,3))
camera:zoom(999)
assert(camera.distance<=size.Y/2-0.79,
 "Top-down Edit camera can escape behind the sealed ceiling")
camera:destroy()
room:Destroy()
print("OPENWORKS EDIT CHAMBER PASS: centered workspace, opaque six sides, camera zoom confinement")
