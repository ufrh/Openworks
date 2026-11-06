--!strict
-- Read-only dimensional preview for the actual hovered planar FORM face.
-- Face polygons are taken from cached authored HistoryTopology, never
-- the primitive stock envelope or a live EditableMesh readback.
local Measurements={}
Measurements.__index=Measurements

local SCALE_MM=280
local OUTLINE=Color3.fromRGB(105,226,235)
local DIMENSION=Color3.fromRGB(163,192,200)
local MAX_LINES=96

local function line(parent:Instance,origin:BasePart,index:number):LineHandleAdornment
	local visual=Instance.new("LineHandleAdornment")
	visual.Name="SurfaceGuide_"..index
	visual.Adornee=origin
	visual.AlwaysOnTop=false
	visual.Color3=OUTLINE
	visual.Transparency=0.03
	visual.Thickness=1.4
	visual.Visible=false
	visual.Parent=parent
	return visual
end

local function badge(parent:Instance,origin:BasePart,name:string)
	local position=Instance.new("Attachment")
	position.Name=name.."_Anchor"
	position.Parent=origin

	local gui=Instance.new("BillboardGui")
	gui.Name=name
	gui.Adornee=position
	gui.AlwaysOnTop=true
	gui.Size=UDim2.fromOffset(108,23)
	gui.Enabled=false
	gui.Parent=parent

	local label=Instance.new("TextLabel")
	label.Size=UDim2.fromScale(1,1)
	label.BackgroundColor3=Color3.fromRGB(22,33,39)
	label.BackgroundTransparency=0.08
	label.TextColor3=Color3.fromRGB(230,244,247)
	label.Font=Enum.Font.Code
	label.TextSize=12
	label.Text=""
	label.Parent=gui

	local round=Instance.new("UICorner")
	round.CornerRadius=UDim.new(0,4)
	round.Parent=label
	return {position=position,gui=gui,label=label}
end

function Measurements.new(playerGui:PlayerGui)
	local group=Instance.new("Folder")
	group.Name="FORM_SurfaceMeasurements"
	group.Parent=playerGui

	local origin=Instance.new("Part")
	origin.Name="FORM_SurfaceDimensionOrigin"
	origin.Anchored=true
	origin.CanQuery=false
	origin.CanCollide=false
	origin.CanTouch=false
	origin.CastShadow=false
	origin.Transparency=1
	origin.Size=Vector3.one*0.05
	origin.CFrame=CFrame.identity
	origin.Parent=workspace

	local guides={}
	for i=1,MAX_LINES do
		table.insert(guides,line(group,origin,i))
	end
	return setmetatable({
		root=group,origin=origin,guides=guides,
		widthBadge=badge(playerGui,origin,"SurfaceWidth"),
		heightBadge=badge(playerGui,origin,"SurfaceHeight"),
		lineCount=0,part=nil,lastFace=nil,lastFrame=nil,
	},Measurements)
end

function Measurements:hide()
	if not self.part then return end
	for _,guide in ipairs(self.guides) do guide.Visible=false end
	self.widthBadge.gui.Enabled=false
	self.heightBadge.gui.Enabled=false
	self.lineCount=0
	self.part=nil
	self.lastFace=nil
	self.lastFrame=nil
end

function Measurements:segment(a:Vector3,b:Vector3,tint:Color3?,thickness:number?)
	local offset=b-a
	if offset.Magnitude<0.0005 or self.lineCount>=#self.guides then return end
	self.lineCount+=1
	local guide=self.guides[self.lineCount]
	guide.CFrame=CFrame.lookAt(a,b)
	guide.Length=offset.Magnitude
	guide.Thickness=thickness or 1.4
	guide.Transparency=0.05
	guide.Color3=tint or OUTLINE
	guide.Visible=true
end

local function selectAxis(points:{Vector3}):Vector3?
	local longest=0
	local result=nil
	for i,a in ipairs(points) do
		local vector=points[i%#points+1]-a
		local length=vector.Magnitude
		if length>longest then
			longest=length
			result=vector.Unit
		end
	end
	return result
end

local function dimension(value:number):string
	return string.format("%.0f mm",value*SCALE_MM)
end

-- Supports convex/concave planar faces; measurements are orthogonal
-- bounding EXTENTS in the face's own plane, not a misleading claim
-- about an arbitrary polygon's perimeter or area. Bore walls are curved
-- and intentionally receive no planar face measurement.
function Measurements:show(part:BasePart,face):boolean
	if not part or not face or face.curved or not face.polygon
		or #face.polygon<3 or #face.polygon>80 then
		self:hide()
		return false
	end
	if self.part==part and self.lastFace==face
		and self.lastFrame==part.CFrame then
		return true
	end
	self:hide()
	local points={}
	for _,v in ipairs(face.polygon) do
		table.insert(points,part.CFrame:PointToWorldSpace(v))
	end
	local normal=part.CFrame:VectorToWorldSpace(face.normal)
	if normal.Magnitude<0.1 then return false end
	normal=normal.Unit
	local axis=selectAxis(points)
	if not axis then return false end
	axis=(axis-normal*axis:Dot(normal))
	if axis.Magnitude<0.2 then return false end
	axis=axis.Unit
	local other=normal:Cross(axis).Unit
	local reference=points[1]
	local left,right,bottom,top=math.huge,-math.huge,math.huge,-math.huge
	for _,p in ipairs(points) do
		local offset=p-reference
		local x=offset:Dot(axis)
		local y=offset:Dot(other)
		left=math.min(left,x)
		right=math.max(right,x)
		bottom=math.min(bottom,y)
		top=math.max(top,y)
	end
	local width=right-left
	local height=top-bottom
	if width<0.01 or height<0.01 then return false end

	-- Keep the boundary attached to the actual visible manufactured
	-- contour. The small normal lift prevents Z-fighting with material.
	local lift=normal*0.014
	for i,a in ipairs(points) do
		self:segment(a+lift,points[i%#points+1]+lift,OUTLINE,1.65)
	end

	local function corner(x:number,y:number):Vector3
		return reference+axis*x+other*y+lift
	end
	local leftBottom=corner(left,bottom)
	local rightBottom=corner(right,bottom)
	local rightTop=corner(right,top)

	-- Two offset dimension baselines and short witness ticks, CAD-style.
	local margin=math.clamp(math.min(width,height)*0.15,0.06,0.23)
	local tick=math.clamp(margin*0.22,0.014,0.045)
	local a=leftBottom-other*margin
	local b=rightBottom-other*margin
	local c=rightBottom+axis*margin
	local d=rightTop+axis*margin
	self:segment(a,b,DIMENSION,1.15)
	self:segment(c,d,DIMENSION,1.15)
	self:segment(leftBottom,a-other*tick,DIMENSION,1)
	self:segment(rightBottom,b-other*tick,DIMENSION,1)
	self:segment(rightBottom,c+axis*tick,DIMENSION,1)
	self:segment(rightTop,d+axis*tick,DIMENSION,1)
	for _,p in ipairs({a,b}) do
		self:segment(p-other*tick,p+other*tick,DIMENSION,1.7)
	end
	for _,p in ipairs({c,d}) do
		self:segment(p-axis*tick,p+axis*tick,DIMENSION,1.7)
	end

	self.widthBadge.position.Position=(a+b)*0.5-other*(tick*2)
	self.widthBadge.label.Text=dimension(width)
	self.widthBadge.gui.Enabled=true
	self.heightBadge.position.Position=(c+d)*0.5+axis*(tick*2)
	self.heightBadge.label.Text=dimension(height)
	self.heightBadge.gui.Enabled=true
	self.part=part
	self.lastFace=face
	self.lastFrame=part.CFrame
	return true
end

function Measurements:destroy()
	self:hide()
	self.widthBadge.gui:Destroy()
	self.heightBadge.gui:Destroy()
	self.root:Destroy()
	self.origin:Destroy()
end

return Measurements
