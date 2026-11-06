--!strict
-- Run in Play Solo CLIENT Command Bar after syncing OPENWORKS dev.
-- Tests real rendered world-coordinate arrow/ring vertices and selection.
-- UI event dispatch still needs a click in Studio.
local Players=game:GetService("Players")
local player=Players.LocalPlayer
assert(player,"Client Play Solo required")
local Gizmo=require(player:WaitForChild("PlayerScripts")
	:WaitForChild("Openworks"):WaitForChild("TransformGizmo"))
local camera=workspace.CurrentCamera
assert(camera,"CurrentCamera missing")
local originalCamera=camera.CFrame
local position=Vector3.zero
local size=Vector3.new(2,1,3)
local node={position=position,size=size,rotation=Vector3.zero}
local component={id=1984,nodes={node},operations={}}
local gizmo=Gizmo.new(player:WaitForChild("PlayerGui"),{},function() end)
local ok,why=pcall(function()
	camera.CFrame=CFrame.lookAt(Vector3.new(6,5,9),position)
	gizmo:show(component,1)
	local count=0
	for _,grip in ipairs(gizmo.grips) do
		if grip.mode=="Move" then
			count+=1
			local direction=grip.normal
			assert(grip.arrow:IsA("WireframeHandleAdornment"),
				"Move visual must be world-space wireframe")
			assert(grip.arrow.Visible)
			assert((grip.shaftStart-position).Magnitude<1e-5,
				"Move stem does not begin at the object center")
			assert((grip.shaftEnd-position):Dot(direction)>size[grip.axis]*0.5,
				"Move stem fails to cross the object face")
			assert((grip.arrowTip-grip.shaftEnd):Dot(direction)>0,
				"Arrowhead tip points inward, not outward")
			assert((grip.arrowTip-grip.shaftStart):Cross(direction).Magnitude<1e-5,
				"Arrowhead deviates from its axis")
		end
	end
	assert(count==3,"All XYZ move arrows required")
	gizmo:setMode("Scale")
	count=0
	for _,grip in ipairs(gizmo.grips) do
		if grip.mode=="Scale" then
			count+=1
			assert(grip.marker.Visible)
			assert((grip.part.Position-position):Dot(grip.normal)>
				size[grip.axis]*0.5,"Scale handle overlaps the body")
		end
	end
	assert(count==6,"All six scale faces required")
	gizmo:setMode("Rotate")
	local ringCount=0
	local clickable=false
	for _,grip in ipairs(gizmo.grips) do
		if grip.mode=="Rotate" then
			ringCount+=1
			assert(grip.ring:IsA("WireframeHandleAdornment"))
			assert(grip.ring.Visible,"A rotation ring is hidden")
			assert(#grip.ringPath==72 and #grip.ringWorldPath==72,
				"Rotation ring has no full wireframe circumference")
			assert(grip.ring.CFrame==CFrame.identity,
				"World-space ring must not apply a second transformation")
			assert(grip.ring.Scale==Vector3.one,
				"World-space ring must not apply a second scale")
			for i,worldPoint in ipairs(grip.ringWorldPath) do
				local projected=grip.ringFrame:PointToWorldSpace(
					grip.ringPath[i]*grip.ringRadius)
				assert((worldPoint-projected).Magnitude<1e-5,
					"Rendered ring point differs from click target")
				local point,front=camera:WorldToViewportPoint(worldPoint)
				if front and gizmo._pick(Vector2.new(point.X,point.Y)) then
					clickable=true
				end
			end
		end
	end
	assert(ringCount==3,"Missing XYZ rotation rings")
	assert(clickable,"Rotation ring cannot be selected at its drawn pixels")
end)
camera.CFrame=originalCamera
gizmo:destroy()
assert(ok,tostring(why))
print("FORM gizmo: 3 pivot-origin outward arrows, 6 scale grips, 3 drawn/clickable rotation rings verified")
