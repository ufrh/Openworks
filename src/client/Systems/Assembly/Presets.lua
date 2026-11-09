--!strict
local Presets = {}
function Presets.build(docs, assembly, kind)
	local made = {}
	local function expect(ok, value)
		assert(ok, tostring(value))
		return value
	end
	local function layout()
		return expect(assembly:GetLayout())
	end
	local state = layout()
	local far = 12
	for _, pose in pairs(state.poses) do
		far = math.max(far, pose.Position.X - 120 + 12)
	end
	local center = Vector3.new(120 + far, 203, 0)
	local function place(c, offset, fixed)
		expect(assembly:SetPose(c.id, c.revision, layout().revision, CFrame.new(center + offset)))
		if fixed then
			expect(assembly:SetGrounded(c.id, layout().revision, true))
		end
		return c
	end
	local function box(name, size, offset)
		local x, z = size.X / 2, size.Z / 2
		local c = expect(
			docs:CreateSketchBody(
				name,
				Vector3.new(far + #made * 2, 3, 20),
				Vector3.new(-0.5, 200, -0.5),
				Vector3.new(1, 3, 1),
				{ Vector2.new(-x, -z), Vector2.new(x, -z), Vector2.new(x, z), Vector2.new(-x, z) },
				size.Y
			)
		)
		table.insert(made, c)
		return place(c, offset, true)
	end
	local ok, result = xpcall(function()
		local mover
		if kind == "Bearing" then
			local housing = box("Preset bearing housing", Vector3.new(0.6, 0.2, 0.6), Vector3.zero)
			housing = expect(
				docs:ApplyOperation(
					housing.id,
					housing.revision,
					"DrillFace",
					{
						origin = Vector3.new(0, 0.1, 0),
						normal = Vector3.yAxis,
						diameter = 31 / 280,
						depth = 0.2,
						through = true,
					}
				)
			)
			mover = expect(
				docs:CreateCylinder(
					"Preset shaft",
					Vector3.new(far + 6, 3, 20),
					Vector3.new(-0.5, 200, -0.5),
					Vector3.new(1, 3, 1),
					0.1,
					0.8
				)
			)
			table.insert(made, mover)
			place(mover, Vector3.zero, false)
			local lower = box(
				"Preset lower end plate",
				Vector3.new(0.3, 0.1, 0.3),
				Vector3.new(0, -127 / 280, 0)
			)
			local upper = box(
				"Preset upper end plate",
				Vector3.new(0.3, 0.1, 0.3),
				Vector3.new(0, 127 / 280, 0)
			)
			expect(
				assembly:RegisterRelationship(
					"RetainedBoreV1",
					mover.id,
					housing.id,
					"hole:" .. housing.operations[1].id,
					{ lower.id, upper.id },
					layout().revision
				)
			)
		else
			mover = box("Preset carriage", Vector3.new(0.2, 0.4, 0.2), Vector3.zero)
			expect(assembly:SetGrounded(mover.id, layout().revision, false))
			local fixtures = {}
			for i = 1, 4 do
				local sign = if i % 2 == 1 then -1 else 1
				local size = if i <= 2 then Vector3.new(0.1, 2, 0.2) else Vector3.new(0.2, 2, 0.1)
				local offset = if i <= 2
					then Vector3.new(sign * 43 / 280, 0, 0)
					else Vector3.new(0, 0, sign * 43 / 280)
				table.insert(fixtures, box("Preset rail " .. i, size, offset).id)
			end
			for _, sign in ipairs({ -1, 1 }) do
				table.insert(
					fixtures,
					box(
						"Preset end stop",
						Vector3.new(0.2, 0.1, 0.2),
						Vector3.new(0, sign * 0.75, 0)
					).id
				)
			end
			expect(
				assembly:RegisterRelationship(
					"LimitedGuideV1",
					mover.id,
					0,
					"",
					fixtures,
					layout().revision
				)
			)
		end
		return mover.id
	end, debug.traceback)
	if not ok then
		local failed = {}
		for _, c in ipairs(made) do
			local success, current = docs:GetSnapshot(c.id)
			if success then
				local deleted = docs:DeleteComponent(c.id, current.revision)
				if not deleted then
					table.insert(failed, tostring(c.id))
				end
			end
		end
		return false,
			tostring(result) .. (if #failed > 0
				then "\nCould not remove partial parts: " .. table.concat(failed, ", ")
				else "")
	end
	return true, result
end
return Presets
