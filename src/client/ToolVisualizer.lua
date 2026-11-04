--!strict
-- Transient, pooled tool preview. No EditableMesh, no Boolean or physics work
-- runs under the cursor. One tinted solid plus one outline ring/edge marker.
local Visualizer = {}
Visualizer.__index = Visualizer
local AMBER = Color3.fromRGB(245, 177, 105)
local CYAN = Color3.fromRGB(95, 217, 220)

local function part(name: string, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = AMBER
	p.Transparency = 1
	p.Size = Vector3.one * 0.05
	p.Parent = parent
	return p
end

function Visualizer.new(playerGui: PlayerGui)
	local folder = Instance.new("Folder")
	folder.Name = "FORM_FabricationIndicators"
	folder.Parent = workspace
	local ghost = part("RemovalVolume", folder)
	local ringAnchor = part("RingAnchor", folder)
	local edgeLine = part("EdgeIndicator", folder)
	local faceLines = {}
	for i=1,64 do
		local line=part("FaceBoundary_"..i,folder)
		table.insert(faceLines,line)
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "VolumeHighlight"
	highlight.Adornee = ghost
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.OutlineColor = AMBER
	highlight.FillColor = AMBER
	highlight.FillTransparency = 0.84
	highlight.OutlineTransparency = 0.1
	highlight.Enabled = false
	highlight.Parent = folder
	local ring = Instance.new("CylinderHandleAdornment")
	ring.Name = "DrillPerimeter"
	ring.Adornee = ringAnchor
	ring.Radius = 0.1
	ring.InnerRadius = 0.09
	ring.Height = 0.007
	ring.Angle = 360
	ring.Color3 = CYAN
	ring.Transparency = 0
	ring.AlwaysOnTop = false
	ring.Visible = false
	ring.Parent = playerGui

	local label = Instance.new("BillboardGui")
	label.Name = "ToolDimensionBadge"
	label.Adornee = ringAnchor
	label.AlwaysOnTop = true
	label.StudsOffsetWorldSpace = Vector3.new(0, 0.35, 0)
	label.Size = UDim2.fromOffset(165, 26)
	label.Enabled = false
	label.Parent = playerGui
	local display = Instance.new("TextLabel")
	display.Size = UDim2.fromScale(1, 1)
	display.BackgroundColor3 = Color3.fromRGB(31, 39, 46)
	display.BackgroundTransparency = 0.12
	display.TextColor3 = Color3.fromRGB(233, 244, 245)
	display.Font = Enum.Font.Code
	display.TextSize = 12
	display.Parent = label
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = display
	return setmetatable({
		root = folder, ghost = ghost, edgeLine = edgeLine, faceLines=faceLines,
		ringAnchor = ringAnchor, ring = ring,
		highlight = highlight, label = label, display = display,
	}, Visualizer)
end

function Visualizer:hide()
	self.ghost.Transparency = 1
	self.edgeLine.Transparency = 1
	self.highlight.Enabled = false
	self.ring.Visible = false
	self.label.Enabled = false
	for _,line in ipairs(self.faceLines) do line.Transparency=1 end
end

local function segment(p: Part, a: Vector3, b: Vector3, thickness: number)
	local delta = b - a
	if delta.Magnitude < 1e-5 then p.Transparency = 1 return end
	p.Size = Vector3.new(thickness, thickness, delta.Magnitude)
	p.CFrame = CFrame.lookAt((a + b) / 2, b)
	p.Transparency = 0
end

function Visualizer:volume(frame: CFrame, size: Vector3, shape: Enum.PartType, caption: string, color: Color3?)
	self.ghost.Shape = shape
	self.ghost.Size = size
	self.ghost.CFrame = frame
	self.ghost.Color = color or AMBER
	self.ghost.Transparency = 0.79
	self.highlight.FillColor = color or AMBER
	self.highlight.OutlineColor = color or AMBER
	self.highlight.Enabled = true
	self.ringAnchor.CFrame = CFrame.new(frame.Position)
	self.ring.Visible = false
	self.edgeLine.Transparency = 1
	for _,line in ipairs(self.faceLines) do line.Transparency=1 end
	self.display.Text = caption
	self.label.Enabled = true
end

function Visualizer:drill(pose: CFrame, node, x: number, z: number,
	diameter: number, depth: number, through: boolean)
	local top = node.size.Y / 2
	local penetration = if through then node.size.Y + 0.08
		else math.min(depth, node.size.Y) + 0.04
	local centerY = if through then 0 else top - penetration / 2 + 0.04
	self:volume(
		pose * CFrame.new(x, centerY, z) * CFrame.Angles(0, 0, math.pi / 2),
		Vector3.new(penetration, diameter, diameter), Enum.PartType.Cylinder,
		string.format("Ø %.0f mm  ·  %s", diameter * 280,
			if through then "THROUGH" else string.format("%.0f mm", depth * 280)),
		CYAN
	)
	self.ringAnchor.CFrame = pose * CFrame.new(x, top + 0.025, z)
	self.ring.Radius = diameter / 2
	self.ring.InnerRadius = math.max(0, diameter / 2 - math.clamp(diameter * 0.08, 0.005, 0.02))
	self.ring.Visible = true
end

function Visualizer:drillFace(pose:CFrame,origin:Vector3,normal:Vector3,
	diameter:number,depth:number,through:boolean,maxDepth:number)
	local outward=pose:VectorToWorldSpace(normal).Unit
	local start=pose:PointToWorldSpace(origin)
	local penetration=if through then maxDepth*2+0.08 else depth+0.04
	local center=start-outward*(penetration/2-0.04)
	self:volume(CFrame.lookAt(center,center-outward)*CFrame.Angles(0,math.pi/2,0),
		Vector3.new(penetration,diameter,diameter),Enum.PartType.Cylinder,
		string.format("Ø %.0f mm · %s",diameter*280,
			if through then "THROUGH" else string.format("%.0f mm",depth*280)),CYAN)
	self.ringAnchor.CFrame=CFrame.lookAt(start+outward*0.018,start-outward)
	self.ring.Radius=diameter/2
	self.ring.InnerRadius=math.max(0,diameter/2-math.clamp(diameter*0.08,0.005,0.02))
	self.ring.Visible=true
end

function Visualizer:inset(pose: CFrame, node, margin: number, depth: number)
	local width = node.size.X - margin * 2
	local length = node.size.Z - margin * 2
	if width <= 0 or length <= 0 then self:hide() return end
	local penetration = math.min(depth, node.size.Y) + 0.04
	local center = pose * CFrame.new(0, node.size.Y / 2 - penetration / 2 + 0.04, 0)
	self:volume(center, Vector3.new(width, penetration, length),
		Enum.PartType.Block, string.format("INSET  %.0f mm  ·  DEPTH %.0f mm", margin * 280, depth * 280))
end

function Visualizer:grooveFace(pose:CFrame,a:Vector3,b:Vector3,
	normal:Vector3,width:number,depth:number,through:boolean,maxDepth:number)
	local forward=b-a
	if forward.Magnitude<0.02 then self:hide() return end
	local outward=normal.Unit
	local right=outward:Cross(forward.Unit).Unit
	local back=right:Cross(outward).Unit
	local penetration=if through then maxDepth*2+0.08 else depth+0.04
	local center=(a+b)/2-outward*(penetration/2-0.04)
	self:volume(pose*CFrame.fromMatrix(center,right,outward,back),
		Vector3.new(width,penetration,forward.Magnitude+width),Enum.PartType.Block,
		string.format("%s  %.0f × %.0f mm",if through then "KERF" else "GROOVE",
			width*280,depth*280))
end

function Visualizer:groove(pose: CFrame, node, a: Vector2, b: Vector2, width: number, depth: number)
	local v = Vector3.new(b.X - a.X, 0, b.Y - a.Y)
	if v.Magnitude < 0.02 then self:hide() return end
	local penetration = math.min(depth, node.size.Y) + 0.04
	local center = Vector3.new((a.X + b.X) / 2, node.size.Y / 2 - penetration / 2 + 0.04,
		(a.Y + b.Y) / 2)
	local cf = pose * CFrame.lookAt(center, center + v)
	self:volume(cf, Vector3.new(width, penetration, v.Magnitude + width),
		Enum.PartType.Block, string.format("GROOVE  %.0f × %.0f mm", width * 280, depth * 280))
end

function Visualizer:meshEdge(part:BasePart,edge,width:number)
	self:hide()
	local a=part.CFrame:PointToWorldSpace(edge.a)
	local b=part.CFrame:PointToWorldSpace(edge.b)
	self.edgeLine.Color=CYAN
	segment(self.edgeLine,a,b,math.clamp(width*0.25,0.009,0.04))
	self.ringAnchor.CFrame=CFrame.new((a+b)/2)
	self.display.Text=string.format("FILE EDGE  ·  %.0f mm",width*280)
	self.label.Enabled=true
end

function Visualizer:meshFace(part:BasePart,loop:{Vector3},margin:number,depth:number)
	self:hide()
	local center=Vector3.zero
	for i,p in ipairs(loop) do
		local q=loop[i%#loop+1]
		if i>#self.faceLines then break end
		local a=part.CFrame:PointToWorldSpace(p)
		local b=part.CFrame:PointToWorldSpace(q)
		local line=self.faceLines[i]
		line.Color=CYAN
		segment(line,a,b,0.013)
		center+=a
	end
	self.ringAnchor.CFrame=CFrame.new(center/#loop)
	self.display.Text=string.format("FACE INSET  %.0f / %.0f mm",margin*280,depth*280)
	self.label.Enabled=true
end

function Visualizer:file(pose: CFrame, node, edge: string, width: number)
	self.ghost.Transparency = 1
	self.highlight.Enabled = false
	self.ring.Visible = false
	local hx, hy, hz = node.size.X / 2, node.size.Y / 2, node.size.Z / 2
	local a, b
	if edge == "X+" then
		a,b = Vector3.new(hx,hy,-hz),Vector3.new(hx,hy,hz)
	elseif edge == "X-" then
		a,b = Vector3.new(-hx,hy,-hz),Vector3.new(-hx,hy,hz)
	elseif edge == "Z+" then
		a,b = Vector3.new(-hx,hy,hz),Vector3.new(hx,hy,hz)
	else
		a,b = Vector3.new(-hx,hy,-hz),Vector3.new(hx,hy,-hz)
	end
	local worldA, worldB = pose:PointToWorldSpace(a), pose:PointToWorldSpace(b)
	self.edgeLine.Color = CYAN
	segment(self.edgeLine, worldA, worldB, math.clamp(width * 0.25, 0.012, 0.045))
	self.ringAnchor.CFrame = CFrame.new((worldA + worldB) / 2)
	self.display.Text = string.format("FILE %s  ·  %.0f mm", edge, width * 280)
	self.label.Enabled = true
end

function Visualizer:destroy()
	self.root:Destroy()
	self.ring:Destroy()
	self.label:Destroy()
end

return Visualizer
