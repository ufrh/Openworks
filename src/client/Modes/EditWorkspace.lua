--!strict
-- Authoritative world placement never changes when opening a dedicated
-- edit chamber. The editor receives a separate virtual coordinate frame.
local EditWorkspace={}
EditWorkspace.__index=EditWorkspace
local CENTER=Vector3.new(0,200,0)
function EditWorkspace.new(worldCorner:Vector3,size:Vector3,name:string)
	assert(size.X>0 and size.Z>0,"Positive X/Z component dimensions required")
	local editCorner=CENTER-Vector3.new(size.X*0.5,0,size.Z*0.5)
	return setmetatable({
		name=name,worldCorner=worldCorner,editCorner=editCorner,
		size=size,center=CENTER,
	},EditWorkspace)
end
function EditWorkspace:toWorld(editPoint:Vector3):Vector3
	return editPoint-self.editCorner+self.worldCorner
end
function EditWorkspace:toEdit(worldPoint:Vector3):Vector3
	return worldPoint-self.worldCorner+self.editCorner
end
function EditWorkspace:vectorToWorld(vector:Vector3):Vector3
	return vector
end
EditWorkspace.ChamberCenter=CENTER
return EditWorkspace
