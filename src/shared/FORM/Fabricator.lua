--!strict
-- Rebuilds a manufactured solid from its base material + ordered cut history.
-- All CSG executes in material-local coordinates; moving a finished component
-- changes its CFrame and never rebuilds its fabrication history.
local GeometryService = game:GetService("GeometryService")
local Compiler = require(script.Parent.Compiler)
local Cutters = require(script.Parent.Cutters)
local Extrusion = require(script.Parent.Extrusion)

local Fabricator = {}
local OPTIONS = { SplitApart = false }

function Fabricator.requiresCompile(component): boolean
	return #(component.operations or {}) > 0
end

function Fabricator.geometryKey(component): string
	local pieces = { Compiler.geometryKey(component.nodes[1]) }
	for _, op in ipairs(component.operations or {}) do
		if op.kind == "Drill" then
			table.insert(pieces, string.format("D|%.4f|%.4f|%.4f", op.x, op.z, op.diameter))
		elseif op.kind == "Saw" then
			table.insert(pieces, string.format("S|%.4f|%.4f|%.4f|%.4f|%.4f|%s",
				op.x1, op.z1, op.x2, op.z2, op.kerf, tostring(op.useMesh)))
		elseif op.kind == "SketchExtrude" then
			table.insert(pieces, string.format("E|%s|%.4f|%s",
				op.mode, op.depth, tostring(op.through)))
			for _, point in ipairs(op.points) do
				table.insert(pieces, string.format("%.4f,%.4f", point.X, point.Y))
			end
		end
	end
	return table.concat(pieces, ";")
end

local function combine(source: BasePart, cutter: BasePart, mode: string): (boolean, any)
	local ok, result = pcall(function()
		if mode == "Add" then
			return GeometryService:UnionAsync(source, { cutter }, OPTIONS)
		elseif mode == "Intersect" then
			return GeometryService:IntersectAsync(source, { cutter }, OPTIONS)
		end
		return GeometryService:SubtractAsync(source, { cutter }, OPTIONS)
	end)
	if not ok then return false, result end
	if #result ~= 1 then
		for _, part in ipairs(result) do part:Destroy() end
		return false, "CSG returned " .. tostring(#result) .. " solids, expected one; empty or separated cuts may need different geometry"
	end
	return true, result[1]
end

-- Returns a material-local solid and a status summary. Intermediate source
-- solids, cutters, and EditableMeshes are all disposed deterministically.
function Fabricator.compile(component): (BasePart, string)
	local node = component.nodes[1]
	local current = Compiler.nativePart(node)
	local meshCuts, nativeFallbacks = 0, 0
	for _, op in ipairs(component.operations or {}) do
		if op.kind == "SketchExtrude" then
			local generated, cutter, release = pcall(Extrusion.create, node, op)
			if not generated then
				current:Destroy()
				error("Sketch extrusion " .. tostring(op.id) .. ": " .. tostring(cutter), 0)
			end
			local success, result = combine(current, cutter, op.mode)
			release()
			if not success then
				current:Destroy()
				error("Sketch " .. tostring(op.mode) .. " failed: " .. tostring(result), 0)
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
	return current, string.format("%d features (%d mesh saws, %d fallback)",
		#(component.operations or {}), meshCuts, nativeFallbacks)
end

return Fabricator
