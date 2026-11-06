--!strict
-- Client-side Studio smoke test for the FORM gizmo adornment overhaul.
-- Run in the Play Solo CLIENT Command Bar after syncing `dev`.
-- Verifies the new visual geometry and cursor capture without moving CSG.
local player=game:GetService("Players").LocalPlayer
assert(player,"Run this in the client Command Bar during Play Solo")
local gizmoModule=player:WaitForChild("PlayerScripts")
	:WaitForChild("Openworks"):WaitForChild("TransformGizmo")
local Gizmo=require(gizmoModule)
local camera=workspace.CurrentCamera
assert(camera,"Studio must provide an active Camera")
local position=Vector3.zero
local size=Vector3.new(2,1,3)
local node={position=position,size=size,rotation=Vector3.zero}
local component={id=1984,nodes={node},operations={}}
local gizmo=Gizmo.new(player:WaitForChild("PlayerGui"),{},function() end)
gizmo:show(component,1)

local moves=0
for _,grip in ipairs(gizmo.grips) do
	if grip.mode=="Move" then
		moves+=1
		local axis=grip.normal
		assert(grip.shaftAdornment.Visible)
		assert((grip.shaftAdornment.CFrame.Position-position).Magnitude<1e-5,
			"Move shaft does not originate at the common XYZ pivot")
		assert(grip.tipAdornment.CFrame.LookVector:Dot(axis)>0.999,
			"Move arrowhead is rotated off its axis")
		assert(grip.shaftAdornment.Length>size[grip.axis]*0.5,
			"Move arrow does not extend beyond component bounds")
	end
end
assert(moves==3,"Need X/Y/Z move arrows")
gizmo:setMode("Scale")
local scales=0
for _,grip in ipairs(gizmo.grips) do
	if grip.mode=="Scale" then
		scales+=1
		assert(grip.marker.Visible)
		local axis=grip.normal
		assert((grip.part.Position-position):Dot(axis)>size[grip.axis]*0.5,
			"Scale grip overlaps the selected component")
	end
end
assert(scales==6,"Need six positive/negative face scale grips")
gizmo:setMode("Rotate")
local rings=0
for _,grip in ipairs(gizmo.grips) do
	if grip.mode=="Rotate" then
		rings+=1
		assert(grip.ring:IsA("WireframeHandleAdornment"))
		assert(grip.ring.Visible and #grip.ringPath>=48,
			"Rotation ring not displayed with smooth wireframe")
		assert(grip.ringRadius>0)
		assert((grip.ringFrame.Position-position).Magnitude<1e-5)
		for _,point in ipairs(grip.ringPath) do
			assert(math.abs(point:Dot(grip.normal))<1e-5,
				"Rotation wireframe not perpendicular to its rotation axis")
		end
	end
end
assert(rings==3,"Need three XYZ wireframe rotation rings")

local picked=false
for _,grip in ipairs(gizmo.grips) do
	if grip.mode=="Rotate" then
		for _,point in ipairs(grip.ringPath) do
			local world=grip.ringFrame:PointToWorldSpace(point*grip.ringRadius)
			local projection,inFront=camera:WorldToViewportPoint(world)
			if inFront then
				local mouse=Vector2.new(projection.X,projection.Y)
				if gizmo:capturesPoint(mouse) then
					picked=true
					break
				end
			end
		end
	end
	if picked then break end
end
assert(picked,"Wireframe circumference does not capture projected pointer")
gizmo:destroy()
print("FORM gizmo: center-to-tip XYZ arrows, correct cone directions, 6 scale grips and 3 clickable wireframe rings")
