--!strict
-- FORM source document: editable material envelopes plus ordered fabrication history.
-- A component's origin is the minimum local corner of its uncut envelope,
-- while BasePart positioning continues to use the calculated center.
local Quantize = require(script.Parent.Quantize)
local MaterialVolume = require(script.Parent.MaterialVolume)
local SketchProfile = require(script.Parent.SketchProfile)
local Features = require(script.Parent.Features)

local Document = {}
Document.__index = Document

local KINDS = { Block = true, Cylinder = true, RoundedL = true }
local AXES = { X = true, Y = true, Z = true }

-- Authoritative feature constraint: a filed corner cannot share its
-- segment or junction with an interior smooth, regardless of UI entry.
local function nearSegment(point:Vector3,a:Vector3,b:Vector3):boolean
	local d=b-a
	local t=math.clamp((point-a):Dot(d)/math.max(d:Dot(d),1e-9),0,1)
	return (point-(a+d*t)).Magnitude<0.008
end
local function edgesTouch(a:Vector3,b:Vector3,c:Vector3,d:Vector3):boolean
	return nearSegment(a,c,d) or nearSegment(b,c,d)
		or nearSegment(c,a,b) or nearSegment(d,a,b)
end
local function adjacentOperation(component,a:Vector3,b:Vector3,kind:string):boolean
	for _,op in ipairs(component.operations) do
		if op.enabled==false or op.kind~=kind then continue end
		if edgesTouch(a,b,op.a,op.b) then return true end
	end
	return false
end

local function orientation(rotation: Vector3): CFrame
	return CFrame.fromOrientation(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
end

local function halfOffset(size: Vector3, rotation: Vector3): Vector3
	return orientation(rotation):VectorToWorldSpace(size * 0.5)
end

local function withAxis(vec: Vector3, axis: string, value: number): Vector3
	if axis == "X" then return Vector3.new(value, vec.Y, vec.Z) end
	if axis == "Y" then return Vector3.new(vec.X, value, vec.Z) end
	return Vector3.new(vec.X, vec.Y, value)
end

function Document.minCorner(node): Vector3
	return node.position - halfOffset(node.size, node.rotation)
end

local function defaultSize(kind: string): Vector3
	if kind == "Cylinder" then return Vector3.new(0.5, 0.4, 0.5) end
	if kind == "RoundedL" then return Vector3.new(0.25,0.25,0.20) end
	return Vector3.new(1, 0.4, 1)
end

function Document.new()
	return setmetatable({
		components = {}, order = {}, nextComponent = 0,
		nextNode = 0, nextOperation = 0,
	}, Document)
end

function Document:create(kind: string, minimumCorner: Vector3, name: string?, specifiedSize: Vector3?)
	assert(KINDS[kind], "Unknown FORM material: " .. tostring(kind))
	self.nextComponent += 1
	self.nextNode += 1
	local size = specifiedSize or defaultSize(kind)
	if typeof(size)~="Vector3" or not Quantize.isFinite(size.X)
		or not Quantize.isFinite(size.Y) or not Quantize.isFinite(size.Z)
		or math.min(size.X,size.Y,size.Z)<Quantize.MinSize-0.00001
		or math.max(size.X,size.Y,size.Z)>Quantize.MaxSize then
		return nil,"Component dimensions must be between 0.05 and 128 studs"
	end
	size=Quantize.vector(size,Quantize.Size)
	if not MaterialVolume.within(MaterialVolume.primitive(kind,size)) then
		return nil,"Material volume exceeds "..MaterialVolume.display(
			Quantize.MaxComponentVolume).." per component"
	end
	local node = {
		id = self.nextNode,
		kind = kind,
		position = Quantize.vector(minimumCorner, Quantize.Grid) + size * 0.5,
		size = size,
		rotation = Vector3.zero,
	}
	local component = {
		id = self.nextComponent, name = if typeof(name)=="string" and name:match("%S")
			then string.sub(name,1,64) else kind .. " " .. self.nextComponent,
		nodes = { node }, operations = {}, notes = "", revision = 1,
		materialVolume=MaterialVolume.primitive(kind,size),volumeExact=true,
	}
	self.components[component.id] = component
	table.insert(self.order, component.id)
	return component
end

-- A brand-new component begins as a user-authored outline, not stock.
-- Workspace X/Z bound the 2D sketch and Y is its first extrusion depth.
function Document:createSketchBody(name:string,ground:Vector3,
	workspaceSize:Vector3,outline:{Vector2},depth:number)
	local points,_,reason=SketchProfile.prepare(outline)
	if not points then return nil,reason end
	if not Quantize.isFinite(depth) or depth<Quantize.MinSize
		or depth>Quantize.MaxSize then
		return nil,"Sketch extrusion must be between 14 and 35,840 mm"
	end
	local w=workspaceSize.X
	local z=workspaceSize.Z
	for _,p in ipairs(points) do
		if math.abs(p.X)>w*0.5+0.001 or math.abs(p.Y)>z*0.5+0.001 then
			return nil,"Sketch outline must fit inside the placed grid"
		end
	end
	depth=Quantize.snap(depth,Quantize.Size)
	local plane=Quantize.vector(ground,Quantize.Grid)
	local node={
		id=self.nextNode+1,kind="SketchBody",
		position=plane+Vector3.new(w*0.5,depth*0.5,z*0.5),
		size=Vector3.new(w,depth,z),rotation=Vector3.zero,
		profileSize=Vector2.new(w,z),profilePoints=points,
	}
	local material=MaterialVolume.node(node)
	if not MaterialVolume.within(material) then
		return nil,"Sketched material exceeds "..MaterialVolume.display(
			Quantize.MaxComponentVolume)
	end
	self.nextNode+=1
	self.nextComponent+=1
	local component={
		id=self.nextComponent,
		name=if name:match("%S") then string.sub(name,1,64)
			else "Component "..self.nextComponent,
		nodes={node},operations={},notes="",revision=1,
		materialVolume=material,volumeExact=true,
		workspaceOrigin=plane,workspaceSize=workspaceSize,
	}
	self.components[component.id]=component
	table.insert(self.order,component.id)
	return component
end

-- Fabricated components may have cavities or recesses; avoid limiting
-- their bounding envelope. After a CSG operation, Preview checks the
-- actual compiled material volume and restores the last valid snapshot.
local function hasFabrication(component):boolean
	for _,op in ipairs(component.operations) do
		if op.enabled~=false then return true end
	end
	return component.nodes[1].kind=="RoundedL"
		or component.nodes[1].kind=="SketchBody"
end

local function withinCurrentVolume(component,size:Vector3):boolean
	local node=component.nodes[1]
	if node.kind=="SketchBody" then
		-- For an unmodified sketch the outline area is known exactly.
		-- Once boolean features exist, Preview validates compiled material.
		for _,op in ipairs(component.operations) do
			if op.enabled~=false then return true end
		end
		local candidate=table.clone(node)
		candidate.size=size
		return MaterialVolume.within(MaterialVolume.node(candidate))
	end
	if hasFabrication(component) then return true end
	return MaterialVolume.within(MaterialVolume.primitive(node.kind,size))
end

local function validateTransform(position: Vector3, size: Vector3, rotation: Vector3)
	for _, n in ipairs({
		position.X, position.Y, position.Z, size.X, size.Y, size.Z,
		rotation.X, rotation.Y, rotation.Z,
	}) do
		if not Quantize.isFinite(n) then return false, "Transform must contain finite numbers" end
	end
	if math.max(math.abs(position.X), math.abs(position.Y), math.abs(position.Z)) > Quantize.MaxPosition then
		return false, "Position must be within +/-512 studs"
	end
	if math.min(size.X, size.Y, size.Z) < Quantize.MinSize - 0.00001
		or math.max(size.X, size.Y, size.Z) > Quantize.MaxSize then
		return false, "Size must be between 0.05 and 128 studs"
	end
	return true, nil
end

function Document:editNode(component, index: number, field: string, axis: string?, value: number)
	local node = component.nodes[index]
	if not node then return false, "No node selected" end
	if typeof(value) ~= "number" or not Quantize.isFinite(value) then
		return false, "Enter a finite number"
	end
	if not axis or not AXES[axis] then return false, "Invalid axis" end
	local snapped = Quantize.snap(value, if field == "rotation" then Quantize.Rotation
		elseif field=="size" then Quantize.Size else Quantize.Size)
	local position, size, rotation = node.position, node.size, node.rotation
	if field == "position" then
		-- Numeric MIN fields edit a boundary coordinate, not the part's center.
		local minimum = withAxis(Document.minCorner(node), axis, snapped)
		position = minimum + halfOffset(size, rotation)
	elseif field == "size" then
		local minimum = Document.minCorner(node)
		size = withAxis(size, axis, snapped)
		if node.kind == "Cylinder" and axis ~= "Y" then
			size = Vector3.new(snapped, size.Y, snapped)
		end
		position = minimum + halfOffset(size, rotation)
	elseif field == "rotation" then
		rotation = withAxis(rotation, axis, snapped % 360)
	else
		return false, "Unknown FORM property"
	end
	local ok, reason = validateTransform(position, size, rotation)
	if not ok then return false, reason end
	if not withinCurrentVolume(component,size) then
		return false,"Material volume limit: "..MaterialVolume.display(Quantize.MaxComponentVolume)
	end
	node.position, node.size, node.rotation = position, size, rotation
	component.revision += 1
	return true, nil
end

function Document:applyTransform(component, index: number, position: Vector3?, size: Vector3?, rotation: Vector3?, preserveFaceAnchor: boolean?, preserveRotationPrecision: boolean?, moveSnap:number?)
	local node = component.nodes[index]
	if not node then return false, "No node selected" end
	local newSize = Quantize.vector(size or node.size, Quantize.Size)
	local incoming = rotation or node.rotation
	local newRotation = Vector3.new(
		(if preserveRotationPrecision then incoming.X else Quantize.snap(incoming.X, Quantize.Rotation)) % 360,
		(if preserveRotationPrecision then incoming.Y else Quantize.snap(incoming.Y, Quantize.Rotation)) % 360,
		(if preserveRotationPrecision then incoming.Z else Quantize.snap(incoming.Z, Quantize.Rotation)) % 360
	)
	if node.kind == "Cylinder" then
		local dx = math.abs(newSize.X - node.size.X)
		local dz = math.abs(newSize.Z - node.size.Z)
		local diameter = if dx >= dz then newSize.X else newSize.Z
		newSize = Vector3.new(diameter, newSize.Y, diameter)
	end
	local newPosition = position or node.position
	if position and not preserveFaceAnchor then
		-- Move the *local minimum corner* onto 0.05-grid coordinates,
		-- accounting for half-cell centers of odd-sized envelopes.
		local half = halfOffset(newSize, node.rotation)
		newPosition = Quantize.vector(position - half, moveSnap or Quantize.Grid) + half
	end
	local ok, reason = validateTransform(newPosition, newSize, newRotation)
	if not ok then return false, reason end
	if not withinCurrentVolume(component,newSize) then
		return false,"Material volume limit: "..MaterialVolume.display(Quantize.MaxComponentVolume)
	end
	if newPosition ~= node.position or newSize ~= node.size or newRotation ~= node.rotation then
		node.position, node.size, node.rotation = newPosition, newSize, newRotation
		component.revision += 1
	end
	return true, nil
end

-- Fabrication locations are snapped offsets from minimum material edges, so
-- resizing from the opposite face does not unexpectedly move previous cuts.
function Document:addOperation(component, kind: string, data)
	local node = component.nodes[1]
	if node.kind ~= "Block" and node.kind ~= "Cylinder"
		and node.kind ~= "RoundedL" and node.kind ~= "SketchBody" then
		return false, "This workpiece does not support fabrication"
	end
	local operation
	if kind == "Drill" then
		-- Drill dimensions use 1 mm resolution independently of the
		-- 0.05-stud construction POSITION snap (14 mm).
		local millimeter = 1 / 280
		if typeof(data.diameter) ~= "number" or not Quantize.isFinite(data.diameter) then
			return false, "Enter a finite drill diameter"
		end
		local diameter = Quantize.snap(data.diameter, millimeter)
		local depth = data.depth or node.size.Y
		if typeof(depth) ~= "number" or not Quantize.isFinite(depth) then
			return false, "Enter a finite drilling depth"
		end
		depth = Quantize.snap(depth, millimeter)
		if diameter < 5 / 280 or diameter > math.min(2 * math.max(node.size.X, node.size.Z), 128) then
			return false, "Diameter must be at least 5 mm and fit the workpiece"
		end
		if depth < 5 / 280 or depth > Quantize.MaxSize then
			return false, "Drill depth must be between 5 mm and 128 studs"
		end
		local snap=if typeof(data.snap)=="number" and Quantize.isFinite(data.snap)
   and data.snap>=0.01 and data.snap<=2 then data.snap else Quantize.Grid
  local x=Quantize.snap(data.x+node.size.X*0.5,snap)
  local z=Quantize.snap(data.z+node.size.Z*0.5,snap)
		if x < 0 or x > node.size.X or z < 0 or z > node.size.Z then
			return false, "Drill center must be on the workpiece"
		end
		operation = {
			kind = "Drill", diameter = diameter, depth = depth,
			through = data.through ~= false,
			x = x, z = z,
		}
	elseif kind == "DrillFace" then
		local origin,normal=data.origin,data.normal
		local diameter,depth=data.diameter,data.depth
		if typeof(origin)~="Vector3" or typeof(normal)~="Vector3"
			or typeof(diameter)~="number" or typeof(depth)~="number"
			or normal.Magnitude<0.9 or not Quantize.isFinite(diameter)
			or not Quantize.isFinite(depth) then
			return false,"Invalid drill face selection"
		end
		diameter=Quantize.snap(diameter,1/280)
		depth=Quantize.snap(depth,1/280)
		if diameter<5/280 or diameter>Quantize.MaxSize
			or depth<5/280 or depth>Quantize.MaxSize then
			return false,"Drill dimensions out of bounds"
		end
		operation={kind="DrillFace",origin=origin,normal=normal.Unit,
			diameter=diameter,depth=depth,through=data.through~=false}
	elseif kind == "GrooveFace" then
		local a,b,n=data.a,data.b,data.normal
		local width,depth=data.width,data.depth
		if typeof(a)~="Vector3" or typeof(b)~="Vector3"
			or typeof(n)~="Vector3" or n.Magnitude<0.9
			or typeof(width)~="number" or typeof(depth)~="number"
			or not Quantize.isFinite(width) or not Quantize.isFinite(depth) then
			return false,"Invalid selected groove plane"
		end
		width,depth=Quantize.snap(width,1/280),Quantize.snap(depth,1/280)
		if width<5/280 or depth<5/280 or depth>Quantize.MaxSize
			or width>Quantize.MaxSize or (a-b).Magnitude<Quantize.MinSize then
			return false,"Groove path or dimensions are invalid"
		end
		if math.abs((b-a):Dot(n.Unit))>0.008 then
			return false,"Groove points must lie on the same planar face"
		end
		operation={kind="GrooveFace",a=a,b=b,normal=n.Unit,
			width=width,depth=depth,through=data.through==true}
	elseif kind == "Saw" or kind == "Groove" then
		local kerf = Quantize.snap(data.kerf, 1 / 280)
		-- Cursor picks already use the configured snap; the source history
  -- retains them at 1 mm precision instead of re-quantizing at .05 stud.
  local x1,z1=Quantize.snap(data.x1+node.size.X*.5,Quantize.Size),
   Quantize.snap(data.z1+node.size.Z*.5,Quantize.Size)
  local x2,z2=Quantize.snap(data.x2+node.size.X*.5,Quantize.Size),
   Quantize.snap(data.z2+node.size.Z*.5,Quantize.Size)
		if not Quantize.isFinite(kerf) or kerf < 5 / 280
			or kerf > Quantize.MaxSize then return false, "Cut width must be at least 5 mm" end
		local depth = data.depth or node.size.Y
		if typeof(depth) ~= "number" or not Quantize.isFinite(depth) then return false, "Invalid cut depth" end
		depth = Quantize.snap(depth, 1 / 280)
		if depth < 5 / 280 or depth > Quantize.MaxSize then return false, "Invalid cut depth" end
		if (Vector2.new(x2 - x1, z2 - z1)).Magnitude < Quantize.MinSize - 0.00001 then
			return false, "Saw cut must extend at least 0.05 studs"
		end
		operation = {
			kind = kind, x1 = x1, z1 = z1, x2 = x2, z2 = z2,
			kerf = kerf, useMesh = kind == "Saw" and data.useMesh == true,
			through = kind == "Saw" or data.through == true, depth = depth,
		}
	elseif kind == "Inset" then
		if node.kind ~= "Block" then return false, "Inset requires rectangular stock" end
		local margin, depth = data.margin, data.depth
		if typeof(margin) ~= "number" or typeof(depth) ~= "number"
			or not Quantize.isFinite(margin) or not Quantize.isFinite(depth) then
			return false, "Enter finite inset dimensions"
		end
		margin, depth = Quantize.snap(margin, 1 / 280), Quantize.snap(depth, 1 / 280)
		if margin < 5 / 280 or margin * 2 >= math.min(node.size.X, node.size.Z) - 0.05 then
			return false, "Inset border is too large for the workpiece"
		end
		if depth < 5 / 280 or depth > node.size.Y then
			return false, "Inset depth must fit inside material"
		end
		operation = { kind = "Inset", margin = margin, depth = depth }
	elseif kind == "File" then
		if node.kind ~= "Block" then return false, "Edge filing requires rectangular stock" end
		local edge = data.edge
		if edge ~= "X+" and edge ~= "X-" and edge ~= "Z+" and edge ~= "Z-" then
			return false, "Select a supported top perimeter edge"
		end
		local width = data.width
		if typeof(width) ~= "number" or not Quantize.isFinite(width) then
			return false, "Enter a finite filing width"
		end
		width = Quantize.snap(width, 1 / 280)
		local maxWidth = math.min(node.size.Y, if string.sub(edge, 1, 1) == "X" then node.size.X else node.size.Z)
		if width < 5 / 280 or width >= maxWidth - 0.005 then
			return false, "File width must fit the top edge of the workpiece"
		end
		operation = { kind = "File", edge = edge, width = width }
	elseif kind == "FileMesh" then
		-- Interior filing is intentionally suspended; historical entries
		-- are retained for editing but excluded from compilation.
		if data.interior==true then
			return false,"Interior File is paused while corner geometry is rebuilt"
		end
		local a,b,n1,n2=data.a,data.b,data.normalA,data.normalB
		local width=data.width
		if typeof(a)~="Vector3" or typeof(b)~="Vector3"
			or typeof(n1)~="Vector3" or typeof(n2)~="Vector3"
			or typeof(width)~="number" or not Quantize.isFinite(width) then
			return false, "Invalid compiled edge selection"
		end
		width=Quantize.snap(width,1/280)
		if width < 5/280 or width > Quantize.MaxSize
			or (b-a).Magnitude < 0.01 or n1.Magnitude<0.9 or n2.Magnitude<0.9 then
			return false, "Invalid edge filing geometry"
		end
		if adjacentOperation(component,a,b,"SmoothInside") then
			return false,"Cannot File an edge touching a smoothed interior junction"
		end
		local segments=data.segments or 1
		if typeof(segments)~="number" or segments~=math.floor(segments)
			or segments<1 or segments>12 then
			return false,"File segmentation must be a whole number from 1 to 12"
		end
		operation={kind="FileMesh",a=a,b=b,normalA=n1.Unit,normalB=n2.Unit,
			width=width,interior=false,segments=segments,
			taperA=false,taperB=false}
	elseif kind == "SmoothInside" then
		local a,b,n1,n2=data.a,data.b,data.normalA,data.normalB
		local radius=data.radius
		local segments=data.segments or 8
		if typeof(a)~="Vector3" or typeof(b)~="Vector3"
			or typeof(n1)~="Vector3" or typeof(n2)~="Vector3"
			or typeof(radius)~="number" or not Quantize.isFinite(radius)
			or (b-a).Magnitude<0.05 or radius<5/280 or radius>Quantize.MaxSize
			or n1.Magnitude<0.9 or n2.Magnitude<0.9
			or math.abs(n1.Unit:Dot(n2.Unit))>0.12
			or typeof(segments)~="number" or segments~=math.floor(segments)
			or segments<2 or segments>12 then
			return false,"Smooth needs a straight interior 90-degree edge, 2-12 segments"
		end
		if adjacentOperation(component,a,b,"FileMesh")
			or adjacentOperation(component,a,b,"SmoothInside") then
			return false,"Interior smooth overlaps a File or another smooth junction"
		end
		operation={kind="SmoothInside",a=a,b=b,normalA=n1.Unit,
			normalB=n2.Unit,radius=Quantize.snap(radius,1/280),
			segments=segments}
	elseif kind == "InsetFace" then
		local points=data.points
		local normal=data.normal
		local margin,depth=data.margin,data.depth
		if typeof(points)~="table" or #points<3 or #points>64
			or typeof(normal)~="Vector3" or normal.Magnitude<0.9
			or typeof(margin)~="number" or typeof(depth)~="number"
			or not Quantize.isFinite(margin) or not Quantize.isFinite(depth) then
			return false,"Invalid compiled face selection"
		end
		local stored={}
		for _,p in ipairs(points) do
			if typeof(p)~="Vector3" then return false,"Inset face points must be Vector3" end
			table.insert(stored,p)
		end
		margin=Quantize.snap(margin,1/280)
		depth=Quantize.snap(depth,1/280)
		if margin<5/280 or depth<5/280 or depth>Quantize.MaxSize then
			return false,"Inset requires positive border and depth"
		end
		operation={kind="InsetFace",points=stored,normal=normal.Unit,margin=margin,depth=depth}
	elseif kind == "SketchExtrude" then
		local mode = data.mode
		if mode ~= "Add" and mode ~= "Remove" and mode ~= "Intersect" then
			return false, "Choose Add, Remove or Intersect"
		end
		local depth = Quantize.snap(data.depth, Quantize.Size)
		if not Quantize.isFinite(depth) or depth < Quantize.MinSize
			or depth > Quantize.MaxSize then
			return false, "Extrusion depth must be 0.05 to 128 studs"
		end
		-- SketchEditor and Extrusion both use component-CENTERED local
  -- coordinates. Store exactly that frame; no +halfSize recentering.
  -- Authoring snap is user configurable, geometric storage is 1 mm.
  local snappedPoints={}
  for _,point in ipairs(data.points or {}) do
   if typeof(point)~="Vector2" or not Quantize.isFinite(point.X)
    or not Quantize.isFinite(point.Y) then
    return false,"Sketch point must be finite Vector2"
   end
   table.insert(snappedPoints,Vector2.new(
    Quantize.snap(point.X,Quantize.Size),
    Quantize.snap(point.Y,Quantize.Size)))
  end
		local points, _, sketchError = SketchProfile.prepare(snappedPoints)
		if not points then return false, sketchError end
		-- No bounding-volume rejection here: the compiled result is
		-- checked against the scalar material budget after CSG.
		operation = {
			kind = "SketchExtrude", mode = mode,
			depth = depth, through = data.through == true,
			points = points,
		}
	else
		return false, "Unknown fabrication tool"
	end
	for _, value in pairs(operation) do
		if typeof(value) == "number" and (not Quantize.isFinite(value) or math.abs(value) > 512) then
			return false, "Fabrication coordinate outside allowed bounds"
		end
	end
	self.nextOperation += 1
	operation.id = self.nextOperation
	operation.enabled = true
	table.insert(component.operations, operation)
	component.revision += 1
	return true, nil
end

-- Individual feature controls: source remains intact when a feature is disabled.
function Document:setOperationEnabled(component, id: number, enabled: boolean)
	for _, operation in ipairs(component.operations) do
		if operation.id == id then
			-- Added/removed features are measured after manufacture,
			-- not by the stock's enclosing rectangular envelope.
			if (operation.enabled ~= false) ~= enabled then
				operation.enabled = enabled
				component.revision += 1
			end
			return true, nil
		end
	end
	return false, "Fabrication feature no longer exists"
end

function Document:removeOperation(component, id: number)
	for i, operation in ipairs(component.operations) do
		if operation.id == id then
			table.remove(component.operations, i)
			component.revision += 1
			return true, nil
		end
	end
	return false, "Fabrication feature no longer exists"
end

function Document:undoOperation(component)
	if #component.operations == 0 then return false, "No cuts to undo" end
	table.remove(component.operations)
	component.revision += 1
	return true, nil
end

function Document:removeComponent(id: number)
	if not self.components[id] then return end
	self.components[id] = nil
	for i, value in ipairs(self.order) do
		if value == id then table.remove(self.order, i) break end
	end
end

function Document:restoreSnapshot(component,snapshot)
	if not snapshot or snapshot.id~=component.id then return false end
	local copy=Document.snapshot(snapshot)
	component.name=copy.name
	component.nodes=copy.nodes
	component.operations=copy.operations
	component.notes=copy.notes
	component.materialVolume=copy.materialVolume
	component.volumeExact=copy.volumeExact
	component.workspaceOrigin=copy.workspaceOrigin
	component.workspaceSize=copy.workspaceSize
	component.worldOrigin=copy.worldOrigin
	component.revision+=1
	return true
end

function Document.snapshot(component)
	local nodes, operations = {}, {}
	for _, node in ipairs(component.nodes) do
		local clone=table.clone(node)
		if node.profilePoints then clone.profilePoints=table.clone(node.profilePoints) end
		table.insert(nodes,clone)
	end
	for _, operation in ipairs(component.operations) do
		local copy = table.clone(operation)
		if operation.points then copy.points = table.clone(operation.points) end
		table.insert(operations, copy)
	end
	return {
		id = component.id, name = component.name,
		revision = component.revision, nodes = nodes, operations = operations,
		notes = component.notes or "",
		materialVolume=component.materialVolume,
		volumeExact=component.volumeExact,
		workspaceOrigin=component.workspaceOrigin,
		workspaceSize=component.workspaceSize,
		worldOrigin=component.worldOrigin,
	}
end

-- Replace local document state from a FORGE-authoritative snapshot, but
-- preserve each component table identity for editor callbacks/preview jobs.
function Document:adoptSnapshot(snapshot:any)
 if typeof(snapshot)~="table" or typeof(snapshot.id)~="number"
  or typeof(snapshot.nodes)~="table"
  or typeof(snapshot.operations)~="table" then
  return nil,"Invalid authoritative component snapshot"
 end
 local copy=Document.snapshot(snapshot)
 local component=self.components[copy.id]
 if not component then
  component=copy
  self.components[copy.id]=component
  table.insert(self.order,copy.id)
 else
  table.clear(component)
  for key,value in pairs(copy) do component[key]=value end
 end
 self.nextComponent=math.max(self.nextComponent,copy.id)
 for _,node in ipairs(copy.nodes) do
  self.nextNode=math.max(self.nextNode,node.id or 0)
 end
 for _,operation in ipairs(copy.operations) do
  self.nextOperation=math.max(self.nextOperation,operation.id or 0)
 end
 return component,nil
end

function Document:setNotes(component,text:string)
 if typeof(text)~="string" or #text>4096 then
  return false,"Component notes must be at most 4,096 characters"
 end
 if component.notes~=text then
  component.notes=text
  component.revision+=1
 end
 return true,nil
end

-- Geometry-independent, stable feature IDs for future assembly mating.
-- These are only candidates until the compiled final surface is verified.
function Document:listFeatures(component)
 return Features.list(component)
end
function Document:getFeature(component,id:string)
 return Features.get(component,id)
end

return Document
