--!strict
-- ONE workspace grid. No fixed world grid and no physical preview box.
-- Drawn from non-queryable LineHandleAdornments with bounds supplied by
-- mouse placement, then retained at exactly that location for editing.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Quantize=require(ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM").Quantize)
local GridOverlay={}
GridOverlay.__index=GridOverlay

function GridOverlay.new(playerGui:PlayerGui)
	local origin=Instance.new("Part")
	origin.Name="FORM_LocalGridOrigin"
	origin.Anchored=true
	origin.Size=Vector3.one*0.05
	origin.Transparency=1
	origin.CanTouch=false
	origin.CanCollide=false
	origin.CanQuery=false
	origin.CastShadow=false
	origin.CFrame=CFrame.identity
	origin.Parent=workspace
	local container=Instance.new("Folder")
	container.Name="FORM_ComponentWorkspaceGrid"
	container.Parent=playerGui
	return setmetatable({
		origin=origin,anchor=origin,decorations=container,
		lines={},visible=false,corner=nil,size=nil,lineCount=0,
	},GridOverlay)
end

local function guide(self,index:number):LineHandleAdornment
	if self.lines[index] then return self.lines[index] end
	local line=Instance.new("LineHandleAdornment")
	line.Name="WorkspaceGrid_"..index
	line.Adornee=self.origin
	line.AlwaysOnTop=false
	line.Color3=Color3.fromRGB(173,213,226)
	line.Transparency=0.56
	line.Thickness=1
	line.Visible=false
	line.Parent=self.decorations
	self.lines[index]=line
	return line
end

function GridOverlay:setVisible(value:boolean)
	-- Mouse placement runs every rendered frame. A visibility assignment
	-- must be idempotent instead of touching 40-100 adornments per frame.
	if self.visible==value then return end
	self.visible=value
	for i,line in ipairs(self.lines) do
		line.Visible=value and i<=self.lineCount and line.Length>0
	end
end

function GridOverlay:update(corner:Vector3,size:Vector3)
	local width=math.max(Quantize.Grid,size.X)
	local length=math.max(Quantize.Grid,size.Z)
	local bounds=Vector2.new(width,length)
	-- Local-space lines are attached to the origin. Cursor movement
	-- needs ONE Part.CFrame assignment, not a rebuild of every line.
	if self.corner~=corner then
		self.corner=corner
		self.origin.CFrame=CFrame.new(corner)
	end
	if self.size==bounds then return end
	self.size=bounds
	local increment=Quantize.Grid
	local stride=math.max(1,math.ceil(math.max(width,length)/increment/48))
	local step=increment*stride
	local count=0
	local offset=Vector3.new(0,0.012,0)
	local function add(a:Vector3,b:Vector3,major:boolean)
		count+=1
		local line=guide(self,count)
		line.CFrame=CFrame.lookAt(a,b)
		line.Length=(b-a).Magnitude
		line.Color3=if major then Color3.fromRGB(235,249,255)
			else Color3.fromRGB(134,180,194)
		line.Thickness=if major then 1.8 else 1.1
		line.Transparency=if major then 0.32 else 0.71
		line.Visible=self.visible
	end
	local nx=math.ceil(width/step)
	local nz=math.ceil(length/step)
	for i=0,nx do
		local x=math.min(width,i*step)
		add(offset+Vector3.new(x,0,0),
			offset+Vector3.new(x,0,length),
			i==0 or i==nx or i%5==0)
	end
	for i=0,nz do
		local z=math.min(length,i*step)
		add(offset+Vector3.new(0,0,z),
			offset+Vector3.new(width,0,z),
			i==0 or i==nz or i%5==0)
	end
	for i=count+1,#self.lines do self.lines[i].Visible=false end
	self.lineCount=count
end

-- Release temporary placement/sketch lines completely. Reopening the
-- grid reconstructs only the lines needed at its new actual dimensions.
function GridOverlay:clear()
	for _,line in ipairs(self.lines) do line:Destroy() end
	table.clear(self.lines)
	self.lineCount=0
	self.corner=nil
	self.size=nil
	self.visible=false
end

function GridOverlay:destroy()
	self:clear()
	self.decorations:Destroy()
	self.origin:Destroy()
end

return GridOverlay
