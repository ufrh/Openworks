--!strict
-- A dimensioned, manufactured slider-crank demonstration. Each component
-- passes through the same FORGE manufacturing and assembly validation APIs
-- available to players. No invisible links or automatically inferred welds.
local Preset = {}
local MM = 280
local HOLE = 0.13
local PIN = 0.12
local STAGE = Vector3.new(120, 203, 0)

function Preset.build(documents: any, assembly: any): (boolean, any)
	local made = {}

	local function requireResult(ok: boolean, result: any): any
		if not ok then
			error(tostring(result), 0)
		end
		return result
	end

	local function layout(): any
		return requireResult(assembly:GetLayout())
	end

	local occupiedX = 12
	for _, pose in pairs(layout().poses) do
		occupiedX = math.max(occupiedX, pose.Position.X - 120 + 12)
	end
	local origin = STAGE + Vector3.new(occupiedX, 0, 0)
	local theta = math.rad(40)
	local radius = 0.35
	local rodLength = 1.25
	local endCrank = Vector3.new(radius * math.cos(theta), 0, radius * math.sin(theta))
	local slideX = endCrank.X + math.sqrt(rodLength ^ 2 - endCrank.Z ^ 2)
	local endSlide = Vector3.new(slideX, 0, 0)
	local rodVector = endSlide - endCrank
	local yawRod = -math.atan2(rodVector.Z, rodVector.X)

	local function created(component: any): any
		table.insert(made, component.id)
		return component
	end

	local function move(component: any, frame: CFrame, grounded: boolean?): any
		requireResult(assembly:SetPose(component.id, component.revision, layout().revision, frame))
		if grounded then
			requireResult(assembly:SetGrounded(component.id, layout().revision, true))
		end
		return component
	end

	local function plate(name: string, size: Vector3, frame: CFrame,
		grounded: boolean?, holes: { number }?): (any, { string })
		local w = math.max(2.2, size.X + 0.2)
		local d = math.max(0.8, size.Z + 0.2)
		local hx, hz = size.X * 0.5, size.Z * 0.5
		local component = created(requireResult(documents:CreateSketchBody(
			name,
			Vector3.new(occupiedX + #made * 3, 3, 25),
			Vector3.new(-w * 0.5, 200, -d * 0.5),
			Vector3.new(w, 3, d),
			{
				Vector2.new(-hx, -hz),
				Vector2.new(hx, -hz),
				Vector2.new(hx, hz),
				Vector2.new(-hx, hz),
			},
			size.Y
		)))
		local featureIds = {}
		for _, x in ipairs(holes or {}) do
			component = requireResult(documents:ApplyOperation(
				component.id, component.revision, "DrillFace", {
					origin = Vector3.new(x, size.Y * 0.5, 0),
					normal = Vector3.yAxis,
					diameter = HOLE,
					depth = size.Y,
					through = true,
				}
			))
			table.insert(featureIds, "hole:" .. component.operations[#component.operations].id)
		end
		return move(component, CFrame.new(origin + frame.Position) * frame.Rotation, grounded), featureIds
	end

	local function shaft(name: string, point: Vector3, length: number): any
		local component = created(requireResult(documents:CreateCylinder(
			name,
			Vector3.new(occupiedX + #made * 3, 3, 25),
			Vector3.new(-1.1, 200, -0.5),
			Vector3.new(2.2, 3, 1),
			PIN, length
		)))
		return move(component, CFrame.new(origin + point), false)
	end

	local function pivot(name: string, body: any, bodyFeature: string,
		link: any, linkFeature: string, point: Vector3, length: number)
		local pin = shaft(name .. " · pin", point, length)
		local caps = {}
		for _, sign in ipairs({-1, 1}) do
			local height = point.Y + sign * (length * 0.5 + 0.04)
			local cap = plate(
				name .. (if sign < 0 then " · lower cap" else " · upper cap"),
				Vector3.new(0.20, 0.08, 0.20),
				CFrame.new(Vector3.new(point.X, height, point.Z))
			)
			table.insert(caps, cap.id)
		end
		requireResult(assembly:RegisterRelationship(
			"RetainedPivotV1", link.id, body.id, bodyFeature,
			{pin.id, caps[1], caps[2]}, layout().revision, linkFeature
		))
	end

	local function rail(name: string, size: Vector3, offset: Vector3): number
		local component = plate(
			name, size, CFrame.new(offset), true
		)
		return component.id
	end

	local success, result = xpcall(function()
		local base, baseHoles = plate(
			"Crank · grounded mount",
			Vector3.new(0.25, 0.10, 0.25),
			CFrame.new(Vector3.zero),
			true,
			{0}
		)
		local crank, crankHoles = plate(
			"Crank · 98 mm throw",
			Vector3.new(0.59, 0.10, 0.24),
			CFrame.new(endCrank * 0.5 + Vector3.new(0, 0.20, 0))
				* CFrame.Angles(0, -theta, 0),
			false,
			{-radius * 0.5, radius * 0.5}
		)
		local rod, rodHoles = plate(
			"Connecting rod · 350 mm centers",
			Vector3.new(1.42, 0.10, 0.24),
			CFrame.new((endCrank + endSlide) * 0.5 + Vector3.new(0, 0.40, 0))
				* CFrame.Angles(0, yawRod, 0),
			false,
			{-rodLength * 0.5, rodLength * 0.5}
		)
		local slider, sliderHoles = plate(
			"Slider · extended carriage",
			Vector3.new(1.80, 0.14, 0.24),
			CFrame.new(Vector3.new(slideX - 0.8, 0.75, 0)),
			false,
			{0.8}
		)

		pivot("Main crank", base, baseHoles[1], crank, crankHoles[1],
			Vector3.new(0, 0.10, 0), 0.70)
		pivot("Crank pin", crank, crankHoles[2], rod, rodHoles[1],
			endCrank + Vector3.new(0, 0.30, 0), 0.55)
		pivot("Crosshead pin", rod, rodHoles[2], slider, sliderHoles[1],
			endSlide + Vector3.new(0, 0.575, 0), 0.75)

		-- Four separate stock rails form a physical rectangular guide.
		-- The rails occupy the left portion of the long carriage, keeping
		-- the crosshead pin clear of the rail channel throughout its stroke.
		local gap = 1 / MM
		local railCenterX = 0.20
		local rails = {}
		for _, sign in ipairs({-1, 1}) do
			table.insert(rails, rail(
				"Guide · upper/lower rail",
				Vector3.new(1.20, 0.10, 0.24),
				Vector3.new(railCenterX, 0.75 + sign * (0.07 + 0.05 + gap), 0)
			))
		end
		for _, sign in ipairs({-1, 1}) do
			table.insert(rails, rail(
				"Guide · lateral rail",
				Vector3.new(1.20, 0.14, 0.10),
				Vector3.new(railCenterX, 0.75, sign * (0.12 + 0.05 + gap))
			))
		end
		for _, x in ipairs({-0.90, 1.85}) do
			table.insert(rails, rail(
				"Guide · travel stop",
				Vector3.new(0.10, 0.34, 0.34),
				Vector3.new(x, 0.75, 0)
			))
		end
		requireResult(assembly:RegisterRelationship(
			"LimitedGuideV1", slider.id, 0, "", rails,
			layout().revision, nil, "X"
		))
		-- A torque drive is intentionally NOT manufactured or auto-installed;
		-- the Simulation controls provide an external test-bench motor.
		return crank.id
	end, function(err)
		return tostring(err)
	end)

	if not success then
		for i = #made, 1, -1 do
			local ok, snapshot = documents:GetSnapshot(made[i])
			if ok then
				pcall(function()
					documents:DeleteComponent(snapshot.id, snapshot.revision)
				end)
			end
		end
		return false, result
	end
	return true, result
end

return Preset
