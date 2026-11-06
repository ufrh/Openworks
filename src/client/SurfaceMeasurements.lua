--!strict
-- Read-only dimensional preview for the actual hovered planar FORM face.
-- Face polygons are taken from cached authored HistoryTopology, never
-- the primitive stock envelope or a live EditableMesh readback.
local Measurements={}
Measurements.__index=Measurements

local SCALE_MM=280
local DIMENSION=Color3.fromRGB(163,192,200)
local MAX_LINES=96
local SNAP_MM=1 -- independent fine ruler snap; not FORM construction grid
local RULER_STEPS=10 -- major ruler subdivisions along the on-face guide lines

local function line(parent:Instance,origin:BasePart,index:number):LineHandleAdornment
	local visual=Instance.new("LineHandleAdornment")
	visual.Name="SurfaceGuide_"..index
	visual.Adornee=origin
	visual.AlwaysOnTop=false
	visual.Color3=DIMENSION
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
	guide.Color3=tint or DIMENSION
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
	return string.format("%.1f mm",value*SCALE_MM)
end

-- Supports convex/concave planar faces; measurements are orthogonal
-- bounding EXTENTS in the face's own plane, not a misleading claim
-- about an arbitrary polygon's perimeter or area. Bore walls are curved
-- and intentionally receive no planar face measurement.
function Measurements:show(part:BasePart,face,cursorWorld:Vector3?):boolean
	if not part or not face or face.curved or not face.polygon
		or #face.polygon<3 or #face.polygon>80 then
		self:hide()
		return false
	end
	if cursorWorld==nil and self.part==part and self.lastFace==face
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

	-- Guides sit on the actual planar manufactured face. There is no
	-- perimeter silhouette / SelectionBox-like outline.
	local lift=normal*0.014
	local function corner(x:number,y:number):Vector3
		return reference+axis*x+other*y+lift
	end
	-- Fine 1 mm cursor snap, independent of OpenWorks' 0.05-stud
	-- modeling grid. Snap from the minimum edge, not from world zero.
	local localCursor=if cursorWorld then cursorWorld-reference else
		axis*(width*0.5+left)+other*(height*0.5+bottom)
	local snapStuds=SNAP_MM/SCALE_MM
	local cursorX=left+math.clamp(
		math.round((localCursor:Dot(axis)-left)/snapStuds)*snapStuds,0,width)
	local cursorY=bottom+math.clamp(
		math.round((localCursor:Dot(other)-bottom)/snapStuds)*snapStuds,0,height)
	local cursor=corner(cursorX,cursorY)
	local short=math.min(width,height)
	local inset=math.min(short*0.07,0.1)
	local rulerX=bottom+inset
	local rulerY=left+inset
	local xStart=corner(left,rulerX)
	local xEnd=corner(right,rulerX)
	local yStart=corner(rulerY,bottom)
	local yEnd=corner(rulerY,top)
	-- Two real in-face ruler baselines with ticks ON the baselines.
	self:segment(xStart,xEnd,DIMENSION,1.35)
	self:segment(yStart,yEnd,DIMENSION,1.35)
	local minor=math.clamp(short*0.022,0.009,0.025)
	for i=0,RULER_STEPS do
		local major=i%5==0
		local tick=if major then minor*1.9 else minor
		local x=left+width*i/RULER_STEPS
		local y=bottom+height*i/RULER_STEPS
		local px=corner(x,rulerX)
		local py=corner(rulerY,y)
		self:segment(px-other*tick*0.5,px+other*tick*0.5,
			DIMENSION,if major then 1.5 else 1)
		self:segment(py-axis*tick*0.5,py+axis*tick*0.5,
			DIMENSION,if major then 1.5 else 1)
	end
	-- Perpendicular cursor guides intersect the ruler axes while
	-- remaining on the face. No border/perimeter drawing.
	local xBase=corner(left,cursorY)
	local yBase=corner(cursorX,bottom)
	self:segment(xBase,cursor,DIMENSION,1.15)
	self:segment(yBase,cursor,DIMENSION,1.15)
	local cross=minor*0.85
	self:segment(cursor-axis*cross,cursor+axis*cross,DIMENSION,1.35)
	self:segment(cursor-other*cross,cursor+other*cross,DIMENSION,1.35)
	self.widthBadge.position.Position=(xBase+cursor)*0.5+other*(cross*2)
	self.widthBadge.label.Text="X "..dimension(cursorX-left)
	self.widthBadge.gui.Enabled=true
	self.heightBadge.position.Position=(yBase+cursor)*0.5+axis*(cross*2)
	self.heightBadge.label.Text="Y "..dimension(cursorY-bottom)
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
