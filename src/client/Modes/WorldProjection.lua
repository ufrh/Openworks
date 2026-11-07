--!strict
-- Q1 compatibility layer. Live FORM meshes are authored in isolated edit
-- coordinates and displayed at the original world location outside Edit.
-- Only visual copies are retained; server-authoritative shipping is Q2/Q4.
local WorldProjection={}
WorldProjection.__index=WorldProjection
function WorldProjection.new()
	local root=Instance.new("Folder")
	root.Name="OPENWORKS_LocalWorldComponents"
	root.Parent=workspace
	return setmetatable({root=root,source=nil},WorldProjection)
end
function WorldProjection:show(preview:any,document:any,workspaceData:any,targetCorner:Vector3?)
	self:clear()
	if not workspaceData then return end
	for _,component in pairs(document.components) do
		local model=preview:getModel(component.id)
		if not model then continue end
		local clone=model:Clone()
		clone.Name=component.name
		clone.Parent=self.root
		local offset=(targetCorner or component.worldOrigin or workspaceData.worldCorner) - (component.workspaceOrigin or workspaceData.editCorner)
		for _,descendant in ipairs(clone:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.CFrame=CFrame.new(offset)*descendant.CFrame
				descendant.Anchored=true
				descendant.CanCollide=false
				descendant.CanTouch=false
				descendant.CastShadow=true
			end
		end
	end
end
function WorldProjection:clear()
	for _,child in ipairs(self.root:GetChildren()) do child:Destroy() end
end
function WorldProjection:Destroy()
	self.root:Destroy()
end
return WorldProjection
