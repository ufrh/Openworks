--!strict
-- Rebuilds a manufactured solid from its base material + ordered cut history.
-- All CSG executes in material-local coordinates; moving a finished component
-- changes its CFrame and never rebuilds its fabrication history.
local GeometryService = game:GetService("GeometryService")
local Compiler = require(script.Parent.Compiler)
local Cutters = require(script.Parent.Cutters)

local Fabricator = {}
local OPTIONS = { SplitApart = false }

function Fabricator.requiresCompile(component): boolean
	return Compiler.requiresBoolean(component.nodes[1]) or #(component.operations or {}) > 0
end

function Fabricator.geometryKey(component): string
	local pieces = { Compiler.geometryKey(component.nodes[1]) }
	for _, op in ipairs(component.operations or {}) do
		if op.kind == "Drill" then
			table.insert(pieces, string.format("D|%.4f|%.4f|%.4f", op.x, op.z, op.diameter))
		elseif op.kind == "Saw" then
			table.insert(pieces, string.format("S|%.4f|%.4f|%.4f|%.4f|%.4f|%s",
				op.x1, op.z1, op.x2, op.z2, op.kerf, tostring(op.useMesh)))
		end
	end
	return table.concat(pieces, ";")
end

local function subtract(source: BasePart, cutter: BasePart): (boolean, any)
	local ok, result = pcall(function()
		return GeometryService:SubtractAsync(source, { cutter }, OPTIONS)
	end)
	if not ok then return false, result end
	if #result ~= 1 then
		for _, part in ipairs(result) do part:Destroy() end
		return false, "CSG returned " .. tostring(#result) .. " solids, expected one"
	end
	return true, result[1]
end

-- Returns a material-local solid and a status summary. Intermediate source
-- solids, cutters, and EditableMeshes are all disposed deterministically.
function Fabricator.compile(component): (BasePart, string)
	local node = component.nodes[1]
	local current = Compiler.compileTemplate(node)
	local meshCuts, nativeFallbacks = 0, 0
	for _, op in ipairs(component.operations or {}) do
		local preferMesh = op.kind == "Saw" and op.useMesh == true
		local created, cutter, release, mode = pcall(Cutters.create, node, op, preferMesh)
		if not created then
			current:Destroy()
			error("Cutter generation failed: " .. tostring(cutter), 0)
		end
		local success, result = subtract(current, cutter)
		release()
		if not success and mode == "editable" then
			-- Mesh CSG may be unavailable without the beta. Retry the *same*
			-- cut with a disposable native part, never leak a temporary mesh.
			nativeFallbacks += 1
			local ok, fallback, releaseFallback = pcall(Cutters.create, node, op, false)
			if not ok then
				current:Destroy()
				error("Native cutter fallback failed: " .. tostring(fallback), 0)
			end
			success, result = subtract(current, fallback)
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
		current.Anchored = true
	end
	return current, string.format("%d cuts (%d mesh, %d native fallback)",
		#(component.operations or {}), meshCuts, nativeFallbacks)
end

return Fabricator
