--!strict
-- Read-only dimensional preview for the actual hovered planar FORM face.
-- Face polygons are taken from cached authored HistoryTopology, never
-- the primitive stock envelope or a live EditableMesh readback.
local Measurements={}
Measurements.__index=Measurements

local SCALE_MM=280
local DIMENSION=Color3.new(1,1,1)
local MAX_LINES=96
local SNAP_MM=1 -- independent fine ruler snap; not FORM construction grid
local TICK_SPACING_MM=10 -- physical spacing, never stretched to cursor distance
local MAJOR_SPACING_MM=50
local MAX_TICKS_PER_AXIS=43 -- keep bounded guide allocations on enormous faces

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

	local dotPosition=Instance.new("Attachment")
	dotPosition.Name="SnappedCursorAnchor"
	dotPosition.Parent=origin
	local dotGui=Instance.new("BillboardGui")
	dotGui.Name="SnappedCursorDot"
	dotGui.Adornee=dotPosition
	dotGui.Size=UDim2.fromOffset(9,9)
	dotGui.AlwaysOnTop=true
	dotGui.Enabled=false
	dotGui.Parent=playerGui
	local dot=Instance.new("Frame")
	dot.Name="Dot"
	dot.Size=UDim2.fromScale(1,1)
	dot.BackgroundColor3=Color3.new(1,1,1)
	dot.BorderSizePixel=0
	dot.Parent=dotGui
	local circle=Instance.new("UICorner")
	circle.CornerRadius=UDim.new(1,0)
	circle.Parent=dot
	local guides={}
	for i=1,MAX_LINES do
		table.insert(guides,line(group,origin,i))
	end
	return setmetatable({
		root=group,origin=origin,guides=guides,
		cursorDot=dotGui,cursorAnchor=dotPosition,
		lineCount=0,part=nil,lastFace=nil,lastFrame=nil,
	},Measurements)
end

function Measurements:hide()
	if not self.part then return end
	for _,guide in ipairs(self.guides) do guide.Visible=false end
	self.cursorDot.Enabled=false
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
	-- The two measurement legs ARE the rulers. They meet at the
	-- snapped cursor and show 10 graduated ticks along their lengths.
	-- No detached baselines and no face border.
	local xBase=corner(left,cursorY)
	local yBase=corner(cursorX,bottom)
	self:segment(xBase,cursor,DIMENSION,1.2)
	self:segment(yBase,cursor,DIMENSION,1.2)
	local short=math.min(width,height)
	local minor=math.clamp(short*0.023,0.009,0.03)
	local xDistance=cursorX-left
	local yDistance=cursorY-bottom
	-- Draw real 10 mm increments, anchored to the minimum edge.
	-- Moving the cursor adds/removes ticks; existing marks never stretch.
	-- The cap only limits how many very distant ticks we render.
	local function ticks(distance:number,alongX:boolean)
		local total=math.floor(distance*SCALE_MM/TICK_SPACING_MM+1e-5)
		local first=math.max(0,total-MAX_TICKS_PER_AXIS+1)
		for i=first,total do
			local mm=i*TICK_SPACING_MM
			local major=mm%MAJOR_SPACING_MM==0
			local tick=if major then minor*1.8 else minor
			local p=if alongX then corner(left+mm/SCALE_MM,cursorY)
				else corner(cursorX,bottom+mm/SCALE_MM)
			local offset=if alongX then other*tick*0.5 else axis*tick*0.5
			self:segment(p-offset,p+offset,DIMENSION,
				if major then 1.45 else 1)
		end
	end
	ticks(xDistance,true)
	ticks(yDistance,false)
	self.cursorAnchor.Position=cursor
	self.cursorDot.Enabled=true
	self.part=part
	self.lastFace=face
	self.lastFrame=part.CFrame
	return true
end

function Measurements:destroy()
	self:hide()
	self.cursorDot:Destroy()
	self.root:Destroy()
	self.origin:Destroy()
end

return Measurements
