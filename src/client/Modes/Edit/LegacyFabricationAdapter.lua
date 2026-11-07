--!strict
-- Q1 legacy fabrication adapter. Ownership: FORGE OpenWorksRuntime -> Edit Mode.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Client=script.Parent.Parent.Parent
local FORM = ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM")
local Document = require(FORM.Document)
local Compiler = require(FORM.Compiler)
local Fabricator = require(FORM.Fabricator)
local GeometryCutter = require(FORM.GeometryCutter)
local Quantize = require(FORM.Quantize)
local MaterialVolume = require(FORM.MaterialVolume)
local Preview = require(Client.Systems.Components.Preview)
local BlenderCamera = require(Client.Experience.Cameras.BlenderCamera)
local GridOverlay = require(Client.Experience.Visuals.GridOverlay)
local CharacterMode = require(Client.Modes.Free.CharacterMode)
local EditWorkspace = require(Client.Modes.EditWorkspace)
local WorldProjection = require(Client.Modes.WorldProjection)
local AssemblyEnvironment = require(Client.Modes.AssemblyEnvironment)
local SurfaceSnap = require(Client.Tools.Snapping.SurfaceSnap)
local ViewGizmo = require(Client.Experience.Cameras.ViewGizmo)
local TransformGizmo = require(Client.Tools.Transform.TransformGizmo)
local SketchEditor = require(Client.Tools.Sketch.SketchEditor)
local ToolVisualizer = require(Client.Tools.Visuals.ToolVisualizer)
local SurfacePicker = require(Client.Systems.Selection.SurfacePicker)
local ComponentPlacement = require(Client.Experience.Placement.ComponentPlacement)
local MeasurementTool = require(Client.Tools.Inspection.MeasurementTool)
local EdgeAvailability = require(Client.Systems.Selection.EdgeAvailability)
local FaceTools = require(FORM.FaceTools)

local Debug = {}

local function make(className: string, properties, parent: Instance)
	local obj = Instance.new(className)
	for key, value in pairs(properties) do
		obj[key] = value
	end
	obj.Parent = parent
	return obj
end

function Debug.start(options:any?)
	options=options or {}
	local externalConnections={}
	local function connectExternal(signal:any,callback:any)
		local connection=signal:Connect(callback)
		table.insert(externalConnections,connection)
		return connection
	end
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local document = Document.new()
	local characterMode=CharacterMode.new(player)
	local editorActive=false
 local previewOnly=false
 local showTopologyOutlines=false
 local gizmoWasHidden=false
 local setPreviewEnabled:any=nil
 local togglePreview:any=nil
	local pendingSketch:any=nil
	local currentWorkspace:any=nil
	local worldProjection=WorldProjection.new()
	local assemblyEnvironment=AssemblyEnvironment.new()
	local leaveEditor:any=nil
	local selectedId: number? = nil
	local nodeIndex = 1
	local cameraController: any = nil
	local activeTool: string? = nil
	local historyInfo: any = nil
	local volumeInfo:any=nil
	local historyRows = {}
	local sketchEditor: any = nil
	local toolVisualizer = ToolVisualizer.new(playerGui)
	local placementFlow:any=nil
	local measurementTool:any=nil
	local notesBox:TextBox?=nil
	local surfacePicker: any = nil
	local drillThrough = true

	local grid = GridOverlay.new(playerGui)
	local gridUserVisible=false

	local gui = make("ScreenGui", {
		Name = "FORM_DebugUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	gui.Enabled=false -- Roblox character play is the default mode
 local previewButton=make("TextButton",{
  Name="ModelPreviewToggle",
  AnchorPoint=Vector2.new(1,0),
  Position=UDim2.new(1,-16,0,64),
  Size=UDim2.fromOffset(150,34),
  Text="PREVIEW  [P]",
  Font=Enum.Font.GothamMedium,TextSize=12,
  TextColor3=Color3.fromRGB(231,245,252),
  BackgroundColor3=Color3.fromRGB(33,65,81),
  BorderSizePixel=0,AutoButtonColor=true,
 },gui)
 make("UICorner",{CornerRadius=UDim.new(0,6)},previewButton)
 previewButton.Activated:Connect(function()
  if togglePreview then togglePreview() end
 end)
	local panel = make("Frame", {
		Name = "Controls",
		BackgroundColor3 = Color3.fromRGB(25, 29, 33),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.fromOffset(314, 595),
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 5) }, panel)

	panel.Visible=false -- Enter the editor only after a component is placed
	local title = make("TextLabel", {
		BackgroundTransparency = 1,
		Text = "FORM // DEBUG 01",
		TextColor3 = Color3.fromRGB(231, 236, 239),
		Font = Enum.Font.Code,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 28),
	}, panel)
	local status = make("TextLabel", {
		Name = "Status",
		BackgroundTransparency = 1,
		Text = "Local prototype. No server shipping or saving.",
		TextColor3 = Color3.fromRGB(159, 198, 204),
		Font = Enum.Font.Code,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Position = UDim2.fromOffset(12, 544),
		Size = UDim2.new(1, -24, 0, 47),
	}, panel)
	local scroll = make("ScrollingFrame", {
		Name = "Editor",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		Position = UDim2.fromOffset(10, 38),
		Size = UDim2.new(1, -20, 0, 505),
	}, panel)
	make("UIListLayout", {
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, scroll)

	local layoutOrder = 0
	local function row(height: number)
		layoutOrder += 1
		return make("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = layoutOrder,
			Size = UDim2.new(1, -8, 0, height),
		}, scroll)
	end
	local function line(text: string, height: number?)
		local container = row(height or 20)
		return make("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Code,
			Text = text,
			TextColor3 = Color3.fromRGB(184, 195, 200),
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.fromScale(1, 1),
		}, container)
	end
	local function button(parent: Instance, text: string, x: number, width: number, callback)
		local control = make("TextButton", {
			AutoButtonColor = true,
			BackgroundColor3 = Color3.fromRGB(56, 63, 70),
			BorderSizePixel = 0,
			Font = Enum.Font.Code,
			Text = text,
			TextColor3 = Color3.fromRGB(235, 238, 240),
			TextSize = 13,
			Position = UDim2.new(x, 0, 0, 0),
			Size = UDim2.new(width, -4, 1, 0),
		}, parent)
		make("UICorner", { CornerRadius = UDim.new(0, 3) }, control)
		control.MouseButton1Click:Connect(callback)
		return control
	end
	local function pair(left: string, leftFn, right: string, rightFn)
		local container = row(29)
		button(container, left, 0, 0.5, leftFn)
		button(container, right, 0.5, 0.5, rightFn)
	end
	local function message(value: string)
		status.Text = value
		print("[FORM] " .. value)
	end

	local info = line("Selection: none")
	local nodeInfo = line("Node: none")

	-- Manufactured-edge wireframe follows the authored CSG history.
	-- Unlike SelectionBox, it does not outline the bounding volume.
	local outlineOrigin=make("Part",{
		Name="FORM_SelectionOutlineOrigin",Anchored=true,
		CanQuery=false,CanTouch=false,CanCollide=false,
		CastShadow=false,Transparency=1,Size=Vector3.one*0.05,
		CFrame=CFrame.identity,
	},workspace)
	local selectionBorder=make("WireframeHandleAdornment",{
		Name="FORM_ManufacturedSelectionOutline",
		Adornee=outlineOrigin,Color3=Color3.fromRGB(100,234,246),
		Transparency=0.12,Thickness=0.85,AlwaysOnTop=false,
		Visible=false,
	},workspace)

	local preview
	local transformGizmo: any = nil
	local textFields = {}
	local function selectedComponent()
		return if selectedId then document.components[selectedId] else nil
	end
	local function selectedNode()
		local component = selectedComponent()
		return if component then component.nodes[nodeIndex] else nil
	end
	local function displayNumber(value: number): string
		return string.format("%.2f", value)
	end
	local function refresh()
		local component = selectedComponent()
		local node = selectedNode()
		info.Text = if component then ("Selection: " .. component.name) else "Selection: none"
		nodeInfo.Text = if node then ("Material: " ..
			(if node.kind=="SketchBody" then "Sketched Solid" else node.kind)) else "Material: none"
		if volumeInfo then
			local used=if component then component.materialVolume else nil
			if node and not Fabricator.requiresCompile(component) then
				used=MaterialVolume.primitive(node.kind,node.size)
			end
			local state=if component then preview and preview.states[component.id] else nil
			local pending=component and Fabricator.requiresCompile(component)
				and (not state or state.key~=Fabricator.geometryKey(component))
			volumeInfo.Text=if not component then "Material volume: —"
				elseif pending then "Material: calculating CSG…"
				elseif used then "Material: "..(if component.volumeExact==false then "≈" else "")..
					MaterialVolume.display(used)..
					" / "..MaterialVolume.display(Quantize.MaxComponentVolume)
				else "Material: calculating CSG…"
		end
		if notesBox and not notesBox:IsFocused() then
			notesBox.Text=if component then component.notes or "" else ""
		end
		if historyInfo then
			local active = 0
			if component then
				for _, feature in ipairs(component.operations) do
					if feature.enabled ~= false then active += 1 end
				end
			end
			historyInfo.Text = if component
				then string.format("Fabrication: %d features (%d active)", #component.operations, active)
				else "Fabrication: no material selected"
		end
		for slot, entry in ipairs(historyRows) do
			local operation = if component
				then component.operations[#component.operations - slot + 1] else nil
			entry.container.Visible = operation ~= nil
			if operation then
				local description
				if operation.kind == "SketchExtrude" then
					description = "SKETCH " .. string.upper(operation.mode) .. " (" .. #operation.points .. "p)"
				elseif operation.kind == "Drill" or operation.kind == "DrillFace" then
					description = string.format("DRILL Ø%.0f%s", operation.diameter * 280,
						if operation.through == false then " BLIND" else "")
				elseif operation.kind == "Inset" then
					description = string.format("INSET %.0fmm", operation.margin * 280)
				elseif operation.kind == "File" then
					description = string.format("FILE %s %.0fmm", operation.edge, operation.width * 280)
				elseif operation.kind == "SmoothInside" then
					description=string.format("SMOOTH INNER %.0fmm",operation.radius*280)
				elseif operation.kind == "FileMesh" then
					description = string.format("%s %.0fmm · %d seg",
						if operation.interior then "FILE INNER (PAUSED)" else "FILE EDGE",
						operation.width*280,operation.segments or 1)
				elseif operation.kind == "InsetFace" then
					description = string.format("INSET FACE %.0fmm",operation.margin*280)
				elseif operation.kind == "Groove" then
					description = string.format("GROOVE %.0fmm", operation.kerf * 280)
				elseif operation.kind == "GrooveFace" then
					description = string.format("%s %.0fmm",
						if operation.through then "KERF" else "GROOVE",operation.width*280)
				else
					description = string.format("KERF %.0fmm", operation.kerf * 280)
				end
				entry.label.Text = string.format("%02d %s", operation.id, description)
				entry.label.TextColor3 = if operation.enabled == false
					then Color3.fromRGB(120, 135, 143)
					else Color3.fromRGB(216, 231, 236)
				entry.toggle.Text = if operation.enabled == false then "OFF" else "ON"
				entry.toggle.BackgroundColor3 = if operation.enabled == false
					then Color3.fromRGB(57, 66, 76)
					else Color3.fromRGB(46, 97, 86)
			end
		end
		for _, binding in ipairs(textFields) do
			local box = binding.box
			local value = nil
			if node then
				local property = if binding.field == "position" then Document.minCorner(node) else node[binding.field]
				if binding.axis ~= " " then
					value = property[binding.axis]
				end
			end
			if not box:IsFocused() then
				box.Text = if value ~= nil then displayNumber(value) else "-"
			end
		end
		local model = if component then preview:getModel(component.id) else nil
		selectionBorder:Clear()
		selectionBorder.Visible=false
		local solidState=if component then preview.states[component.id] else nil
		local ready=component and solidState
			and solidState.key==Fabricator.geometryKey(component)
			and (not Fabricator.requiresCompile(component) or solidState.boolean)
		if showTopologyOutlines and ready and editorActive and not previewOnly and not pendingSketch and not activeTool
			and not (sketchEditor and sketchEditor.active)
			and model and surfacePicker then
			local topology=surfacePicker:get(component.id,model,component)
			if topology then
				-- Topology is manufactured-history aware: retired sharp
				-- edges are absent, and new fillets supply their own edges.
				-- Paths are world-space because origin is CFrame.identity.
				for _,edge in ipairs(topology.edges) do
					if node and node.kind=="RoundedL" and edge.curved then
						local onCap=false
						for _,fid in ipairs(edge.faces) do
							local face=topology.faces[fid]
							if face and (face.tag=="rounded_l_front" or
								face.tag=="rounded_l_back") then
								onCap=true
							end
						end
						if not onCap then continue end
					end
					local a=topology.part.CFrame:PointToWorldSpace(edge.a)
					local b=topology.part.CFrame:PointToWorldSpace(edge.b)
					if (a-b).Magnitude>0.001 then
						-- Keep even segmented curved trim edges: the
						-- selection follows new smooth/file surfaces.
						selectionBorder:AddPath({a,b},false)
					end
				end
				selectionBorder.Visible=true
			end
		end
		if transformGizmo then
			if ready and editorActive and not previewOnly and not pendingSketch and component and node then
				transformGizmo:show(component, nodeIndex)
			else
				transformGizmo:hide()
			end
		end
	end

	surfacePicker = SurfacePicker.new(function(result)
		message(result)
		-- Async history topology becomes available after the preview
		-- renders; refresh the manufactured outline at that point.
		refresh()
	end)
	preview = Preview.new(message, function(id,model)
		surfacePicker:request(id,model,document.components[id])
		-- A background CSG compilation can complete after leaving Edit.
		-- Refresh only the visible projection for Free or Assembly.
		if not editorActive and currentWorkspace then
			local stageCorner=if assemblyEnvironment.root
				then AssemblyEnvironment.Center-
					Vector3.new(currentWorkspace.size.X*0.5,0,currentWorkspace.size.Z*0.5)
				else nil
			worldProjection:show(preview,document,currentWorkspace,stageCorner)
		end
		if id == selectedId then
			-- Once the first manufactured solid exists, don't leave a
			-- wireframe grid obscuring it. Its real placement remains
			-- available through the construction-grid toggle.
			local material=preview.states[id]
			if material and material.boolean and gridUserVisible then
				gridUserVisible=false
				grid:clear()
			end
			refresh()
		end
	end,function(id,accepted,reason)
		local component=document.components[id]
		if not component then return end
		if document:restoreSnapshot(component,accepted) then
			preview:render(component)
			refresh()
		end
		message(reason.." · reverted to last valid material")
	end)

	local function selectComponent(id: number?)
		if id~=selectedId then toolVisualizer:stopAnimation() end
		selectedId = id
		if editorActive then preview:showOnly(id or -1) end
		local component = selectedComponent()
		nodeIndex = if component then #component.nodes else 1
		if placementFlow then
			panel.Visible=(component~=nil)
			placementFlow:setLaunchVisible(component==nil)
		end
		refresh()
	end
 -- Dragging a Free Mode component selects that manufactured object for
 -- the next Edit entry. Free Mode never exposes the CAD gizmo.
 worldProjection.onSelect=function(id:number)
  local component=document.components[id]
  if not component then return end
  selectComponent(id)
  currentWorkspace=EditWorkspace.new(component.worldOrigin
   or component.workspaceOrigin or Vector3.zero,
   component.workspaceSize or component.nodes[1].size,component.name)
  if placementFlow then placementFlow:setLaunchVisible(true) end
 end

	local function changed(component)
		toolVisualizer:stopAnimation()
		preview:render(component)
		refresh()
	end

	transformGizmo = TransformGizmo.new(playerGui, document, function(phase: string, component, index: number, dirty: boolean?)
		if phase == "begin" then
			preview:beginLive(component, index)
		elseif phase == "update" then
			-- Update the existing solid immediately; no duplicate ghost.
			preview:updateLive(component, index)
			refresh()
		elseif phase == "finish" then
			if dirty then
				preview:finishLive(component)
			else
				preview:cancelLive(component.id)
			end
			refresh()
		end
	end)

	line("COMPONENT WORKSPACE")
	button(row(29),"Toggle Edge Outlines",0,1,function()
  showTopologyOutlines=not showTopologyOutlines
  selectionBorder:Clear()
  selectionBorder.Visible=false
  refresh()
 end)
	button(row(29),"Toggle Construction Grid",0,1,function()
		local component=selectedComponent()
		if component then
			local corner=component.workspaceOrigin or Document.minCorner(component.nodes[1])
			local size=component.workspaceSize or component.nodes[1].size
			grid:update(corner,size)
		end
		gridUserVisible=not gridUserVisible
		grid:setVisible(gridUserVisible)
	end)
	button(row(29),"Exit Workspace → Character",0,1,function()
		if options.onFreeRequested then options.onFreeRequested()
		elseif leaveEditor then leaveEditor() end
	end)
	button(row(29), "+ Create Component", 0, 1, function()
		if sketchEditor and sketchEditor.active then sketchEditor:stop() end
		activeTool=nil
		if options.onToolChanged then options.onToolChanged(nil) end
		toolVisualizer:stopAnimation()
		selectionBorder:Clear()
		selectionBorder.Visible=false
		if measurementTool then measurementTool:setActive(false) end
		transformGizmo:setHidden(true)
		if options.onFreeRequested then options.onFreeRequested() end
		if placementFlow then placementFlow:open() end
	end)
	local notesButton=button(row(29),"Notepad (component notes)",0,1,function() end)
	local notesContainer=row(116)
	notesContainer.Visible=false
	notesBox=make("TextBox",{
		Name="ComponentNotepad",
		Text="",MultiLine=true,TextWrapped=true,
		TextXAlignment=Enum.TextXAlignment.Left,
		TextYAlignment=Enum.TextYAlignment.Top,
		Font=Enum.Font.Code,TextSize=13,
		TextColor3=Color3.fromRGB(242,247,249),
		BackgroundColor3=Color3.fromRGB(40,49,55),
		BorderSizePixel=0,ClearTextOnFocus=false,
		Size=UDim2.fromScale(1,1),
	},notesContainer)
	make("UICorner",{CornerRadius=UDim.new(0,4)},notesBox)
	notesButton.MouseButton1Click:Connect(function()
		notesContainer.Visible=not notesContainer.Visible
	end)
	notesBox:GetPropertyChangedSignal("Text"):Connect(function()
		local selected=selectedComponent()
		if selected and notesBox:IsFocused() then
			selected.notes=notesBox.Text
		end
	end)
	volumeInfo=line("Material volume: —",30)
	volumeInfo.TextSize=11
	volumeInfo.TextWrapped=true
	line("Material budget: "..MaterialVolume.display(Quantize.MaxComponentVolume),24)
	line("Scale: 1 mm · hollow shapes use less material",22)
	line("FABRICATION TOOLS // MANUFACTURED SURFACES")
	local toolStatus = line("Tool: none")
	historyInfo = line("Fabrication: 0 cuts")
	local function setTool(kind: string?)
		toolVisualizer:stopAnimation()
		if sketchEditor and sketchEditor.active then sketchEditor:stop() end
		activeTool = kind
		if options.onToolChanged then options.onToolChanged(kind) end
		if measurementTool then measurementTool:setActive(kind=="Measure") end
		toolVisualizer:hide()
		selectionBorder:Clear()
		selectionBorder.Visible=false
		if kind then
			transformGizmo:setHidden(true)
			toolStatus.Text = "Tool: " .. string.upper(kind)
			local guidance = {
				Drill = "Drill: hover a face, wheel to change diameter, click to bore",
				Inset = "Inset: hover a planar manufactured face; wheel sets border width; click",
				File = "File: select one exposed edge segment; width via wheel",
				Smooth = "Smooth: select a concave interior edge; connected File edges are locked",
				Measure = "Measure: click a first point, then a second point; distance is in mm",
			}
			message(guidance[kind] or "Choose a fabrication operation")
		else
			transformGizmo:setMode("Move")
			toolStatus.Text = "Tool: none"
			message("Fabrication tool cleared")
			refresh()
		end
	end
	pair("Drill", function() setTool("Drill") end, "Saw (Profile)", function()
		local component = selectedComponent()
		if not component then message("Select a workpiece before using Saw") return end
		if not sketchEditor then message("Sketch workspace unavailable") return end
		activeTool = nil
		if options.onToolChanged then options.onToolChanged("Saw") end
		toolVisualizer:stopAnimation()
		selectionBorder:Clear()
		selectionBorder.Visible=false
		toolStatus.Text = "Tool: SAW"
		sketchEditor:start(component, "Saw")
		transformGizmo:setHidden(true)
	end)
	pair("Inset / Pocket", function() setTool("Inset") end,
		"File Edge", function() setTool("File") end)
	button(row(29), "Smooth Inside Edge", 0, 1, function() setTool("Smooth") end)
	button(row(29), "Measure Two Points", 0, 1, function() setTool("Measure") end)
	pair("Sketch / Extrude", function()
		local component = selectedComponent()
		if not component then message("Create or select a workpiece first") return end
		if not sketchEditor then message("Sketch workspace is not initialized") return end
		activeTool = nil
		toolVisualizer:stopAnimation()
		selectionBorder:Clear()
		selectionBorder.Visible=false
		transformGizmo:setHidden(true)
		toolStatus.Text = "Tool: SKETCH"
		if options.onToolChanged then options.onToolChanged("Sketch") end
		sketchEditor:start(component)
		transformGizmo:setHidden(true)
	end, "New Component", function()
		if options.onFreeRequested then options.onFreeRequested() end
		if placementFlow then placementFlow:open() end
	end)
	pair("Exit Tool", function() setTool(nil) end, "Undo Last Cut", function()
		local component = selectedComponent()
		if not component then message("Select a material first") return end
		local ok, reason = document:undoOperation(component)
		if ok then changed(component) message("Last fabrication cut removed")
		else message(reason) end
	end)
	local function toolNumberRow(caption: string, initial: string)
		local container = row(30)
		make("TextLabel", {
			BackgroundTransparency = 1, Font = Enum.Font.Code,
			Text = caption, TextSize = 12, TextColor3 = Color3.fromRGB(184, 195, 200),
			TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0.65, 0, 1, 0),
		}, container)
		local input = make("TextBox", {
			BackgroundColor3 = Color3.fromRGB(45, 51, 56),
			BorderSizePixel = 0, ClearTextOnFocus = false,
			Font = Enum.Font.Code, TextSize = 13, Text = initial,
			TextColor3 = Color3.fromRGB(235, 238, 240),
			Position = UDim2.new(0.65, 0, 0, 1), Size = UDim2.new(0.35, -4, 1, -2),
		}, container)
		make("UICorner", { CornerRadius = UDim.new(0, 3) }, input)
		return input
	end
	line("DRILL  /  PRECISION CONTROLS")
	local diameterInput = toolNumberRow("Diameter (mm)  [wheel]", "56")
	local drillDepthInput = toolNumberRow("Blind depth (mm)", "28")
	local throughRow = row(29)
	local throughButton: TextButton? = nil
	throughButton = button(throughRow, "Drill: THROUGH (click to toggle)", 0, 1, function()
		drillThrough = not drillThrough
		if throughButton then
			throughButton.Text = if drillThrough then "Drill: THROUGH (click to toggle)"
				else "Drill: BLIND (click to toggle)"
		end
	end)
	line("Position snap: 14 mm · Dimensions: 1 mm",24)
	line("Wheel: Drill 2 | File 1 | Inset 2 mm", 20)
	line("Shift+Wheel: coarse · Alt+Wheel: File segments", 20)
	line("POCKET  /  FILE EDGE")
	local insetMarginInput = toolNumberRow("Inset border (mm)  [wheel]", "28")
	local insetDepthInput = toolNumberRow("Inset depth (mm)", "28")
	local fileWidthInput = toolNumberRow("File chamfer (mm)  [wheel]", "14")
	local fileSegmentsInput = toolNumberRow("File segments (1–12)", "1")
	local smoothRadiusInput = toolNumberRow("Inside smooth radius (mm)", "14")

	line("File: convex only. Smooth: concave only; touching File locked.", 24)

	line("3D TRANSFORM HANDLES")
	local transformStatus = line("Mode: MOVE (G)")
	local function setTransformMode(mode: string)
		if sketchEditor and sketchEditor.active then sketchEditor:stop() end
		toolVisualizer:stopAnimation()
		selectionBorder:Clear()
		selectionBorder.Visible=false
		activeTool = nil
		toolStatus.Text = "Tool: none"
		if measurementTool then measurementTool:setActive(false) end
		transformGizmo:setMode(mode)
		if options.onToolChanged then options.onToolChanged(mode) end
		transformStatus.Text = "Mode: " .. string.upper(mode)
		refresh()
	end
	pair("Move [G]", function() setTransformMode("Move") end,
		"Scale [S]", function() setTransformMode("Scale") end)
	pair("Rotate [R]", function() setTransformMode("Rotate") end,
		"Hide Handles", function()
		transformGizmo:setHidden(true)
		transformStatus.Text = "Mode: HIDDEN (G/S/R)"
	end)

	connectExternal(UserInputService.InputBegan,function(input, processed)
		if not editorActive or previewOnly then return end
		if toolVisualizer:isAnimating() then return end
		if sketchEditor and sketchEditor.active then return end
		if processed or UserInputService:GetFocusedTextBox() then return end
		if placementFlow and (placementFlow.placing or placementFlow.form.Visible) then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if input.KeyCode == Enum.KeyCode.G then
			setTransformMode("Move")
		elseif input.KeyCode == Enum.KeyCode.S then
			setTransformMode("Scale")
		elseif input.KeyCode == Enum.KeyCode.R then
			setTransformMode("Rotate")
		end
	end)

	line("COMPONENT TRANSFORM")
	line("Move snap 0.05 / Scale 1 mm / rotation 15°")
	local function editRow(label: string, field: string, axes)
		local container = row(32)
		make("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Code,
			Text = label,
			TextColor3 = Color3.fromRGB(184, 195, 200),
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(0, 45, 1, 0),
		}, container)
		for index, axis in ipairs(axes) do
			local slot = make("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 45 + (index - 1) * 80, 0, 0),
				Size = UDim2.fromOffset(77, 32),
			}, container)
			make("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.Code,
				Text = axis or " ",
				TextColor3 = Color3.fromRGB(137, 149, 158),
				TextSize = 12,
				Size = UDim2.fromOffset(15, 32),
			}, slot)
			local box = make("TextBox", {
				BackgroundColor3 = Color3.fromRGB(45, 51, 56),
				BorderSizePixel = 0,
				ClearTextOnFocus = false,
				Font = Enum.Font.Code,
				Text = "-",
				TextColor3 = Color3.fromRGB(235, 238, 240),
				TextSize = 13,
				Position = UDim2.fromOffset(17, 2),
				Size = UDim2.fromOffset(59, 27),
			}, slot)
			make("UICorner", { CornerRadius = UDim.new(0, 3) }, box)
			table.insert(textFields, { box = box, field = field, axis = axis })
			box.FocusLost:Connect(function()
				local component = selectedComponent()
				if not component then refresh() return end
				local value = tonumber(box.Text)
				local axisArgument = if axis == " " then nil else axis
				local ok, reason = document:editNode(component, nodeIndex, field, axisArgument, value :: any)
				if not ok then message(reason) else changed(component) end
				refresh()
			end)
		end
	end
	editRow("MIN", "position", { "X", "Y", "Z" })
	editRow("SIZE", "size", { "X", "Y", "Z" })
	editRow("ROT", "rotation", { "X", "Y", "Z" })

	line("FEATURE HISTORY  /  LAST 6")
	for slot = 1, 6 do
		local entry = row(27)
		local label = make("TextLabel", {
			BackgroundTransparency = 1, Text = "",
			Font = Enum.Font.Code, TextSize = 11,
			TextColor3 = Color3.fromRGB(215, 228, 234),
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(0.64, 0, 1, 0),
		}, entry)
		local toggle = button(entry, "ON", 0.65, 0.18, function()
			local component = selectedComponent()
			local operation = component and component.operations[#component.operations - slot + 1]
			if not operation then return end
			local ok, reason = document:setOperationEnabled(component, operation.id, operation.enabled == false)
			if ok then changed(component) else message(reason) end
		end)
		button(entry, "X", 0.84, 0.16, function()
			local component = selectedComponent()
			local operation = component and component.operations[#component.operations - slot + 1]
			if not operation then return end
			local ok, reason = document:removeOperation(component, operation.id)
			if ok then changed(component) else message(reason) end
		end)
		table.insert(historyRows, { container = entry, label = label, toggle = toggle })
		entry.Visible = false
	end

	local deleteRow = row(29)
	button(deleteRow, "Delete Component", 0, 1, function()
		if sketchEditor and sketchEditor.active then sketchEditor:stop() end
		local component = selectedComponent()
		if not component then message("No selection") return end
		preview:remove(component.id)
		surfacePicker:remove(component.id)
		document:removeComponent(component.id)
		selectComponent(document.order[#document.order])
		message("Component removed")
	end)


	-- Read the actual compiled solid when available; fall back to editable node dimensions.
	local function selectionBounds()
		local component = selectedComponent()
		if not component then return nil, nil end
		local model = preview:getModel(component.id)
		if model then return model:GetBoundingBox() end
		local node = component.nodes[1]
		return CFrame.new(node.position), node.size
	end

	local function sceneBounds()
		local minimum: Vector3? = nil
		local maximum: Vector3? = nil
		for _, id in ipairs(document.order) do
			local component = document.components[id]
			local model = preview:getModel(id)
			local frame: CFrame
			local size: Vector3
			if model then
				frame, size = model:GetBoundingBox()
			else
				local node = component.nodes[1]
				frame = CFrame.new(node.position)
				size = node.size
			end
			local half = size / 2
			for _, x in ipairs({ -1, 1 }) do
				for _, y in ipairs({ -1, 1 }) do
					for _, z in ipairs({ -1, 1 }) do
						local corner = frame:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
						if minimum then
							minimum = Vector3.new(math.min(minimum.X, corner.X), math.min(minimum.Y, corner.Y), math.min(minimum.Z, corner.Z))
							maximum = Vector3.new(math.max(maximum.X, corner.X), math.max(maximum.Y, corner.Y), math.max(maximum.Z, corner.Z))
						else
							minimum = corner
							maximum = corner
						end
					end
				end
			end
		end
		if not minimum or not maximum then return nil, nil end
		return CFrame.new((minimum + maximum) / 2), maximum - minimum
	end


	cameraController = BlenderCamera.new(selectionBounds, sceneBounds)
	-- The player is walking by default. Explicitly entering/exiting
	-- component workspace changes camera AND movement controls.
	leaveEditor=function()
  if previewOnly and setPreviewEnabled then setPreviewEnabled(false) end
		pendingSketch=nil
		editorActive=false
		-- Switching modes must cancel an unfinished ground placement,
		-- otherwise its RenderStep and click listener remain active.
		if placementFlow and (placementFlow.placing or placementFlow.form.Visible) then
			placementFlow:close()
		end
		if sketchEditor and sketchEditor.active then sketchEditor:stop() end
		activeTool=nil
		toolVisualizer:stopAnimation()
		selectionBorder:Clear()
		selectionBorder.Visible=false
		if measurementTool then measurementTool:setActive(false) end
		if transformGizmo then transformGizmo:setHidden(true) end
		gridUserVisible=false
		-- Preserve reusable grid adornments across mode switches. Creating
		-- and destroying every line caused frame spikes on editor exit.
		grid:setVisible(false)
		gui.Enabled=false
		panel.Visible=false
		if placementFlow then placementFlow:setLaunchVisible(true) end
		cameraController:setActive(false)
		characterMode:setEditing(false)
		if preview then preview.root.Parent=nil end
		message("Character mode · Create Component to enter a workspace")
	end
	pair("Zoom Selected (F)", function()
		if not cameraController:frameSelected() then message("Select a component first") end
	end, "Zoom All (Home)", function()
		if not cameraController:frameAll() then message("No components to frame") end
	end)
	line("RMB / MMB drag: orbit component workspace", 24)
	line("Ctrl+MMB / wheel: hybrid zoom", 24)
	line("Numpad 1/3/7 views | 5 ortho", 24)
	line("F / Home: frame current workspace", 24)
	line("Drag view gizmo; drag zoom control", 24)

	local viewGizmo = ViewGizmo.new(gui, cameraController)
	cameraController:setOnFrame(function(cameraFrame, label)
		viewGizmo:update(cameraFrame, label)
	end)
	sketchEditor = SketchEditor.new(playerGui, cameraController,
		function(component, data)
			if component then
				local ok, reason = document:addOperation(component, "SketchExtrude", data)
				if ok then
     -- Sketch booleans are replayed asynchronously. Never draw the old
     -- cutter's 3D extrusion wireframe after committing it; that stale
     -- animation looked like stretched/broken geometry during CSG.
     toolVisualizer:stopAnimation()
     toolVisualizer:discard()
     changed(component)
				end
				return ok, reason
			end
			-- The placed grid provides an empty construction plane.
			-- The *first sketch itself* becomes the manufactured solid.
			local pending=pendingSketch
			if not pending then return false,"Create and place a component grid first" end
			local body,reason=document:createSketchBody(
				pending.name,pending.corner,pending.size,data.points,data.depth)
			if not body then return false,reason end
			body.worldOrigin=pending.worldCorner or pending.corner
			pendingSketch=nil
			selectComponent(body.id)
			changed(body)
			panel.Visible=true
			grid:update(pending.corner,pending.size)
			grid:setVisible(true)
			-- No primitive stock and no hidden intersection box.
			message("First sketch created; manufacturing solid")
			return true,nil
		end,
		message,
		function()
			if pendingSketch then
				-- Canceling the required initial sketch returns to normal
				-- player mode; no empty component was ever created.
				pendingSketch=nil
				if options.onFreeRequested then options.onFreeRequested()
				elseif leaveEditor then leaveEditor() end
				return
			end
			-- Never resurrect CAD handles or topology paths when a sketch
   -- finishes. The player can explicitly re-enable transforms with G/S/R.
   activeTool=nil
   if options.onToolChanged then options.onToolChanged(nil) end
   toolVisualizer:stopAnimation()
   toolVisualizer:discard()
   selectionBorder:Clear()
   selectionBorder.Visible=false
   transformGizmo:setHidden(true)
			toolStatus.Text = "Tool: none"
			transformStatus.Text = "Mode: HIDDEN (G/S/R)"
			if editorActive then refresh() end
		end
	)


	-- Active fabrication tools use the scroll wheel for the dimension under
	-- the cursor, not camera zoom. The input field stays authoritative, so
	-- typed values and wheel edits share the exact same CSG history path.
	-- Ctrl+MMB remains available for camera zoom while using a tool.
	local dimensionTools={
		Drill={ box=diameterInput, step=2, coarse=10, default=56 },
		File={ box=fileWidthInput, step=1, coarse=5, default=14, minimum=6 },
		Inset={ box=insetMarginInput, step=2, coarse=10, default=28 },
	}
	cameraController:setWheelHandler(function(steps:number):boolean
		local entry=dimensionTools[activeTool]
		if not entry or UserInputService:GetFocusedTextBox() then return false end
		-- ALT + wheel changes geometric rounding segmentation. Plain
		-- wheel still changes File width, matching the Drill workflow.
		if activeTool=="File" and (
			UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)) then
			local current=tonumber(fileSegmentsInput.Text) or 1
			local count=math.clamp(math.floor(current+steps+0.5),1,12)
			fileSegmentsInput.Text=tostring(count)
			toolStatus.Text=string.format("FILE: %d %s",count,
				if count==1 then "flat segment" else "rounded segments")
			return true
		end
		local shift=UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		local increment=if shift then entry.coarse else entry.step
		local current=tonumber(entry.box.Text)
		if not current or current~=current then current=entry.default end
		local node=selectedNode()
		-- Bounds only protect the numeric UI from absurd dimensions.
		-- The actual face/edge geometry validator applies stricter limits
		-- before committing File or Inset.
		local limit=35840
		if node then
			local major=math.max(node.size.X,node.size.Y,node.size.Z)*280
			if activeTool=="Drill" then
				limit=math.max(5,math.min(major*2,35840))
			elseif activeTool=="File" then
				limit=math.max(5,math.min(major*0.5,35840))
			else
				limit=math.max(5,math.min(major*0.45,35840))
			end
		end
		local nextMM=math.clamp(math.round(current+steps*increment),entry.minimum or 5,limit)
		entry.box.Text=string.format("%.0f",nextMM)
		toolStatus.Text=string.format("Tool: %s · %d mm",
			string.upper(activeTool),nextMM)
		return true
	end)

	local function millimeters(box: TextBox, label: string): (number?, string?)
		local mm = tonumber(box.Text)
		if not mm or not Quantize.isFinite(mm) or mm < 5 or mm > 35840 then
			return nil, label .. " must be between 5 mm and 35840 mm"
		end
		-- All editable tool dimensions are whole-millimeter increments,
		-- regardless of whether typed or adjusted with the wheel.
		local snappedMM=math.floor(mm+0.5)
		if not box:IsFocused() and box.Text~=tostring(snappedMM) then
			box.Text=tostring(snappedMM)
		end
		return SurfaceSnap.mm(snappedMM/280),nil
	end


	-- Only ever raycast the actual manufactured geometry. Tool indicators
	-- are CanQuery=false so the ghost itself cannot steal the mouse.
	local function fabricationHit()
		if not activeTool or (sketchEditor and sketchEditor.active) then return nil end
		if UserInputService:GetFocusedTextBox() or cameraController.dragging then return nil end
		local mouse = UserInputService:GetMouseLocation()
		if mouse.X < 345 and mouse.Y < 615 then return nil end
		local camera = workspace.CurrentCamera
		if not camera then return nil end
		if mouse.X > camera.ViewportSize.X - 340 and mouse.Y > 225 and mouse.Y < 610 then return nil end
		if viewGizmo:containsPoint(mouse) or transformGizmo:capturesPoint(mouse) then return nil end
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { preview.root }
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
		if not hit then return nil end
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		local id = if model then model:GetAttribute("FORMComponentId") else nil
		local component = if typeof(id) == "number" then document.components[id] else nil
		if not component then return nil end
		local node = component.nodes[1]
		-- The rendered CSG may still be the previous revision while
		-- asynchronous remanufacturing is in progress. Never pick stale
		-- topology or commit a feature against a replaced mesh.
		local state = preview.states[id]
		if activeTool and (not state or state.key~=Fabricator.geometryKey(component)) then
			return nil
		end
		local pose = Compiler.pose(node)
		local normal = pose:VectorToObjectSpace(hit.Normal)
		
		local localPoint = pose:PointToObjectSpace(hit.Position)
		local x = Quantize.snap(localPoint.X, Quantize.Grid)
		local z = Quantize.snap(localPoint.Z, Quantize.Grid)
		return { component = component, id = id, node = node, pose = pose,
			point = localPoint, x = x, z = z, hit = hit }
	end

	-- Edge tools use screen-space segments, not a face raycast. This lets
	-- the player select an entire vertical/re-entrant edge even if the mouse
	-- is over empty background or its neighboring top face.
	local function fileEdgeTarget()
		if (activeTool~="File" and activeTool~="Smooth") or (sketchEditor and sketchEditor.active)
			or UserInputService:GetFocusedTextBox() or cameraController.dragging then
			return nil
		end
		local camera=workspace.CurrentCamera
		if not camera then return nil end
		local mouse=UserInputService:GetMouseLocation()
		if mouse.X<345 and mouse.Y<615 then return nil end
		if mouse.X>camera.ViewportSize.X-340 and mouse.Y>225 and mouse.Y<610 then
			return nil
		end
		if viewGizmo:containsPoint(mouse) or transformGizmo:capturesPoint(mouse) then
			return nil
		end
		local best,bestDistance=nil,math.huge
		for id,component in pairs(document.components) do
			local state=preview.states[id]
			if not state or state.key~=Fabricator.geometryKey(component) then continue end
			local topology=surfacePicker:get(id,preview:getModel(id),component)
			if not topology then continue end
			topology.selectedComponent=component
			local edge,distance=topology.closestEdge(topology,camera,mouse,18)
			if edge and distance and distance<bestDistance then
				local pose=Compiler.pose(component.nodes[1])
				local partFrame=topology.part.CFrame
				local localA=pose:PointToObjectSpace(partFrame:PointToWorldSpace(edge.a))
				local localB=pose:PointToObjectSpace(partFrame:PointToWorldSpace(edge.b))
				local width=SurfaceSnap.mm((tonumber(if activeTool=="Smooth"
					then smoothRadiusInput.Text else fileWidthInput.Text) or 14)/280)
				local available=EdgeAvailability.segments(localA,localB,component,width)
				-- The originating topology edge may be longer than the
				-- actual exposed edge. Pick only the unblocked segment
				-- under the pointer, then preview/commit those endpoints.
				for _,section in ipairs(available) do
					local wa=pose:PointToWorldSpace(section.a)
					local wb=pose:PointToWorldSpace(section.b)
					local pa,va=camera:WorldToViewportPoint(wa)
					local pb,vb=camera:WorldToViewportPoint(wb)
					if not va and not vb then continue end
					local origin=Vector2.new(pa.X,pa.Y)
					local vector=Vector2.new(pb.X-pa.X,pb.Y-pa.Y)
					local length2=vector:Dot(vector)
					if length2<0.1 then continue end
					local t=math.clamp((mouse-origin):Dot(vector)/length2,0,1)
					local d=(mouse-origin-vector*t).Magnitude
					if d>=math.min(bestDistance,12) then continue end
					local clipped=table.clone(edge)
					clipped.a=partFrame:PointToObjectSpace(wa)
					clipped.b=partFrame:PointToObjectSpace(wb)
					bestDistance=d
					best={id=id,component=component,node=component.nodes[1],
						pose=pose,topology=topology,edge=clipped}
				end
			end
		end
		return best
	end

	-- Derive a single validated filing operation from a current, visible
	-- manufactured edge. Hover and click use identical face normals and
	-- inside/outer classification, so a preview cannot promise another cut.
	local function fileSegments():number?
		local n=tonumber(fileSegmentsInput.Text)
		if not n or n~=math.floor(n) or n<1 or n>12 then
			return nil
		end
		return n
	end

	local function bevelData(topology,edge,pose:CFrame,width:number,segments:number)
		if not edge or #edge.faces~=2 or edge.curved then
			return nil,"Select a straight manufactured edge between two faces"
		end
		local f1,f2=topology.faces[edge.faces[1]],topology.faces[edge.faces[2]]
		if not f1 or not f2 or f1.curved or f2.curved then
			return nil,"Filing curved faces is not yet supported"
		end
		local partFrame=topology.part.CFrame
		local a=pose:PointToObjectSpace(partFrame:PointToWorldSpace(edge.a))
		local b=pose:PointToObjectSpace(partFrame:PointToWorldSpace(edge.b))
		local n1=pose:VectorToObjectSpace(partFrame:VectorToWorldSpace(f1.normal))
		local n2=pose:VectorToObjectSpace(partFrame:VectorToWorldSpace(f2.normal))
		local interior=edge.interior==true
			or ((string.find(f1.tag or "","_floor")~=nil)
				and (string.find(f2.tag or "","_wall")~=nil))
			or ((string.find(f2.tag or "","_floor")~=nil)
				and (string.find(f1.tag or "","_wall")~=nil))
		local smoothing=activeTool=="Smooth"
		if smoothing and not interior then
			return nil,"Smooth works only on concave interior edges"
		end
		if not smoothing and interior then
			return nil,"Use Smooth Inside Edge for concave edges"
		end
		-- Fillets and adjoining sharp-edge cuts cannot share a corner:
		-- their CSG volumes would intersect and recreate jagged wedges.
		local component=topology.selectedComponent
		if component then
			local function closeToSegment(p:Vector3,a:Vector3,b:Vector3)
				local d=b-a
				local t=math.clamp((p-a):Dot(d)/math.max(d:Dot(d),1e-9),0,1)
				return (p-(a+d*t)).Magnitude<0.008
			end
			local function touches(p:Vector3,q:Vector3,r:Vector3,t:Vector3)
				return closeToSegment(p,r,t) or closeToSegment(q,r,t)
					or closeToSegment(r,p,q) or closeToSegment(t,p,q)
			end
			for _,op in ipairs(component.operations or {}) do
				if op.enabled==false then continue end
				if op.kind=="SmoothInside" and touches(a,b,op.a,op.b) then
					return nil,"This edge touches an already smoothed corner"
				end
				if smoothing and op.kind=="FileMesh" and touches(a,b,op.a,op.b) then
					return nil,"Remove the adjacent File before smoothing this corner"
				end
			end
		end
		local ok,why=GeometryCutter.validateFile(a,b,n1,n2,width,smoothing,segments)
		if not ok then return nil,why end
		-- A bevel cannot be wider than either of its adjacent physical
		-- faces. Especially important for shallow recesses: cutting right
		-- through the opposite wall creates the huge triangular shards
		-- that CSG produces with overlarge, overlapping cutters.
		local dot=f1.normal:Dot(f2.normal)
		local sign=if interior then -1 else 1
		local mid=(edge.a+edge.b)/2
		for _,side in ipairs({
			{face=f1,dir=(f1.normal*dot-f2.normal).Unit*sign},
			{face=f2,dir=(f2.normal*dot-f1.normal).Unit*sign},
		}) do
			if side.face.polygon then
				local available=0
				for _,vertex in ipairs(side.face.polygon) do
					available=math.max(available,(vertex-mid):Dot(side.dir))
				end
				if available+0.002<width then
					return nil,"Chamfer width exceeds the neighboring face"
				end
			end
		end
		return {a=a,b=b,normalA=n1,normalB=n2,
			width=width,radius=width,interior=interior,segments=segments,
			taperA=false,taperB=false},nil
	end

	-- Snap drilling centers in the selected face's tangent plane. The
	-- face-normal coordinate is untouched so rotated/filleted surfaces
	-- do not push the drill origin off the actual manufactured surface.
	local function snappedFaceOrigin(target,topology,face):Vector3
		local planePoint=topology.part.CFrame:PointToWorldSpace(face.polygon[1])
		local normal=topology.part.CFrame:VectorToWorldSpace(face.normal)
		local world=SurfaceSnap.pointOnPlane(
			target.hit.Position,planePoint,normal,Quantize.Grid)
		return target.pose:PointToObjectSpace(world)
	end

	-- Passive CAD face inspection. Only show a measurement on a
	-- visible, indexed manufactured surface with no fabrication tool,
	-- camera gesture, text edit, or transform gizmo interaction.
	connectExternal(RunService.RenderStepped,function(dt)
		if not editorActive or previewOnly then return end
		if sketchEditor and sketchEditor.active then
			if selectionBorder.Visible then
				selectionBorder:Clear()
				selectionBorder.Visible=false
			end
			return
		end
		if toolVisualizer:update(dt) then
				return
		end
		if not activeTool then
			toolVisualizer:hide()
			return
		end
		if activeTool=="Measure" then
			toolVisualizer:hide()
			return
		end
		if activeTool=="File" or activeTool=="Smooth" then
			local selection=fileEdgeTarget()
			local width=millimeters(if activeTool=="Smooth" then smoothRadiusInput
				else fileWidthInput, "Edge radius")
			if not selection or not width then toolVisualizer:hide() return end
			local segments=if activeTool=="Smooth" then 8 else fileSegments()
			if not segments then toolVisualizer:hide() return end
			local plan=bevelData(selection.topology,selection.edge,selection.pose,width,segments)
			if not plan then toolVisualizer:hide() return end
			local edge=selection.edge
			local n1=selection.topology.faces[edge.faces[1]].normal
			local n2=selection.topology.faces[edge.faces[2]].normal
			if activeTool=="Smooth" then
				toolVisualizer:smoothInside(selection.topology.part,edge,width,segments,n1,n2)
			else
				toolVisualizer:meshEdge(selection.topology.part,edge,width,false,
					n1,n2,nil,nil,segments)
			end
			return
		end
		local target = fabricationHit()
		if not target then toolVisualizer:hide() return end
		local node, pose = target.node, target.pose
		if activeTool == "Drill" then
			local diameter = millimeters(diameterInput, "Diameter")
			local depth = millimeters(drillDepthInput, "Drill depth")
			if not diameter or not depth then toolVisualizer:hide() return end
			local topology=surfacePicker:get(target.id,preview:getModel(target.id),target.component)
			if not topology or topology.part~=target.hit.Instance then
				toolVisualizer:hide() return
			end
			local face=topology.faceAt(topology,target.hit.Position,target.hit.Normal)
			if not face then toolVisualizer:hide() return end
			local origin=snappedFaceOrigin(target,topology,face)
			local worldNormal=topology.part.CFrame:VectorToWorldSpace(face.normal)
			toolVisualizer:drillFace(pose,origin,
				pose:VectorToObjectSpace(worldNormal),diameter,depth,drillThrough,node.size.Magnitude,node.size)
		elseif activeTool == "Inset" then
			local margin = millimeters(insetMarginInput, "Inset border")
			local depth = millimeters(insetDepthInput, "Inset depth")
			if not margin or not depth then toolVisualizer:hide() return end
			local topology = surfacePicker:get(target.id,preview:getModel(target.id),target.component)
			if not topology or topology.part ~= target.hit.Instance then
				toolVisualizer:hide() return
			end
			local face = topology.faceAt(topology,target.hit.Position,target.hit.Normal)
			if not face then
				toolVisualizer:hide() return
			end
			local inset = FaceTools.inset(face,margin)
			if not inset then toolVisualizer:hide() return end
			toolVisualizer:meshFace(topology.part,inset,margin,depth)

		end
	end)

	connectExternal(UserInputService.InputBegan,function(input, processed)
		if not editorActive or previewOnly then return end
		if sketchEditor and sketchEditor.active then return end
		if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		if placementFlow and (placementFlow.placing or placementFlow.form.Visible) then return end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt) then return end
		if activeTool=="Measure" then
			local mm=measurementTool and measurementTool:click()
			if mm then
				message(string.format("Point distance: %.1f mm",mm))
			else
				message("Choose the second point")
			end
			return
		end
		if activeTool=="File" or activeTool=="Smooth" then
			local selection=fileEdgeTarget()
			if not selection then
				message("Hover one accessible edge segment")
				return
			end
			local width,why=millimeters(if activeTool=="Smooth" then smoothRadiusInput
				else fileWidthInput,"Edge radius")
			if not width then message(why) return end
			local segments=if activeTool=="Smooth" then 8 else fileSegments()
			if not segments then message("File segments must be a whole number from 1 to 12") return end
			local data,reason=bevelData(selection.topology,selection.edge,selection.pose,width,segments)
			if not data then message(reason or "Unable to file selected edge") return end
			if selection.id~=selectedId then selectComponent(selection.id) end
			local kind=if activeTool=="Smooth" then "SmoothInside" else "FileMesh"
			local ok,err=document:addOperation(selection.component,kind,data)
			if not ok then message(err or "Unable to modify edge") return end
			changed(selection.component)
			if kind=="FileMesh" then toolVisualizer:animateFile(selection.pose,data) end
			message(if kind=="SmoothInside" then "Smoothing interior edge · compiling CSG"
				else "Filing exposed edge segment · compiling CSG")
			return
		end
		local target = fabricationHit()
		if not target then
			-- Selection still works when the editor is not using a fabrication tool.
			if activeTool then return end
			local mouse = UserInputService:GetMouseLocation()
			if viewGizmo:containsPoint(mouse) or transformGizmo:capturesPoint(mouse) then return end
			local camera = workspace.CurrentCamera
			if not camera then return end
			local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { preview.root }
			local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
			if not hit then return end
			local model = hit.Instance:FindFirstAncestorOfClass("Model")
			local id = if model then model:GetAttribute("FORMComponentId") else nil
			if typeof(id) == "number" and document.components[id] then selectComponent(id) end
			return
		end
		if target.id ~= selectedId then selectComponent(target.id) end
		if not activeTool then return end
		local component, node = target.component, target.node
		-- Click handlers share the same local manufacturing frame as hover.
		-- 'pose' was scoped only inside RenderStepped, causing the nil
		-- PointToObjectSpace crash on every face-based operation.
		local pose = target.pose
		local x, z = target.x, target.z
		local kind = activeTool
		local data = nil
		if kind == "Drill" then
			local diameter,errorA=millimeters(diameterInput,"Diameter")
			local depth,errorB=millimeters(drillDepthInput,"Drill depth")
			if not diameter or not depth then message(errorA or errorB) return end
			local topology,why=surfacePicker:get(target.id,preview:getModel(target.id),target.component)
			if not topology then message(why or "Surface indexing in progress") return end
			if topology.part~=target.hit.Instance then message("Surface selection changed") return end
			local face=topology.faceAt(topology,target.hit.Position,target.hit.Normal)
			if not face then message("Select a visible manufactured face") return end
			local worldNormal=topology.part.CFrame:VectorToWorldSpace(face.normal)
			data={origin=snappedFaceOrigin(target,topology,face),
				normal=pose:VectorToObjectSpace(worldNormal),
				diameter=diameter,depth=depth,through=drillThrough}
			kind="DrillFace"
		elseif kind == "Inset" then
			local margin,errorA=millimeters(insetMarginInput,"Inset border")
			local depth,errorB=millimeters(insetDepthInput,"Inset depth")
			if not margin or not depth then message(errorA or errorB) return end
			local topology,why=surfacePicker:get(target.id,preview:getModel(target.id),target.component)
			if not topology then message(why or "Compiling face topology") return end
			if topology.part~=target.hit.Instance then message("Face selection is out of date") return end
			local face=topology.faceAt(topology,target.hit.Position,target.hit.Normal)
			if not face then message("No planar manufactured face under pointer") return end
			local points,reason=FaceTools.inset(face,margin)
			if not points then message(reason or "Face cannot be inset") return end
			local localPoints={}
			for _,point in ipairs(points) do
				local world=topology.part.CFrame:PointToWorldSpace(point)
				table.insert(localPoints,pose:PointToObjectSpace(world))
			end
			local worldNormal=topology.part.CFrame:VectorToWorldSpace(face.normal)
			kind="InsetFace"
			data={points=localPoints,normal=pose:VectorToObjectSpace(worldNormal),
				margin=margin,depth=depth}

		else
			return
		end
		local ok, reason = document:addOperation(component, kind, data)
		if not ok then message(reason or "Unable to apply fabrication") return end
		changed(component)
		if kind=="DrillFace" then
			toolVisualizer:animateDrill(pose,data.origin,data.normal,
				data.diameter,data.depth,data.through,node.size)
		elseif kind=="InsetFace" then
			toolVisualizer:animateInset(pose,data.points,data.normal,data.depth)
		end
		message(kind .. " operation recorded; compiling CSG")
	end)

	measurementTool=MeasurementTool.new(playerGui,preview.root)
	-- Entry from placement only requests a mode switch. The FORGE
	-- OpenWorksRuntime controller is the sole owner of mode state.
	local function enterEdit(workspaceData:any)
		-- Reentering via the mode bar can interrupt an open specification
		-- dialog. Do not leave a placement tool active in the chamber.
		if placementFlow and (placementFlow.placing or placementFlow.form.Visible) then
			placementFlow:close()
		end
		currentWorkspace=workspaceData
		worldProjection:clear()
		assemblyEnvironment:hide()
		preview.root.Parent=workspace
		editorActive=true
		preview:showOnly(if pendingSketch then -1 else selectedId)
		characterMode:setEditing(true)
		cameraController:setFocusTarget(workspaceData.center)
		cameraController:setView("Top")
		cameraController:frameBounds(CFrame.new(workspaceData.center),
			Vector3.new(workspaceData.size.X,0.05,workspaceData.size.Z))
		cameraController:setActive(true)
  if previewOnly and setPreviewEnabled then setPreviewEnabled(false) end
		gui.Enabled=true
		panel.Visible=pendingSketch==nil and selectedComponent()~=nil
		placementFlow:setLaunchVisible(false)
		grid:update(workspaceData.editCorner,workspaceData.size)
		gridUserVisible=true
		grid:setVisible(true)
		toolVisualizer:hide()
		transformGizmo:setHidden(true)
		if pendingSketch then
			local planned=pendingSketch
			task.defer(function()
				if editorActive and pendingSketch==planned then
					sketchEditor:start(nil,"First",planned)
				end
			end)
		else
			refresh()
		end
		message("Edit Chamber · sketch/fabrication workspace")
	end
	placementFlow=ComponentPlacement.new(playerGui,grid,
		function(name,size,ground)
			local workspaceData=EditWorkspace.new(ground,size,name)
			pendingSketch={name=name,corner=workspaceData.editCorner,
				worldCorner=ground,size=size}
			currentWorkspace=workspaceData
			if options.onEditRequested then
				options.onEditRequested(workspaceData)
			else
				enterEdit(workspaceData)
			end
		end,message,function()
			-- Canceling placement never enters the CAD mode.
			if editorActive and not pendingSketch then
				local selected=selectedComponent()
				if selected then
					grid:update(selected.workspaceOrigin or
						Document.minCorner(selected.nodes[1]),
						selected.workspaceSize or selected.nodes[1].size)
					grid:setVisible(true)
				end
			end
		end)
	panel.Visible=false
	gui.Enabled=false
	placementFlow:setLaunchVisible(true)
	grid:setVisible(false)
	preview.root.Parent=nil
 refresh()
 -- A clean viewport toggle: every OpenWorks edit GUI and editing
 -- adornment disappears, but the camera and unsaved sketch remain intact.
 setPreviewEnabled=function(enabled:boolean)
  if enabled and (not editorActive or transformGizmo:isDragging()) then return end
  if previewOnly==enabled then return end
  previewOnly=enabled
  if enabled then gizmoWasHidden=transformGizmo.hidden end
  gui.Enabled=editorActive and not enabled
  if sketchEditor then sketchEditor:setPreviewHidden(enabled) end
  grid:setVisible(not enabled and gridUserVisible)
  if enabled then
   toolVisualizer:stopAnimation()
   toolVisualizer:discard()
   selectionBorder:Clear()
   selectionBorder.Visible=false
   transformGizmo:setHidden(true)
   if measurementTool then measurementTool:setActive(false) end
  else
   transformGizmo:setHidden(gizmoWasHidden)
   if editorActive then refresh() end
   if activeTool=="Measure" and measurementTool then
    measurementTool:setActive(true)
   end
  end
  if options.onPreviewChanged then options.onPreviewChanged(enabled) end
 end
 togglePreview=function()
  setPreviewEnabled(not previewOnly)
 end
 connectExternal(UserInputService.InputBegan,function(input,processed)
  if not editorActive or processed or UserInputService:GetFocusedTextBox() then return end
  if input.KeyCode==Enum.KeyCode.P then togglePreview() end
 end)
	message("Character mode · Create Component places a new sketch workspace")
	return {
  setPreviewEnabled=setPreviewEnabled,
  isPreviewEnabled=function()return previewOnly end,
		getWorkspace=function()
			local selected=selectedComponent()
			if selected then
				local origin=selected.worldOrigin or (currentWorkspace and currentWorkspace.worldCorner)
					or selected.workspaceOrigin or Vector3.zero
				local size=selected.workspaceSize or selected.nodes[1].size
				return EditWorkspace.new(origin,size,selected.name)
			end
			-- A canceled first sketch is not a component. Reopening Edit
			-- without a selected manufactured component would strand the
			-- player in an empty chamber with no active sketch session.
			return if pendingSketch then currentWorkspace else nil
		end,
		enterEditor=enterEdit,
		leaveEditor=function()if leaveEditor then leaveEditor()end end,
		enterFree=function()
			if leaveEditor then leaveEditor()end
			assemblyEnvironment:hide()
			if currentWorkspace then
				worldProjection:show(preview,document,currentWorkspace)
			end
			placementFlow:setLaunchVisible(true)
		end,
		enterAssembly=function()
			if leaveEditor then leaveEditor()end
			assemblyEnvironment:show()
			if currentWorkspace then
				worldProjection:show(preview,document,currentWorkspace,
					AssemblyEnvironment.Center-
					Vector3.new(currentWorkspace.size.X*0.5,0,currentWorkspace.size.Z*0.5))
			end
			placementFlow:setLaunchVisible(false)
			characterMode:setEditing(true)
			cameraController:setFocusTarget(AssemblyEnvironment.Center)
			cameraController:setView("Front")
			cameraController:frameBounds(CFrame.new(AssemblyEnvironment.Center),
				Vector3.new(12,8,12))
			cameraController:setActive(true)
			message("Assembly Mode · physical alignment arrives in Q3")
		end,
		leaveAssembly=function()
			assemblyEnvironment:hide()
			worldProjection:clear()
			cameraController:setActive(false)
		end,
		destroy=function()
			-- FORGE lifecycle ownership: disconnect long-lived input/render
			-- listeners and release all client-only scene objects.
			if leaveEditor then leaveEditor() end
			for _,connection in ipairs(externalConnections) do
				connection:Disconnect()
			end
			table.clear(externalConnections)
			if placementFlow then placementFlow:destroy() end
			if sketchEditor then sketchEditor:destroy() end
			if viewGizmo then viewGizmo:destroy() end
			if cameraController then cameraController:destroy() end
			if transformGizmo then transformGizmo:destroy() end
			if toolVisualizer then toolVisualizer:destroy() end
			if measurementTool then measurementTool:destroy() end
			if surfacePicker then surfacePicker:destroy() end
			if grid then grid:destroy() end
			if preview then preview:destroy() end
			worldProjection:Destroy()
			assemblyEnvironment:Destroy()
			selectionBorder:Destroy()
			outlineOrigin:Destroy()
			gui:Destroy()
		end,
	}
end

return Debug
