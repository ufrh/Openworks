--!strict
-- Camera-adaptive center-origin XYZ move arrows, face-scale grips, and
-- three clickable wireframe rotation rings. Visible geometry is adornments.
-- Three center-origin move arrows, six offset scale spheres, and three
-- clickable wireframe rotation rings.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local FORM = ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM")
local Quantize = require(FORM.Quantize)

local TransformGizmo = {}
TransformGizmo.__index = TransformGizmo

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
local RING_SAMPLES = 72
local RING_HIT_PIXELS = 11
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

-- Visible grips are adornments. Invisible Parts remain raycast targets,
-- preserving the existing reliable move/scale/rotate drag calculations.
local function makePart(parent:Instance,name:string,color:Color3,shape:Enum.PartType):Part
	local p=Instance.new("Part")
	p.Name=name
	p.Shape=shape
	p.Anchored=true
	p.CanCollide=false
	p.CanTouch=false
	p.CanQuery=true
	p.CastShadow=false
	p.Transparency=1
	p.Color=color
	p.Parent=parent
	return p
end

local function adorn(parent:Instance,anchor:BasePart,
	class:string,name:string,color:Color3)
	local a=Instance.new(class)
	a.Name=name
	a.Adornee=anchor
	a.AlwaysOnTop=false
	a.Color3=color
	a.Transparency=0.04
	a.Visible=false
	a.Parent=parent
	return a
end

-- Move shafts and heads are one world-space wireframe, with no local
-- cone orientation assumptions. The invisible Parts are click targets only.
local function newArrow(folder:Folder,decor:Instance,anchor:BasePart,
	name:string,color:Color3)
	local model=Instance.new("Model")
	model.Name=name
	model.Parent=folder
	local stem=makePart(model,"StemHit",color,Enum.PartType.Block)
	local tip=makePart(model,"TipHit",color,Enum.PartType.Ball)
	local drawing=adorn(decor,anchor,"WireframeHandleAdornment",
		name.."_Arrow",color)
	drawing.AlwaysOnTop=true
	drawing.Thickness=2.6
	drawing.CFrame=CFrame.identity
	drawing.Scale=Vector3.one
	return {model=model,part=tip,stem=stem,tip=tip,arrow=drawing}
end

local function newSphere(folder:Folder,decor:Instance,anchor:BasePart,
	name:string,color:Color3)
	local model=Instance.new("Model")
	model.Name=name
	model.Parent=folder
	local p=makePart(model,"SphereHit",color,Enum.PartType.Ball)
	return {model=model,part=p,
		marker=adorn(decor,anchor,"SphereHandleAdornment",name.."_Sphere",color)}
end

-- A genuine wireframe ring is visible and selectable all around its
-- circumference. Rotation still uses the original planeRadial drag math.
local function ringPath(normal:Vector3,radial:Vector3)
	local across=normal:Cross(radial).Unit
	local points={}
	for i=0,RING_SAMPLES-1 do
		local angle=i*math.pi*2/RING_SAMPLES
		table.insert(points,radial*math.cos(angle)+across*math.sin(angle))
	end
	return points
end

local function newRotationGrip(folder:Folder,decor:Instance,anchor:BasePart,
	name:string,color:Color3,normal:Vector3,radial:Vector3)
	local model=Instance.new("Model")
	model.Name=name
	model.Parent=folder
	-- Existing invisible knob target remains as a fallback; whole ring
	-- circumference is targeted with the exact displayed world points.
	local p=makePart(model,"RingHit",color,Enum.PartType.Ball)
	local ring=adorn(decor,anchor,"WireframeHandleAdornment",name.."_Ring",color)
	ring.AlwaysOnTop=true
	ring.Thickness=2.8
	ring.CFrame=CFrame.identity
	ring.Scale=Vector3.one
	return {model=model,part=p,ring=ring,path=ringPath(normal,radial)}
end

local function placeArrow(grip,center:Vector3,direction:Vector3,
	extent:number,unit:number,highlighted:boolean)
	-- Draw the visible shaft FROM the actual world-space pivot.
	-- Define the arrowhead in world coordinates; every spoke terminates
	-- at a tip farther OUTWARD along the selected X/Y/Z axis.
	local shaftLength=math.max(extent+unit*4.5,unit*6)
	local tipLength=unit*1.25
	local headRadius=unit*0.65
	local shaftEnd=center+direction*shaftLength
	local tipPoint=shaftEnd+direction*tipLength
	local reference=if math.abs(direction.Y)<0.9 then Vector3.yAxis
		else Vector3.xAxis
	local u=direction:Cross(reference).Unit
	local v=direction:Cross(u).Unit
	local drawing=grip.arrow
	drawing:Clear()
	drawing.Color3=if highlighted then grip.baseColor:Lerp(Color3.new(1,1,1),0.32)
		else grip.baseColor
	drawing.Thickness=if highlighted then 3.5 else 2.6
	drawing:AddLine(center,shaftEnd)
	-- Six-sided cone wireframe: circular base and spokes to the one
	-- outward tip, making reversed/sideways cone heads impossible.
	local corners={}
	for i=0,5 do
		local angle=i*math.pi/3
		table.insert(corners,shaftEnd+
			(u*math.cos(angle)+v*math.sin(angle))*headRadius)
	end
	for i,point in ipairs(corners) do
		drawing:AddLine(point,tipPoint)
		drawing:AddLine(point,corners[i%#corners+1])
	end
	-- Invisible click targets stay OUTSIDE the component.
	local hitStart=center+direction*(extent+unit*0.5)
	local hitLength=math.max((shaftEnd-hitStart):Dot(direction),unit*0.7)
	local hitCenter=hitStart+direction*(hitLength*0.5)
	grip.stem.Size=Vector3.new(unit*0.4,unit*0.4,hitLength)
	grip.stem.CFrame=CFrame.lookAt(hitCenter,hitCenter+direction)
	grip.tip.Position=tipPoint
	grip.tip.Size=Vector3.one*unit*1.1
	-- Expose exact endpoints for smoke tests and future gizmo overlays.
	grip.shaftStart=center
	grip.shaftEnd=shaftEnd
	grip.arrowTip=tipPoint
end

local function ringRadius(size:Vector3,normal:Vector3,unit:number,axis:string)
	local perpendicular=Vector3.new(
		if math.abs(normal.X)>0.5 then 0 else size.X/2,
		if math.abs(normal.Y)>0.5 then 0 else size.Y/2,
		if math.abs(normal.Z)>0.5 then 0 else size.Z/2)
	local halfDiagonal=perpendicular.Magnitude
	-- Different offsets make the three rings individually legible.
	local extra=if axis=="X" then 2.5 elseif axis=="Y" then 3.5 else 4.5
	return halfDiagonal+unit*extra
end

local function screenSegmentDistance(point:Vector2,a:Vector2,b:Vector2)
	local segment=b-a
	local squared=segment:Dot(segment)
	if squared<0.0001 then return math.huge end
	local t=math.clamp((point-a):Dot(segment)/squared,0,1)
	return (point-(a+segment*t)).Magnitude
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
	local decorations=Instance.new("Folder")
	decorations.Name="FORM_TransformAdornments"
	decorations.Parent=playerGui
	local anchor=Instance.new("Part")
	anchor.Name="FORM_GizmoAdornmentOrigin"
	anchor.Anchored=true
	anchor.CanCollide=false
	anchor.CanTouch=false
	anchor.CanQuery=false
	anchor.CastShadow=false
	anchor.Transparency=1
	anchor.Size=Vector3.one*0.05
	anchor.CFrame=CFrame.identity
	anchor.Parent=workspace
	local measurement, measurementText = newMeasurement(playerGui)
	local self = setmetatable({
		document = document, onChange = onChange, folder = folder,
		decorations=decorations,anchor=anchor,
		grips = {}, lookup = {}, connections = {},
		mode = "Move", hidden = false, component = nil, index = nil,
		dragStart = nil, dragChanged = false, hovered = nil, visualFrame = nil, visualSize = nil,
		measurement = measurement, measurementText = measurementText,
	}, TransformGizmo)

	for _, spec in ipairs(MOVE_AXES) do
		local arrow = newArrow(folder,decorations,anchor,"Move_"..spec.axis,spec.color)
		local grip = {
			model = arrow.model, part = arrow.part, stem = arrow.stem, tip = arrow.tip,
			arrow=arrow.arrow,baseColor=spec.color,hoverAlpha=0,
			normal = spec.normal, axis = spec.axis, mode = "Move",
		}
		table.insert(self.grips, grip)
		self.lookup[grip.stem] = grip
		self.lookup[grip.tip] = grip
	end
	for _, spec in ipairs(AXES) do
		local sphere = newSphere(folder,decorations,anchor,"Scale_"..spec.name,spec.color)
		local grip = {
			model = sphere.model, part = sphere.part,
			marker=sphere.marker,baseColor=spec.color,hoverAlpha=0,
			normal = spec.normal, axis = spec.axis, mode = "Scale",
		}
		table.insert(self.grips, grip)
		self.lookup[grip.part] = grip
	end
	for _, spec in ipairs(ROTATIONS) do
		local control = newRotationGrip(folder,decorations,anchor,
			"Rotate_"..spec.axis,spec.color,spec.normal,spec.radial)
		local grip = {
			model = control.model, part = control.part,
			ring=control.ring,ringPath=control.path,baseColor=spec.color,
			hoverAlpha=0,normal=spec.normal,
			radial=spec.radial,axis=spec.axis,mode="Rotate",ringRadius=0,
			ringFrame=CFrame.identity,ringHighlighted=false,ringWorldPath={},
		}
		table.insert(self.grips, grip)
		self.lookup[grip.part] = grip
	end

	local function connect(signal, fn)
		table.insert(self.connections, signal:Connect(fn))
	end

	local function pick(point: Vector2)
		local camera=workspace.CurrentCamera
		if not camera then return nil end
		local ray=camera:ViewportPointToRay(point.X,point.Y)
		local params=RaycastParams.new()
		params.FilterType=Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances={folder}
		local hit=workspace:Raycast(ray.Origin,ray.Direction*2048,params)
		local proxy=if hit then self.lookup[hit.Instance] else nil
		if proxy and proxy.mode==self.mode then return proxy end
		if self.mode~="Rotate" or self.hidden or not self.component then
			return nil
		end
		-- The actual ring circumference is clickable, not just a single
		-- invisible sphere. Evaluate projected ring segments directly.
		local nearest=nil
		local closest=RING_HIT_PIXELS
		for _,grip in ipairs(self.grips) do
			if grip.mode~="Rotate" or not grip.ring.Visible then continue end
			local lastPoint=nil
			local firstPoint=nil
			local lastVisible=false
			local firstVisible=false
			for _,world in ipairs(grip.ringWorldPath) do
				local projection,visible=camera:WorldToViewportPoint(world)
				local screen=Vector2.new(projection.X,projection.Y)
				if lastPoint and visible and lastVisible then
					local distance=screenSegmentDistance(point,lastPoint,screen)
					if distance<closest then
						closest,nearest=distance,grip
					end
				end
				if not firstPoint then
					firstPoint,firstVisible=screen,visible
				end
				lastPoint,lastVisible=screen,visible
			end
			if lastPoint and firstPoint and lastVisible and firstVisible then
				local distance=screenSegmentDistance(point,lastPoint,firstPoint)
				if distance<closest then closest,nearest=distance,grip end
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
				local old = getAxis(start.size, start.grip.axis)
				local new = math.clamp(Quantize.snap(old + distance, Quantize.Grid),
					Quantize.MinSize, Quantize.MaxSize)
				size = putAxis(start.size, start.grip.axis, new)
				position = start.position + start.direction * ((new - old) / 2)
			end
		else
			local current = planeRadial(point, start.pivot, start.direction)
			if not current or not start.initialRadial then return end
			local initial = start.initialRadial
			local radians = math.atan2(start.direction:Dot(initial:Cross(current)), initial:Dot(current))
			rotation = putAxis(start.rotation, start.grip.axis,
				getAxis(start.rotation, start.grip.axis) + math.deg(radians))
		end
		local ok = document:applyTransform(start.component, start.index, position, size, rotation, self.mode == "Scale")
		if ok then
			local node = start.component.nodes[start.index]
			if node.position ~= start.position or node.size ~= start.size or node.rotation ~= start.rotation then
				self.dragChanged = true
			end
			local delta
			if self.mode == "Move" then
				delta = (node.position - start.position):Dot(start.direction)
			elseif self.mode == "Scale" then
				delta = getAxis(node.size, start.grip.axis) - getAxis(start.size, start.grip.axis)
			else
				delta = getAxis(node.rotation, start.grip.axis) - getAxis(start.rotation, start.grip.axis)
				if delta > 180 then delta -= 360 elseif delta < -180 then delta += 360 end
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

	-- GUI adornments can consume InputBegan as a processed UI click.
	-- Connect them directly as well as keeping screen-space ring picking,
	-- so Rotate actually begins dragging when the wireframe is clicked.
	for _,grip in ipairs(self.grips) do
		local handle=if grip.mode=="Move" then grip.arrow
			elseif grip.mode=="Rotate" then grip.ring else nil
		if handle then
			connect(handle.MouseButton1Down,function()
				if self.mode~=grip.mode or self.hidden or not self.component
					or self.dragStart then return end
				begin(grip,UserInputService:GetMouseLocation())
			end)
			connect(handle.MouseButton1Up,function()
				if self.dragStart and self.dragStart.grip==grip then finish() end
			end)
		end
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
		if self.dragStart and input.UserInputType == Enum.UserInputType.MouseMovement then
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
	if mode ~= "Move" and mode ~= "Scale" and mode ~= "Rotate" or self.dragStart then return end
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

function TransformGizmo:refresh(dt: number?)
	local node = if self.component and self.index
		then self.component.nodes[self.index] else nil
	local targetFrame = if node then frame(node) else nil
	local cf = targetFrame
	local size = if node then node.size else nil
	if node and targetFrame then
		-- Exponential smoothing is frame-rate independent. Source node stays snapped.
		local alpha = if dt then 1 - math.exp(-26 * dt) else (if self.visualFrame then 0 else 1)
		self.visualFrame = if self.visualFrame then self.visualFrame:Lerp(targetFrame, alpha) else targetFrame
		self.visualSize = if self.visualSize then self.visualSize:Lerp(node.size, alpha) else node.size
		cf = self.visualFrame
		size = self.visualSize
	else
		self.visualFrame, self.visualSize = nil, nil
	end
	for _, grip in ipairs(self.grips) do
		local hoverTarget = if grip == self.hovered then 1 else 0
		local hoverBlend = if dt then 1 - math.exp(-18 * dt) else 1
		grip.hoverAlpha += (hoverTarget - grip.hoverAlpha) * hoverBlend
		local tint=grip.baseColor:Lerp(Color3.new(1,1,1),grip.hoverAlpha*0.38)
		local visible=node~=nil and not self.hidden and grip.mode==self.mode
		for _,part in ipairs(if grip.mode=="Move" then {grip.stem,grip.tip}
			else {grip.part}) do
			part.Transparency=1
			part.CanQuery=visible
		end
		if grip.mode=="Move" then
			grip.arrow.Visible=visible
		elseif grip.mode=="Rotate" then
			grip.ring.Visible=visible
		else
			grip.marker.Color3=tint
			grip.marker.Visible=visible
		end
		if visible and node then
			local unit = visualScale(cf.Position)
			if grip.mode == "Move" then
				local direction=cf:VectorToWorldSpace(grip.normal)
				placeArrow(grip,cf.Position,direction,
					getAxis(size,grip.axis)/2,unit,grip==self.hovered)
			elseif grip.mode == "Scale" then
				grip.part.Position = cf:PointToWorldSpace(
					grip.normal*(getAxis(size,grip.axis)/2+unit*3))
				grip.part.Size = Vector3.one * unit * (1.35 + 0.18 * grip.hoverAlpha)
				grip.marker.CFrame=CFrame.new(grip.part.Position)
				grip.marker.Radius=grip.part.Size.X*0.5
			else
				local radius=ringRadius(size,grip.normal,unit,grip.axis)
				grip.ringFrame=cf
				grip.ringRadius=radius
				-- Render precisely the SAME world-space points that are
				-- used for projected mouse hit testing. No scaling/CFrame
				-- ambiguity in WireframeHandleAdornment paths.
				local points={}
				for _,localPoint in ipairs(grip.ringPath) do
					table.insert(points,cf:PointToWorldSpace(localPoint*radius))
				end
				grip.ringWorldPath=points
				grip.ring:Clear()
				grip.ring.Color3=if grip==self.hovered then tint else grip.baseColor
				grip.ring.Thickness=if grip==self.hovered then 4 else 2.8
				grip.ring:AddPath(points,true)
				grip.part.Position=cf:PointToWorldSpace(grip.radial*radius)
				grip.part.Size=Vector3.one*unit*1.75
			end
		end
	end
end

function TransformGizmo:destroy()
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	self.folder:Destroy()
	self.decorations:Destroy()
	self.anchor:Destroy()
	self.measurement:Destroy()
end

return TransformGizmo
