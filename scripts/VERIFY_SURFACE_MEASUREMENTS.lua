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
	assert(overlay:show(part,top,Vector3.new(-0.99,5.5,-1.49)),
		"Top face failed to render")
	assert(overlay.part==part and overlay.cursorDot.Enabled)
	assert(overlay.widthBadge==nil and overlay.heightBadge==nil,
		"Surface X/Y labels must not exist")
	local nearLines=overlay.lineCount
	local nearCursor=overlay.cursorAnchor.Position
	assert(overlay:show(part,top,Vector3.new(-0.989,5.5,-1.489)))
	assert((overlay.cursorAnchor.Position-nearCursor).Magnitude<1e-6,
		"Submillimeter pointer drift should remain snapped")
	assert(overlay:show(part,top,Vector3.new(-0.5,5.5,-0.5)))
	assert(overlay.lineCount>nearLines,
		"10mm ruler ticks should accumulate as the measurement grows")
	assert(overlay.cursorDot.Dot.BackgroundColor3==Color3.new(1,1,1),
		"Cursor dot should be pure white")
	for i=1,overlay.lineCount do
		assert(overlay.guides[i].Color3==Color3.new(1,1,1),
			"Rulers should be pure white")
	end
	local before=overlay.guides[1].CFrame.Position
	part.CFrame=CFrame.new(5,8,2)*CFrame.Angles(0,math.rad(20),0)
	assert(overlay:show(part,top),"Rotated surface failed")
	assert((overlay.guides[1].CFrame.Position-before).Magnitude>1,
		"Guides must follow the transformed stock")
	assert(not overlay:show(part,{curved=true,polygon=top.polygon}),
		"Curved faces must not show planar rulers")
	assert(overlay.part==nil and not overlay.cursorDot.Enabled)
	assert(overlay:show(part,top))
	overlay:hide()
	assert(overlay.lineCount==0 and not overlay.cursorDot.Enabled)
	for _,line in ipairs(overlay.guides) do
		assert(not line.Visible,"Dimension guide leaked")
	end
	assert(not overlay.origin.CanQuery and not overlay.origin.CanCollide,
		"Ruler helpers must not be raycast/physics targets")
end)
overlay:destroy()
part:Destroy()
assert(ok,tostring(problem))
print("FORM Surface Measurements: fine 1 mm snap, white cursor-crossing rulers and dot and cleanup verified")
