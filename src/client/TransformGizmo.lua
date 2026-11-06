--!strict
-- Camera-scaled custom solid gizmos styled after Roblox Studio.
-- Native Handles/ArcHandles are deliberately avoided: their fixed visual
-- scale cannot follow the camera zoom needed by the FORM editor.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local FORM = ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM")
local Quantize = require(FORM.Quantize)
-- Authored Cone MeshPart is modeled with its tip along local +Y.
local ConeTemplate = ReplicatedStorage:WaitForChild("Cone")
assert(ConeTemplate:IsA("MeshPart"),
	"OPENWORKS requires ReplicatedStorage.Cone to be a MeshPart")

local TransformGizmo = {}
TransformGizmo.__index = TransformGizmo
-- Shown by the startup build badge, so Studio can distinguish a stale
-- cached gizmo ModuleScript from a newly synced client entry script.
TransformGizmo.Revision = "GIZMO-SCALE-FULL-RINGS.15"

local AXES = {
	{ normal = Vector3.xAxis, name = "X+", axis = "X", color = Color3.fromRGB(224, 88, 91) },
	{ normal = -Vector3.xAxis, name = "X-", axis = "X", color = Color3.fromRGB(224, 88, 91) },
	{ normal = Vector3.yAxis, name = "Y+", axis = "Y", color = Color3.fromRGB(99, 205, 122) },
	{ normal = -Vector3.yAxis, name = "Y-", axis = "Y", color = Color3.fromRGB(99, 205, 122) },
	{ normal = Vector3.zAxis, name = "Z+", axis = "Z", color = Color3.fromRGB(94, 155, 235) },
	{ normal = -Vector3.zAxis, name = "Z-", axis = "Z", color = Color3.fromRGB(94, 155, 235) },
}
local MOVE_AXES = { AXES[1], AXES[3], AXES[5] }
local MM_PER_STUD = 280 -- Roblox standard physical scale, 0.28 m per stud.
local RING_SAMPLES = 48
local RING_HIT_PIXELS = 5
local SHAFT_HIT_PIXELS = 3.5
local ROTATIONS = {
	{ normal = Vector3.xAxis, radial = Vector3.yAxis, axis = "X", color = Color3.fromRGB(224, 88, 91) },
	{ normal = Vector3.yAxis, radial = Vector3.zAxis, axis = "Y", color = Color3.fromRGB(99, 205, 122) },
	{ normal = Vector3.zAxis, radial = Vector3.xAxis, axis = "Z", color = Color3.fromRGB(94, 155, 235) },
}

local function frame(node)
	return CFrame.new(node.position) * CFrame.fromOrientation(
		math.rad(node.rotation.X), math.rad(node.rotation.Y), math.rad(node.rotation.Z))
end

local function getAxis(v: Vector3, axis: string): number
	if axis == "X" then return v.X elseif axis == "Y" then return v.Y end
	return v.Z
end

local function putAxis(v: Vector3, axis: string, n: number): Vector3
	if axis == "X" then return Vector3.new(n, v.Y, v.Z) end
	if axis == "Y" then return Vector3.new(v.X, n, v.Z) end
	return Vector3.new(v.X, v.Y, n)
end

-- Rotating a ring is a local-axis operation, NOT an update to one
-- Euler component. Compose the delta with the initial orientation first,
-- then extract the YXZ angles used by CFrame.fromOrientation / Document.
local function rotateLocal(startRotation:Vector3,localAxis:Vector3,radians:number):Vector3
	local initial=CFrame.fromOrientation(math.rad(startRotation.X),
		math.rad(startRotation.Y),math.rad(startRotation.Z))
	local composed=initial*CFrame.fromAxisAngle(localAxis,radians)
	local x,y,z=composed:ToOrientation()
	return Vector3.new(math.deg(x),math.deg(y),math.deg(z))
end

TransformGizmo.rotateLocal=rotateLocal

local function rayFor(point: Vector2): (Vector3?, Vector3?)
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	local ray = camera:ViewportPointToRay(point.X, point.Y)
	return ray.Origin, ray.Direction.Unit
end

-- Closest parameter along world axis to a viewport ray. Use camera-facing
-- projection as a fallback when the camera looks almost parallel to the axis.
local function axisParameter(point: Vector2, pivot: Vector3, axis: Vector3): number?
	local origin, direction = rayFor(point)
	if not origin or not direction then return nil end
	local b = axis:Dot(direction)
	local denominator = 1 - b * b
	if denominator > 0.0005 then
		local delta = origin - pivot
		return (delta:Dot(axis) - b * delta:Dot(direction)) / denominator
	end
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	local right = camera.CFrame.RightVector
	local up = camera.CFrame.UpVector
	local screenAxis = Vector2.new(axis:Dot(right), -axis:Dot(up))
	if screenAxis.Magnitude < 0.05 then return nil end
	local pivot2d, visible = camera:WorldToViewportPoint(pivot)
	if not visible then return nil end
	local next2d, _ = camera:WorldToViewportPoint(pivot + axis)
	local pixels = Vector2.new(next2d.X - pivot2d.X, next2d.Y - pivot2d.Y)
	if pixels.Magnitude < 0.001 then return nil end
	return (point - Vector2.new(pivot2d.X, pivot2d.Y)):Dot(pixels) / pixels:Dot(pixels)
end

local function planeRadial(point: Vector2, center: Vector3, normal: Vector3): Vector3?
	local origin, direction = rayFor(point)
	if not origin or not direction then return nil end
	local denom = normal:Dot(direction)
	if math.abs(denom) < 0.015 then return nil end
	local distance = normal:Dot(center - origin) / denom
	if distance < 0 then return nil end
	local radial = origin + direction * distance - center
	if radial.Magnitude < 0.001 then return nil end
	return radial.Unit
end

local function visualScale(position: Vector3): number
	local camera = workspace.CurrentCamera
	if not camera then return 0.12 end
	local viewport = camera.ViewportSize
	local distance = (camera.CFrame.Position - position).Magnitude
	-- Approx. 8 screen pixels per grip, independent of the object dimensions.
	local worldPerPixel = 2 * distance * math.tan(math.rad(camera.FieldOfView) / 2) / math.max(viewport.Y, 1)
	return math.clamp(worldPerPixel * 8, 0.025, 0.34)
end

-- Move, Scale and Rotate use colored, highlighted, anchored local Parts.
-- They do not collide, are never part of the manufactured assembly,
-- and are entirely resizeable with the camera.
local function makePart(parent:Instance,name:string,color:Color3,shape:Enum.PartType):Part
	local p=Instance.new("Part")
	p.Name=name
	p.Shape=shape
	p.Anchored=true
	p.CanCollide=false
	p.CanTouch=false
	p.CanQuery=true
	p.CastShadow=false
	p.Material=Enum.Material.SmoothPlastic
	p.Transparency=1
	p.Color=color
	p.Parent=parent
	return p
end

local function highlight(model:Model,color:Color3):Highlight
	local h=Instance.new("Highlight")
	h.Name="HandleHighlight"
	h.Adornee=model
	h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
	h.FillColor=color
	h.FillTransparency=0
	h.OutlineTransparency=1
	h.Enabled=false
	h.Parent=model
	return h
end

-- SelectionBox provides explicit geometric grip borders, leaving
-- Highlights responsible only for solid color fill. It does not affect
-- input, physics, or the user's compiled stock.
local function outline(part:BasePart,color:Color3,parent:Instance):SelectionBox
	local selection=Instance.new("SelectionBox")
	selection.Name=part.Name.."_Border"
	selection.Adornee=part
	selection.Color3=color
	selection.LineThickness=0.014
	selection.SurfaceTransparency=1
	selection.Transparency=0.18
	selection.Visible=false
	selection.Parent=parent
	return selection
end

local function newArrow(folder:Folder,name:string,color:Color3)
	local model=Instance.new("Model")
	model.Name=name
	model.Parent=folder
	local stem=makePart(model,"Shaft",color,Enum.PartType.Cylinder)
	-- Reuse the existing artist-authored mesh rather than constructing
	-- mismatched wedges or guessing a ConeHandleAdornment orientation.
	local tip=ConeTemplate:Clone()
	tip.Name="Arrowhead"
	tip.Anchored=true
	tip.CanCollide=false
	tip.CanTouch=false
	tip.CanQuery=true
	tip.CastShadow=false
	tip.Material=Enum.Material.SmoothPlastic
	tip.Color=color
	tip.Transparency=1
	tip.Parent=model
	-- Never outline move grips with SelectionBox: it outlines a MeshPart's
	-- bounding cube, not the actual cone. Those boxes were the unwanted
	-- colored squares around each arrowhead.
	return {model=model,part=tip,stem=stem,tip=tip,
		highlight=highlight(model,color)}
end

local function newScale(folder:Folder,name:string,color:Color3)
	local model=Instance.new("Model")
	model.Name=name
	model.Parent=folder
	local cube=makePart(model,"ScaleCube",color,Enum.PartType.Block)
	return {model=model,part=cube,highlight=highlight(model,color),
		border=outline(cube,color,model)}
end

local function placeArrow(grip,center:Vector3,direction:Vector3,
	extent:number,unit:number)
	-- Same length on X/Y/Z, just beyond the largest stock face.
	-- Keep the outward tip accessible while reducing screen clutter.
	local shaftLength=math.max(extent+unit*1.8,unit*4.5)
	local tipLength=unit*1.05
	local headWidth=unit*0.7
	local shaftEnd=center+direction*shaftLength
	local tipCenter=shaftEnd+direction*(tipLength*0.5)
	-- Roblox cylinders extend along local X. LookAt local -Z points
	-- along the axis; this explicit Y rotation puts local X on -Z.
	local stemCenter=center+direction*(shaftLength*0.5)
	grip.stem.Size=Vector3.new(shaftLength,unit*0.10,unit*0.10)
	grip.stem.CFrame=CFrame.lookAt(stemCenter,stemCenter+direction)
		*CFrame.Angles(0,math.pi/2,0)
	grip.tip.Size=Vector3.new(headWidth,tipLength,headWidth)
	-- Cone mesh local +Y -> world outward axis. The -90deg X
	-- correction is required for this mesh, unlike ConeHandleAdornment.
	grip.tip.CFrame=CFrame.lookAt(tipCenter,tipCenter+direction)
		*CFrame.Angles(-math.pi/2,0,0)
	grip.shaftStart=center
	grip.shaftEnd=shaftEnd
	grip.arrowTip=shaftEnd+direction*tipLength
end

-- A ring is a local-only Model of small solid cylindrical segments.
-- Native ArcHandles are unsuitable because they cannot be resized to
-- the camera's zoom. We keep the existing Part raycast/planeRadial
-- dragging and add screen-space circle picking for generous hit targets.
local function newRotationRing(folder:Folder,name:string,color:Color3,anchor:BasePart)
	local model=Instance.new("Model")
	model.Name=name
	model.Parent=folder
	local segments={}
	for i=1,RING_SAMPLES do
		local segment=makePart(model,"Arc_"..i,color,Enum.PartType.Cylinder)
		segment.Transparency=1
		segment.CanQuery=false
		table.insert(segments,segment)
	end
	-- Rotation is rendered by the actual Neon cylinder Parts.
	-- No Highlight, adornment border, or overlapping glow model.
	for _,segment in ipairs(segments) do
		segment.Material=Enum.Material.Neon
	end
	return {model=model,segments=segments,part=segments[1]}
end

local function ringRadius(size:Vector3,unit:number):number
	-- One bounding-sphere radius for ALL axes. Per-axis projected
	-- dimensions used to produce three mismatched ring sizes.
	return size.Magnitude*0.5+unit*3.5
end

local function screenSegmentDistance(point:Vector2,a:Vector2,b:Vector2):number
	local delta=b-a
	local squared=delta:Dot(delta)
	if squared<1e-5 then return math.huge end
	local t=math.clamp((point-a):Dot(delta)/squared,0,1)
	return (point-(a+delta*t)).Magnitude
end

-- Project the actual rendered parts onto the viewport for accurate
-- pointer hit tests. Hits are matched to visible geometry, not to a large
-- invisible ball, and overlapping handles compete by pixel distance.
local function project(camera:Camera,world:Vector3):(Vector2?,number?)
	local p=camera:WorldToViewportPoint(world)
	if p.Z<=0 then return nil,nil end
	return Vector2.new(p.X,p.Y),p.Z
end

local function worldPixels(camera:Camera,world:Vector3,worldRadius:number):number
	local a=project(camera,world)
	local b=project(camera,world+camera.CFrame.RightVector*worldRadius)
	if not a or not b then return 0 end
	return (b-a).Magnitude
end

local function projectedSegment(point:Vector2,a:Vector2,b:Vector2):(number,number)
	local d=b-a
	local len=d:Dot(d)
	if len<1e-5 then return (point-a).Magnitude,0 end
	local t=math.clamp((point-a):Dot(d)/len,0,1)
	return (point-(a+d*t)).Magnitude,t
end

-- Project the eight corners of a Scale cube and test its actual 2D
-- footprint. This avoids enlarged box hit targets near adjacent grips.
-- Screen-space scale hit based on the actual projected cube, not a
-- giant invisible selection radius.
local function scaleDistance(camera:Camera,part:BasePart,pointer:Vector2):number
	local half=part.Size*0.5
	local points={}
	for _,x in ipairs({-1,1}) do
		for _,y in ipairs({-1,1}) do
			for _,z in ipairs({-1,1}) do
				local p=project(camera,part.CFrame:PointToWorldSpace(
					Vector3.new(x*half.X,y*half.Y,z*half.Z)))
				if not p then return math.huge end
				table.insert(points,p)
			end
		end
	end
	table.sort(points,function(a,b)
		return a.X==b.X and a.Y<b.Y or a.X<b.X
	end)
	local function cross(a:Vector2,b:Vector2,c:Vector2):number
		return (b.X-a.X)*(c.Y-a.Y)-(b.Y-a.Y)*(c.X-a.X)
	end
	local hull={}
	for _,p in ipairs(points) do
		while #hull>=2 and cross(hull[#hull-1],hull[#hull],p)<=0 do
			table.remove(hull)
		end
		table.insert(hull,p)
	end
	local lowerCount=#hull
	for i=#points-1,1,-1 do
		local p=points[i]
		while #hull>lowerCount and cross(hull[#hull-1],hull[#hull],p)<=0 do
			table.remove(hull)
		end
		table.insert(hull,p)
	end
	if #hull<3 then return math.huge end
	local inside=true
	local nearest=math.huge
	for i=1,#hull-1 do
		local p,q=hull[i],hull[i+1]
		if cross(p,q,pointer)<0 then inside=false end
		nearest=math.min(nearest,screenSegmentDistance(pointer,p,q))
	end
	return if inside then 0 else nearest
end

local function moveDistance(camera:Camera,grip,pointer:Vector2):number
	local pivot=project(camera,grip.shaftStart)
	local shaftEnd=project(camera,grip.shaftEnd)
	local tip=project(camera,grip.arrowTip)
	if not pivot or not shaftEnd or not tip then return math.huge end
	local shaftDistance,shaftT=projectedSegment(pointer,pivot,shaftEnd)
	-- Don't let every shaft claim the pivot where all three converge.
	local pivotClearance=math.min(0.18,10/math.max((shaftEnd-pivot).Magnitude,1))
	local score=math.huge
	if shaftT>pivotClearance then
		local width=worldPixels(camera,grip.stem.Position,grip.stem.Size.Y*0.5)
		score=math.max(0,shaftDistance-width)
	end
	local headDistance,headT=projectedSegment(pointer,shaftEnd,tip)
	local baseRadius=worldPixels(camera,grip.tip.Position,grip.tip.Size.X*0.5)
	-- Cone tapers from its base at shaftEnd to its outward tip.
	local headWidth=baseRadius*(1-headT)
	score=math.min(score,math.max(0,headDistance-headWidth))
	return score
end

local function layoutRing(grip,cf:CFrame,radius:number,thickness:number,
	tint:Color3)
	local axis=cf:VectorToWorldSpace(grip.normal).Unit
	local u=cf:VectorToWorldSpace(grip.radial).Unit
	local v=axis:Cross(u).Unit
	local points={}
	for i=0,RING_SAMPLES-1 do
		local a=i*2*math.pi/RING_SAMPLES
		table.insert(points,cf.Position+(u*math.cos(a)+v*math.sin(a))*radius)
	end
	grip.ringPoints=points
	grip.ringRadius=radius
	grip.ringFrame=cf
	for i,part in ipairs(grip.segments) do
		local a=points[i]
		local b=points[i%RING_SAMPLES+1]
		local tangent=b-a
		local midpoint=(a+b)*0.5
		-- Cylinder Parts use local X for the long axis.
		part.CFrame=CFrame.lookAt((a+b)*0.5,b)*CFrame.Angles(0,math.pi/2,0)
		part.Size=Vector3.new(tangent.Magnitude,thickness,thickness)
		part.Color=tint
	end
end

-- Screen-sized center marker inspired by Studio's transform pivot.
-- Billboard visuals never intersect rays or create extra physics parts.
local function newCenterMarker(parent:PlayerGui,origin:BasePart):BillboardGui
	local gui=Instance.new("BillboardGui")
	gui.Name="FORM_MovePivotMarker"
	gui.Adornee=origin
	gui.Size=UDim2.fromOffset(18,18)
	gui.AlwaysOnTop=true
	gui.Enabled=false
	gui.Parent=parent
	local circle=Instance.new("Frame")
	circle.Name="CenterCircle"
	circle.AnchorPoint=Vector2.new(0.5,0.5)
	circle.Position=UDim2.fromScale(0.5,0.5)
	circle.Size=UDim2.fromOffset(10,10)
	circle.BackgroundColor3=Color3.fromRGB(236,244,247)
	circle.BorderSizePixel=0
	circle.Parent=gui
	local round=Instance.new("UICorner")
	round.CornerRadius=UDim.new(1,0)
	round.Parent=circle
	return gui
end

local function newMeasurement(playerGui: PlayerGui)
	local gui = Instance.new("BillboardGui")
	gui.Name = "FORM_TransformMeasurement"
	gui.Size = UDim2.fromOffset(126, 30)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 0.18, 0)
	gui.AlwaysOnTop = true
	gui.Enabled = false
	gui.Parent = playerGui
	local label = Instance.new("TextLabel")
	label.Name = "Distance"
	label.BackgroundColor3 = Color3.fromRGB(20, 25, 29)
	label.BackgroundTransparency = 0.12
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Code
	label.TextSize = 15
	label.TextColor3 = Color3.fromRGB(242, 245, 247)
	label.Text = ""
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = label
	return gui, label
end

function TransformGizmo.new(playerGui: PlayerGui, document, onChange)
	local folder = Instance.new("Folder")
	folder.Name = "FORM_TransformGrips"
	folder.Parent = workspace
	local adornmentOrigin=Instance.new("Part")
	adornmentOrigin.Name="FORM_GizmoAdornmentOrigin"
	adornmentOrigin.Size=Vector3.one*0.05
	adornmentOrigin.CFrame=CFrame.identity
	adornmentOrigin.Transparency=1
	adornmentOrigin.Anchored=true
	adornmentOrigin.CanCollide=false
	adornmentOrigin.CanTouch=false
	adornmentOrigin.CanQuery=false
	adornmentOrigin.CastShadow=false
	adornmentOrigin.Parent=folder
	local measurement, measurementText = newMeasurement(playerGui)
	local centerOrigin=adornmentOrigin:Clone()
	centerOrigin.Name="FORM_MovePivotOrigin"
	centerOrigin.Parent=folder
	local centerMarker = newCenterMarker(playerGui,centerOrigin)
	local self = setmetatable({
		document = document, onChange = onChange, folder = folder,
		adornmentOrigin=adornmentOrigin,
		
		grips = {}, lookup = {}, connections = {},
		mode = "Move", hidden = false, component = nil, index = nil,
		dragStart = nil, dragChanged = false, hovered = nil, visualFrame = nil, visualSize = nil,
		measurement = measurement, measurementText = measurementText,
		centerMarker=centerMarker,centerOrigin=centerOrigin,
	}, TransformGizmo)

	for _,spec in ipairs(MOVE_AXES) do
		local arrow=newArrow(folder,"Move_"..spec.axis,spec.color)
		local grip={
			model=arrow.model,part=arrow.part,stem=arrow.stem,tip=arrow.tip,
			highlight=arrow.highlight,baseColor=spec.color,hoverAlpha=0,
			normal=spec.normal,axis=spec.axis,mode="Move",
		}
		table.insert(self.grips,grip)
		self.lookup[grip.stem]=grip
		self.lookup[grip.tip]=grip
	end
	for _,spec in ipairs(AXES) do
		local handle=newScale(folder,"Scale_"..spec.name,spec.color)
		local grip={
			model=handle.model,part=handle.part,highlight=handle.highlight,
			border=handle.border,baseColor=spec.color,hoverAlpha=0,
			normal=spec.normal,axis=spec.axis,mode="Scale",
		}
		table.insert(self.grips,grip)
		self.lookup[grip.part]=grip
	end
	self.rotationGrips={}
	for _,spec in ipairs(ROTATIONS) do
		local ring=newRotationRing(folder,"Rotate_"..spec.axis,spec.color,adornmentOrigin)
		local grip={
			model=ring.model,part=ring.part,segments=ring.segments,
			baseColor=spec.color,hoverAlpha=0,
			normal=spec.normal,radial=spec.radial,axis=spec.axis,
			mode="Rotate",ringPoints={},ringRadius=0,ringFrame=nil,
			ringThickness=0,
		}
		self.rotationGrips[spec.axis]=grip
		table.insert(self.grips,grip)
		for _,part in ipairs(grip.segments) do self.lookup[part]=grip end
	end

	local function connect(signal, fn)
		table.insert(self.connections, signal:Connect(fn))
	end

	local function pick(point:Vector2)
		if self.hidden or not self.component then return nil end
		local camera=workspace.CurrentCamera
		if not camera then return nil end
		local nearest=nil
		local closest=math.huge
		for _,grip in ipairs(self.grips) do
			if grip.mode~=self.mode then continue end
			local distance=math.huge
			local threshold=0
			if grip.mode=="Move" then
				if not grip.shaftStart then continue end
				distance=moveDistance(camera,grip,point)
				threshold=SHAFT_HIT_PIXELS
			elseif grip.mode=="Scale" then
				distance=scaleDistance(camera,grip.part,point)
				threshold=3
			else
				threshold=RING_HIT_PIXELS
				for i,a in ipairs(grip.ringPoints) do
					local b=grip.ringPoints[i%#grip.ringPoints+1]
					local pa=project(camera,a)
					local pb=project(camera,b)
					if pa and pb then
						local d=screenSegmentDistance(point,pa,pb)
						-- Account for the visible cylinder width, not a
						-- blanket 13-pixel radius around the entire ring.
						local radius=worldPixels(camera,(a+b)*0.5,
							grip.ringThickness*0.5)
						distance=math.min(distance,math.max(0,d-radius))
					end
				end
			end
			if distance<=threshold and distance<closest then
				closest=distance
				nearest=grip
			end
		end
		return nearest
	end

	local function begin(grip, point: Vector2)
		if self.hidden or not self.component or not self.index then return end
		local node = self.component.nodes[self.index]
		if not node then return end
		local cf = frame(node)
		local direction = cf:VectorToWorldSpace(grip.normal)
		local pivot = node.position
		local radial = if grip.mode == "Rotate"
			then cf:VectorToWorldSpace(grip.radial) else nil
		self.dragStart = {
			component = self.component, index = self.index,
			position = node.position, size = node.size, rotation = node.rotation,
			grip = grip, direction = direction, pivot = pivot,
			initialParameter = if grip.mode ~= "Rotate" then axisParameter(point, pivot, direction) else nil,
			initialRadial = if radial then (planeRadial(point, pivot, direction) or radial) else nil,
			lastRotationAngle = 0,
		}
		self.dragChanged = false
		self.hovered = grip
		self.measurement.Adornee = grip.part
		self.measurement.Enabled = true
		self.measurementText.Text = if grip.mode == "Rotate" then "0°" else "0 mm"
		self.onChange("begin", self.component, self.index)
	end

	local function drag(point: Vector2)
		local start = self.dragStart
		if not start then return end
		local position, size, rotation = nil, nil, nil
		if start.grip.mode ~= "Rotate" then
			local parameter = axisParameter(point, start.pivot, start.direction)
			if not parameter or not start.initialParameter then return end
			local distance = Quantize.snap(parameter - start.initialParameter, Quantize.Grid)
			if self.mode == "Move" then
				position = start.position + start.direction * distance
			elseif self.mode == "Scale" then
				local old=getAxis(start.size,start.grip.axis)
				local updated=math.clamp(Quantize.snap(old+distance,Quantize.Size),
					Quantize.MinSize,Quantize.MaxSize)
				size=putAxis(start.size,start.grip.axis,updated)
				position=start.position+start.direction*((updated-old)*0.5)
			end
		else
			local current = planeRadial(point, start.pivot, start.direction)
			if not current or not start.initialRadial then return end
			local initial = start.initialRadial
			local radians = math.atan2(start.direction:Dot(initial:Cross(current)), initial:Dot(current))
			-- The ring normal is expressed in the object's LOCAL frame.
			-- Multiplying the starting orientation by the local axis-angle
			-- preserves correct behavior after multiple-axis rotations.
			-- Snap the ANGLE around the selected axis, not each
			-- resulting Euler component. This preserves the local axis.
			local snappedRadians=math.rad(Quantize.snap(math.deg(radians),Quantize.Rotation))
			start.lastRotationAngle = snappedRadians
			rotation = rotateLocal(start.rotation,start.grip.normal,snappedRadians)
		end
		local ok = document:applyTransform(start.component, start.index, position, size, rotation,
			self.mode == "Scale", self.mode == "Rotate")
		if ok then
			local node = start.component.nodes[start.index]
			if node.position ~= start.position or node.size ~= start.size or node.rotation ~= start.rotation then
				self.dragChanged = true
			end
			local delta
			if self.mode == "Move" then
				delta = (node.position - start.position):Dot(start.direction)
			elseif self.mode == "Scale" then
				delta = getAxis(node.size,start.grip.axis)-getAxis(start.size,start.grip.axis)
			else
				-- Euler coordinates are coupled; show the actual ring drag,
				-- not the difference of one stored Euler component.
				delta = math.deg(start.lastRotationAngle)
			end
			self.measurementText.Text = if self.mode == "Rotate"
				then string.format("%+.0f°", delta)
				else string.format("%+.1f mm", delta * MM_PER_STUD)
			self:refresh()
			self.onChange("update", start.component, start.index)
		end
	end

	local function finish()
		local start = self.dragStart
		if not start then return end
		self.dragStart = nil
		self.measurement.Enabled = false
		self.measurement.Adornee = nil
		local changed = self.dragChanged
		self.dragChanged = false
		self.onChange("finish", start.component, start.index, changed)
		self:refresh()
	end

	connect(UserInputService.InputBegan, function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 or self.dragStart then return end
		local point = UserInputService:GetMouseLocation()
		local grip = pick(point)
		if grip and grip.mode == self.mode then
			begin(grip, point)
		end
	end)
	connect(UserInputService.InputChanged, function(input)
		if self.dragStart and input.UserInputType==Enum.UserInputType.MouseMovement then
			drag(UserInputService:GetMouseLocation())
		end
	end)
	connect(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then finish() end
	end)
	connect(RunService.RenderStepped, function(dt)
		-- Hover is resolved individually; a captured handle remains emphasized.
		if self.hidden or not self.component then
			self.hovered = nil
		elseif self.dragStart then
			self.hovered = self.dragStart.grip
		else
			self.hovered = pick(UserInputService:GetMouseLocation())
		end
		self:refresh(dt)
	end)
	self._pick = pick
	return self
end

function TransformGizmo:isDragging(): boolean
	return self.dragStart ~= nil
end

function TransformGizmo:capturesPoint(point: Vector2): boolean
	if self.dragStart then return true end
	if self.hidden or not self.component then return false end
	return self._pick(point) ~= nil
end

function TransformGizmo:setMode(mode: string)
	if (mode ~= "Move" and mode ~= "Scale" and mode ~= "Rotate") or self.dragStart then return end
	self.mode, self.hidden = mode, false
	self:refresh()
end

function TransformGizmo:setHidden(hidden: boolean)
	if self.dragStart then return end
	self.hidden = hidden
	self:refresh()
end

function TransformGizmo:show(component, index: number)
	if self.component ~= component or self.index ~= index then
		self.visualFrame, self.visualSize = nil, nil
	end
	self.component, self.index = component, index
	self:refresh()
end

function TransformGizmo:hide()
	if self.dragStart then return end
	self.component, self.index = nil, nil
	self.visualFrame, self.visualSize, self.hovered = nil, nil, nil
	self:refresh()
end

function TransformGizmo:refresh(dt:number?)
	local node=if self.component and self.index then
		self.component.nodes[self.index] else nil
	local targetFrame=if node then frame(node) else nil
	local cf=targetFrame
	self.centerMarker.Enabled=(node~=nil and not self.hidden and self.mode=="Move")
	local size=if node then node.size else nil
	-- No transform easing: immediately track the authoritative node.
	self.visualFrame=targetFrame
	self.visualSize=size
	if cf then self.centerOrigin.CFrame=CFrame.new(cf.Position) end
	for _,grip in ipairs(self.grips) do
		local visible=node~=nil and not self.hidden and grip.mode==self.mode
		local target=if grip==self.hovered then 1 else 0
		grip.hoverAlpha=target
		local tint=grip.baseColor:Lerp(Color3.new(1,1,1),grip.hoverAlpha*0.38)
		if grip.highlight then
			grip.highlight.Enabled=visible
			grip.highlight.FillColor=tint
			grip.highlight.FillTransparency=0
			grip.highlight.OutlineTransparency=1
		end
		if grip.mode=="Scale" then
			grip.border.Visible=visible
			grip.border.Color3=tint
		end
		local parts=if grip.mode=="Move" then {grip.stem,grip.tip}
			elseif grip.mode=="Scale" then {grip.part} else grip.segments
		for _,part in ipairs(parts) do
			part.Transparency=if visible then 0
				else 1
			part.CanQuery=visible
			part.Color=if grip.mode=="Rotate" then grip.baseColor else tint
		end
		if not visible or not node or not cf or not size then
			if grip.mode=="Rotate" then
				grip.ringFrame=nil
				grip.ringPoints={}
			end
			continue
		end
		local unit=visualScale(cf.Position)
		if grip.mode=="Move" then
			local direction=cf:VectorToWorldSpace(grip.normal)
			placeArrow(grip,cf.Position,direction,
				math.max(size.X,size.Y,size.Z)*0.5,unit)
		elseif grip.mode=="Scale" then
			grip.part.CFrame=cf*CFrame.new(
				grip.normal*(getAxis(size,grip.axis)*0.5+unit*1.5))
			grip.part.Size=Vector3.one*unit*1.12
		else
			-- The dragged ring remains at its initial orientation;
			-- the workpiece rotates but its reference circle doesn't.
			local basis=cf
			local dimensions=size
			if self.dragStart and self.dragStart.grip==grip then
				local start=self.dragStart
				basis=CFrame.new(start.position)*CFrame.fromOrientation(
					math.rad(start.rotation.X),math.rad(start.rotation.Y),
					math.rad(start.rotation.Z))
				dimensions=start.size
			end
			local radius=ringRadius(dimensions,unit)
			local thickness=math.max(unit*0.27,0.008)
			local old=grip.ringFrame
			local changed=not old
				or (old.Position-basis.Position).Magnitude>0.0005
				or (old.LookVector-basis.LookVector).Magnitude>0.0005
				or (old.UpVector-basis.UpVector).Magnitude>0.0005
				or math.abs(radius-grip.ringRadius)>0.0005
				or math.abs(thickness-grip.ringThickness)>0.0005
			if changed then
				layoutRing(grip,basis,radius,thickness,grip.baseColor)
				grip.ringThickness=thickness
			end
		end
	end
end

function TransformGizmo:destroy()
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	self.folder:Destroy()
	self.measurement:Destroy()
	self.centerMarker:Destroy()
end

return TransformGizmo
