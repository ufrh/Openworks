--!strict
-- Studio CLIENT Command Bar test after syncing dev.
-- Uses a mock Document so each handle can be rendered without modifying
-- any real FORM body. Actual mouse dragging still needs a human test.
local Players=game:GetService("Players")
local player=Players.LocalPlayer
assert(player,"Run during Play in the CLIENT Command Bar")
local Gizmo=require(player:WaitForChild("PlayerScripts")
	:WaitForChild("Openworks"):WaitForChild("TransformGizmo"))
assert(Gizmo.Revision=="GIZMO-STUDIO-HANDLES.3",
	"Wrong gizmo module loaded: "..tostring(Gizmo.Revision))
local mock={applyTransform=function()
	return true
end}
local node={position=Vector3.zero,size=Vector3.new(2,1,3),
	rotation=Vector3.zero}
local component={id=1984,nodes={node},operations={}}
local gizmo=Gizmo.new(player:WaitForChild("PlayerGui"),mock,function() end)
local success,problem=pcall(function()
	gizmo:show(component,1)
	local moves=0
	for _,grip in ipairs(gizmo.grips) do
		if grip.mode=="Move" then
			moves+=1
			assert(grip.stem:IsA("Part") and
				grip.stem.Shape==Enum.PartType.Cylinder)
			assert(grip.tip:IsA("WedgePart"),
				"Arrowhead must be a solid Part, not an adornment")
			assert(grip.highlight:IsA("Highlight"))
			assert(grip.highlight.Enabled and grip.stem.Transparency==0
				and grip.tip.Transparency==0)
			assert((grip.shaftStart-node.position).Magnitude<1e-5,
				"Arrow shaft doesn't begin at the object center")
			local direction=grip.normal
			assert((grip.arrowTip-grip.shaftEnd):Dot(direction)>0,
				"Arrow tip must point outward from its axis")
			assert((grip.arrowTip-node.position):Cross(direction).Magnitude<1e-5)
		end
	end
	assert(moves==3,"Need X/Y/Z move arrows")

	gizmo:setMode("Scale")
	local scales=0
	for _,grip in ipairs(gizmo.grips) do
		if grip.mode=="Scale" then
			scales+=1
			assert(grip.part:IsA("Part") and
				grip.part.Shape==Enum.PartType.Block,
				"Scale grip must be a studio-style solid cube")
			assert(grip.highlight.Enabled and grip.part.Transparency==0)
		end
	end
	assert(scales==6,"Need six face scale grips")

	gizmo:setMode("Rotate")
	local axes={X=false,Y=false,Z=false}
	for axis,arcs in pairs(gizmo.rotationArcs) do
		assert(arcs:IsA("ArcHandles"),"Rotation ring must be native ArcHandles")
		assert(arcs.Visible and arcs.Adornee==gizmo.rotationAnchor,
			"Native ring has no visible local part to adorn")
		assert(arcs.Parent==player.PlayerGui,
			"Native ArcHandles must be in PlayerGui to receive mouse events")
		axes[axis]=true
	end
	assert(axes.X and axes.Y and axes.Z,"Need X/Y/Z native rotation axes")
	assert(gizmo.rotationAnchor.CanQuery==false,
		"Rotation pivot must not intercept material raycasts")
	assert(gizmo.rotationAnchor.Transparency==1)
	for _,grip in ipairs(gizmo.grips) do
		if grip.mode=="Move" or grip.mode=="Scale" then
			assert(grip.highlight.Enabled==false,
				"Non-rotation parts must hide during Rotate")
		end
	end

	gizmo:hide()
	for _,arcs in pairs(gizmo.rotationArcs) do
		assert(not arcs.Visible,"Rotation rings must hide on deselection")
	end
end)
gizmo:destroy()
assert(success,tostring(problem))
print("FORM: 3 highlighted Part move arrows, six Scale cubes and 3 native ArcHandles verified")
