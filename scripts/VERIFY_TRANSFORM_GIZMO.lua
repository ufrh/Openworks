--!strict
-- Studio CLIENT Command Bar smoke test for camera-scaled custom FORM gizmo.
-- Run during Play after Rojo sync. No real document is modified.
local Players=game:GetService("Players")
local player=Players.LocalPlayer
assert(player,"Run during Play in the CLIENT Command Bar")
local Gizmo=require(player:WaitForChild("PlayerScripts")
	:WaitForChild("Openworks"):WaitForChild("TransformGizmo"))
assert(Gizmo.Revision=="GIZMO-CLEAN-TIPS.6",
	"Wrong gizmo loaded: "..tostring(Gizmo.Revision))
local camera=workspace.CurrentCamera
assert(camera,"CurrentCamera missing")
local originalCamera=camera.CFrame
local mock={applyTransform=function() return true end}
local node={position=Vector3.zero,size=Vector3.new(2,1,3),
	rotation=Vector3.zero}
local component={id=1984,nodes={node},operations={}}
local gizmo=Gizmo.new(player:WaitForChild("PlayerGui"),mock,function() end)
local success,reason=pcall(function()
	camera.CFrame=CFrame.lookAt(Vector3.new(7,6,10),Vector3.zero)
	gizmo:show(component,1)
	local moves=0
	for _,grip in ipairs(gizmo.grips) do
		if grip.mode=="Move" then
			moves+=1
			assert(grip.stem:IsA("Part")
				and grip.stem.Shape==Enum.PartType.Cylinder)
			assert(grip.tip:IsA("MeshPart") and grip.tip.Name=="Arrowhead",
				"Move head must clone ReplicatedStorage.Cone")
			assert(grip.highlight:IsA("Highlight") and grip.highlight.Enabled)
			assert(grip.highlight.FillTransparency==0 and
				grip.highlight.OutlineTransparency==1,
				"Move highlight must be opaque fill only")
			assert(grip.stemBorder==nil and grip.tipBorder==nil,
				"Move cone must not have square SelectionBox outlines")
			assert(grip.stem.Transparency==0 and grip.tip.Transparency==0)
			assert((grip.shaftStart-node.position).Magnitude<1e-5,
				"Move shaft doesn't begin at the component pivot")
			assert((grip.arrowTip-grip.shaftEnd):Dot(grip.normal)>0,
				"Move arrowhead points inward")
		end
	end
	assert(moves==3,"Need X/Y/Z Move arrows")
	gizmo:setMode("Scale")
	local scales=0
	for _,grip in ipairs(gizmo.grips) do
		if grip.mode=="Scale" then
			scales+=1
			assert(grip.part.Shape==Enum.PartType.Block
				and grip.highlight.Enabled)
			assert(grip.highlight.FillTransparency==0 and
				grip.highlight.OutlineTransparency==1)
			assert(grip.border:IsA("SelectionBox") and grip.border.Visible)
			assert((grip.part.Position-node.position):Dot(grip.normal)>
				node.size[grip.axis]*0.5,"Scale handle overlaps stock")
		end
	end
	assert(scales==6,"Need six Scale grips")
	gizmo:setMode("Rotate")
	local rings=0
	local radii={}
	local firstRadius=nil
	local picked=false
	for _,grip in ipairs(gizmo.grips) do
		if grip.mode=="Rotate" then
			rings+=1
			assert(grip.highlight.Enabled,
				"Rotation ring must have a visible highlight")
			assert(grip.highlight.FillTransparency==0 and
				grip.highlight.OutlineTransparency==1)
			assert(grip.contour:IsA("WireframeHandleAdornment")
				and grip.contour.Visible,
				"Ring boundary should use one clean wireframe adornment")
			radii[grip.axis]=grip.ringRadius
			assert(#grip.segments==48 and #grip.ringPoints==48,
				"Rotation ring must have 48 geometric segments")
			for i,p in ipairs(grip.segments) do
				assert(p.Shape==Enum.PartType.Cylinder and p.CanQuery,
					"Ring segments must be real selectable cylinder Parts")
				assert(not p.CanCollide and not p.CanTouch,
					"Visual gizmo must not affect physics")
				assert(p.Transparency<0.1 and p.Size.X>0,
					"Custom rotation ring is not visible")
				local world=grip.ringPoints[i]
				local axis=gizmo.visualFrame:VectorToWorldSpace(grip.normal)
				assert(math.abs((world-node.position):Dot(axis))<0.0001,
					"Rotation ring is not in the correct axis plane")
				local point,onScreen=camera:WorldToViewportPoint(world)
				if onScreen and gizmo._pick(Vector2.new(point.X,point.Y)) then
					picked=true
				end
			end
			if grip.axis=="X" then firstRadius=grip.ringRadius end
		end
	end
	assert(rings==3 and picked,"Missing or unselectable XYZ rotation rings")
	assert(firstRadius and firstRadius>0)
	assert(math.abs(radii.X-radii.Y)<1e-5
		and math.abs(radii.Y-radii.Z)<1e-5,
		"All three rotation axes must have the same radius")
	-- The user requires camera-scaled visuals, unlike native ArcHandles.
	camera.CFrame=CFrame.lookAt(Vector3.new(19,15,22),Vector3.zero)
	gizmo:refresh()
	local farther=gizmo.rotationGrips.X.ringRadius
	assert(farther>firstRadius,
		"Rotation rings must resize as the camera zooms")
	gizmo:hide()
	for _,grip in ipairs(gizmo.grips) do
		assert(not grip.highlight.Enabled,"Handles remain after deselect")
	end
end)
camera.CFrame=originalCamera
gizmo:destroy()
assert(success,tostring(reason))
print("FORM: clean Cone arrowheads, fill-only Highlights, subtle outline and equal XYZ rings verified")
