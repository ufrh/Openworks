--!strict
-- Client-only shadowless staging visuals; not a physical room.
-- Fixed chamber dimensions are independent of any component's grid.
local EditEnvironment={}
EditEnvironment.__index=EditEnvironment
EditEnvironment.Size=Vector3.new(40,20,40)
EditEnvironment.Center=Vector3.new(0,200,0)
local CYAN=Color3.fromRGB(84,229,255)
local STEEL=Color3.fromRGB(17,30,48)
local function visual(parent:Instance,name:string,size:Vector3,position:Vector3,
	color:Color3,material:Enum.Material,transparency:number):BasePart
	local part=Instance.new("Part")
	part.Name=name
	part.Size=size
	part.Position=position
	part.Anchored=true
	part.CanCollide=false
	part.CanQuery=false
	part.CanTouch=false
	part.CastShadow=false
	part.Material=material
	part.Color=color
	part.Transparency=transparency
	part.Parent=parent
	return part
end
function EditEnvironment.new()
	return setmetatable({root=nil},EditEnvironment)
end
function EditEnvironment:show()
	if self.root then return end
	local root=Instance.new("Folder")
	root.Name="OPENWORKS_LocalEditChamber"
	root.Parent=workspace
	local c=EditEnvironment.Center
	local size=EditEnvironment.Size
	local x,z,y=size.X/2,size.Z/2,size.Y
	-- Walls are visual indicators, not light-blocking geometry. No roof.
	visual(root,"Floor",Vector3.new(size.X,0.08,size.Z),
		c+Vector3.new(0,-0.09,0),STEEL,Enum.Material.SmoothPlastic,0.10)
	for _,xSign in ipairs({-1,1}) do
		visual(root,"BoundaryX",Vector3.new(0.05,y,size.Z),
			c+Vector3.new(xSign*x,y/2,0),STEEL,Enum.Material.SmoothPlastic,0.96)
	end
	for _,zSign in ipairs({-1,1}) do
		visual(root,"BoundaryZ",Vector3.new(size.X,y,0.05),
			c+Vector3.new(0,y/2,zSign*z),STEEL,Enum.Material.SmoothPlastic,0.96)
	end
	local thickness=0.075
	for _,dx in ipairs({-x,x}) do
		for _,dz in ipairs({-z,z}) do
			visual(root,"CyanPillar",Vector3.new(thickness,y,thickness),
				c+Vector3.new(dx,y/2,dz),CYAN,Enum.Material.Neon,0.40)
		end
	end
	for _,dx in ipairs({-x,x}) do
		for _,height in ipairs({0,y}) do
			visual(root,"CyanEdgeZ",Vector3.new(thickness,thickness,size.Z),
				c+Vector3.new(dx,height,0),CYAN,Enum.Material.Neon,0.55)
		end
	end
	for _,dz in ipairs({-z,z}) do
		for _,height in ipairs({0,y}) do
			visual(root,"CyanEdgeX",Vector3.new(size.X,thickness,thickness),
				c+Vector3.new(0,height,dz),CYAN,Enum.Material.Neon,0.55)
		end
	end
	self.root=root
end
function EditEnvironment:hide()
	if self.root then self.root:Destroy() self.root=nil end
end
function EditEnvironment:Destroy()
	self:hide()
end
return EditEnvironment
