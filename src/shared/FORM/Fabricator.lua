--!strict
-- Rebuilds a manufactured solid from its base material + ordered cut history.
-- All CSG executes in material-local coordinates; moving a finished component
-- changes its CFrame and never rebuilds its fabrication history.
local GeometryService = game:GetService("GeometryService")
local Compiler = require(script.Parent.Compiler)
local Cutters = require(script.Parent.Cutters)
local Extrusion = require(script.Parent.Extrusion)
local FileCutter = require(script.Parent.FileCutter)
local GeometryCutter = require(script.Parent.GeometryCutter)

local Fabricator = {}
local OPTIONS = { SplitApart = false }
local function vectorKey(v:Vector3):string
	return string.format("%.6f,%.6f,%.6f",v.X,v.Y,v.Z)
end

function Fabricator.requiresCompile(component): boolean
	for _, op in ipairs(component.operations or {}) do
		if op.enabled ~= false then return true end
	end
	return false
end

function Fabricator.geometryKey(component): string
	local pieces = { Compiler.geometryKey(component.nodes[1]) }
	for _, op in ipairs(component.operations or {}) do
		table.insert(pieces, if op.enabled == false then "disabled" else "enabled")
		if op.kind == "Drill" then
			table.insert(pieces, string.format("D|%.6f|%.6f|%.6f|%.6f|%s",
				op.x, op.z, op.diameter, op.depth or 0, tostring(op.through ~= false)))
		elseif op.kind == "DrillFace" then
			table.insert(pieces, string.format("DF|%.6f|%.6f|%s|%s|%s",
				op.diameter,op.depth,tostring(op.through),vectorKey(op.origin),vectorKey(op.normal)))
		elseif op.kind == "GrooveFace" then
			table.insert(pieces,string.format("GF|%.6f|%.6f|%s|%s|%s|%s",
				op.width,op.depth,tostring(op.through),vectorKey(op.a),
				vectorKey(op.b),vectorKey(op.normal)))
		elseif op.kind == "Saw" or op.kind == "Groove" then
			table.insert(pieces, string.format("%s|%.6f|%.6f|%.6f|%.6f|%.6f|%.6f|%s|%s",
				op.kind, op.x1, op.z1, op.x2, op.z2, op.kerf,
				op.depth or 0, tostring(op.useMesh), tostring(op.through)))
		elseif op.kind == "Inset" then
			table.insert(pieces, string.format("I|%.6f|%.6f", op.margin, op.depth))
		elseif op.kind == "File" then
			table.insert(pieces, string.format("F|%s|%.6f", op.edge, op.width))
		elseif op.kind == "FileMesh" then
			table.insert(pieces, string.format("FM|%.6f|%s|%s|%s|%s|%s|%s|%s",
				op.width,vectorKey(op.a),vectorKey(op.b),vectorKey(op.normalA),vectorKey(op.normalB),
				tostring(op.interior==true),tostring(op.taperA==true),tostring(op.taperB==true)))
		elseif op.kind == "InsetFace" then
			table.insert(pieces, string.format("IF|%.6f|%.6f|%s",
				op.margin,op.depth,vectorKey(op.normal)))
			for _,point in ipairs(op.points) do table.insert(pieces,vectorKey(point)) end
		elseif op.kind == "SketchExtrude" then
			table.insert(pieces, string.format("E|%s|%.4f|%s",
				op.mode, op.depth, tostring(op.through)))
			for _, point in ipairs(op.points) do
				table.insert(pieces, string.format("%.4f,%.4f", point.X, point.Y))
			end
		end
	end
	return "FORM_EXTERIOR_FILE_ONLY_V3;"..table.concat(pieces, ";")
end

local function combine(source: BasePart, cutter: BasePart, mode: string): (boolean, any)
	-- GeometryService may bake the input face colors into every output
	-- MeshPart; a final .Color alone cannot override those multipliers.
	-- Neutralize *all* inputs, including subsequent CSG intermediates.
	for _, inputPart in ipairs({ source, cutter }) do
		inputPart.Color = Color3.new(1, 1, 1)
		inputPart.Material = Enum.Material.SmoothPlastic
		inputPart.Reflectance = 0
		inputPart.Transparency = 0
		if inputPart:IsA("PartOperation") then
			inputPart.UsePartColor = true
		elseif inputPart:IsA("MeshPart") then
			inputPart.TextureID = ""
		end
	end
	local ok, result = pcall(function()
		if mode == "Add" then
			return GeometryService:UnionAsync(source, { cutter }, OPTIONS)
		elseif mode == "Intersect" then
			return GeometryService:IntersectAsync(source, { cutter }, OPTIONS)
		end
		return GeometryService:SubtractAsync(source, { cutter }, OPTIONS)
	end)
	if not ok then return false, result end
	if typeof(result) ~= "table" then return false, "CSG returned no result list" end
	if #result ~= 1 then
		for _, part in ipairs(result) do part:Destroy() end
		return false, "CSG returned " .. tostring(#result) .. " solids, expected one; empty or separated cuts may need different geometry"
	end
	return true, result[1]
end

-- Returns a material-local solid and a status summary. Intermediate source
-- solids, cutters, and EditableMeshes are all disposed deterministically.
local function compileUnlocked(component): (BasePart, string)
	local node = component.nodes[1]
	local current = Compiler.nativePart(node)
	local meshCuts, nativeFallbacks, pausedInsideFiles = 0, 0, 0
	for _, op in ipairs(component.operations or {}) do
		if op.enabled == false then continue end
		-- Keep historical interior File entries for possible later repair,
		-- but never compile their additive wedges in the exterior-only
		-- prototype. Those wedges repeatedly refilled existing cuts.
		if op.kind == "FileMesh" and op.interior == true then
			pausedInsideFiles+=1
			continue
		end
		if op.kind == "SketchExtrude" or op.kind == "File"
			or op.kind == "FileMesh" or op.kind == "InsetFace" then
			local function createTool()
				if op.kind == "File" then return FileCutter.create(node,op) end
				if op.kind == "FileMesh" then
					return GeometryCutter.file(op.a,op.b,op.normalA,op.normalB,
						op.width,false)
				end
				if op.kind == "InsetFace" then
					local margin=0.04
					local profile={}
					for _,p in ipairs(op.points) do
						table.insert(profile,p+op.normal*margin)
					end
					return GeometryCutter.prism(profile,-op.normal*(op.depth+margin*2))
				end
				return Extrusion.create(node,op)
			end
			local generated, cutter, release = pcall(createTool)
			if not generated then
				current:Destroy()
				error("Sketch extrusion " .. tostring(op.id) .. ": " .. tostring(cutter), 0)
			end
			-- Exterior filing ONLY. No additive wedges or corner patch.
			local mode = if op.kind == "SketchExtrude" then op.mode else "Remove"
			local success, result = combine(current, cutter, mode)
			release()
			if not success then
				current:Destroy()
				error("Fabrication " .. tostring(mode) .. " failed: " .. tostring(result), 0)
			end
			current:Destroy()
			current = result
		else
			local preferMesh = op.kind == "Saw" and op.useMesh == true
			local created, cutter, release, mode = pcall(Cutters.create, node, op, preferMesh)
			if not created then
				current:Destroy()
				error("Cutter generation failed: " .. tostring(cutter), 0)
			end
			local success, result = combine(current, cutter, "Remove")
			release()
			if not success and mode == "editable" then
				-- Straight saw kerfs have a lossless native-part fallback.
				nativeFallbacks += 1
				local ok, fallback, releaseFallback = pcall(Cutters.create, node, op, false)
				if not ok then
					current:Destroy()
					error("Native cutter fallback failed: " .. tostring(fallback), 0)
				end
				success, result = combine(current, fallback, "Remove")
				releaseFallback()
			elseif preferMesh and mode ~= "editable" then
				nativeFallbacks += 1
			elseif mode == "editable" then
				meshCuts += 1
			end
			if not success then
				current:Destroy()
				error("Fabrication " .. tostring(op.id) .. " failed: " .. tostring(result), 0)
			end
			current:Destroy()
			current = result
		end
		current.Anchored = true


	end
	return current, string.format("%d features (%d mesh saws, %d fallback, %d paused inside files)",
		#(component.operations or {}), meshCuts, nativeFallbacks, pausedInsideFiles)
end

-- Bound peak temporary EditableMesh use: only one manufacturing replay
-- allocates cutter meshes at a time. Always release on success or error.
local working = false
function Fabricator.compile(component): (BasePart, string)
	while working do task.wait() end
	working = true
	local ok, result, summary = pcall(compileUnlocked, component)
	working = false
	if not ok then error(result, 0) end
	return result, summary
end

return Fabricator
