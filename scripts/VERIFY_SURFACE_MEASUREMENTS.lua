--!strict
-- Run during Studio Play in the CLIENT Command Bar.
-- Exercises read-only surface measurements without requiring CSG.
local Players=game:GetService("Players")
local player=Players.LocalPlayer
assert(player,"Run in the client Command Bar during Play")
local Measurements=require(player:WaitForChild("PlayerScripts")
	:WaitForChild("Openworks"):WaitForChild("SurfaceMeasurements"))
local overlay=Measurements.new(player:WaitForChild("PlayerGui"))
local part=Instance.new("Part")
part.Name="FORM_DimensionTest"
part.Size=Vector3.new(2,1,3)
part.CFrame=CFrame.new(0,5,0)
part.Anchored=true
part.Parent=workspace
local top={
	id=1,normal=Vector3.yAxis,
	polygon={
		Vector3.new(-1,0.5,-1.5),
		Vector3.new(1,0.5,-1.5),
		Vector3.new(1,0.5,1.5),
		Vector3.new(-1,0.5,1.5),
	}
}
local ok,problem=pcall(function()
	assert(overlay:show(part,top),"Top face failed to render")
	assert(overlay.part==part and overlay.lineCount>=12)
	assert(overlay.widthBadge.gui.Enabled and overlay.heightBadge.gui.Enabled)
	local a=overlay.widthBadge.label.Text
	local b=overlay.heightBadge.label.Text
	assert((a=="840 mm" and b=="560 mm")
		or (a=="560 mm" and b=="840 mm"),
		"Surface labels don't match 2×3 studs in millimeters: "..a.." "..b)
	local before=overlay.guides[1].CFrame.Position
	part.CFrame=CFrame.new(5,8,2)*CFrame.Angles(0,math.rad(20),0)
	assert(overlay:show(part,top),"Rotated surface failed to render")
	assert((overlay.guides[1].CFrame.Position-before).Magnitude>1,
		"Surface overlay didn't follow component rotation/translation")
	assert(not overlay:show(part,{curved=true,polygon=top.polygon}),
		"Curved faces should not report arbitrary planar dimensions")
	assert(overlay.part==nil and not overlay.widthBadge.gui.Enabled)
	assert(overlay:show(part,top))
	overlay:hide()
	assert(overlay.lineCount==0)
	assert(not overlay.heightBadge.gui.Enabled)
	for _,line in ipairs(overlay.guides) do
		assert(not line.Visible,"Dimension guide leaked after hover ended")
	end
	assert(overlay.origin.CanQuery==false
		and not overlay.origin.CanCollide,
		"Hover guides must never intercept material raycasts or physics")
end)
overlay:destroy()
part:Destroy()
assert(ok,tostring(problem))
print("FORM Surface Measurements: planar face, mm extents, rotation, curved hide and cleanup passed")
