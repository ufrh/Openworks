local Responsive = {} do
	Responsive.DefaultReference = Vector2.new(1920, 1080)
	Responsive.DefaultStrokeLODThreshold = .5
	Responsive.DefaultStrokeLODBoost = 1

	local StrokeState = setmetatable({}, {__mode = 'k'})

	local function ResolveReference(Reference)
		if typeof(Reference) == 'Vector2' then
			return Vector2.new(math.max(Reference.X, 1), math.max(Reference.Y, 1))
		end

		if type(Reference) == 'table' then
			local Width = tonumber(Reference.Width or Reference.X)
			local Height = tonumber(Reference.Height or Reference.Y)
			if Width and Height then
				return Vector2.new(math.max(Width, 1), math.max(Height, 1))
			end
		end

		return Responsive.DefaultReference
	end

	function Responsive.ResolveReference(Reference)
		return ResolveReference(Reference)
	end

	function Responsive.Calculate(ViewportSize, Reference, ScaleMode)
		assert(typeof(ViewportSize) == 'Vector2', 'Responsive.Calculate viewport must be a Vector2.')

		local Viewport = Vector2.new(math.max(ViewportSize.X, 1), math.max(ViewportSize.Y, 1))
		local Design = ResolveReference(Reference)
		local Mode = tostring(ScaleMode or 'Fit')
		if Mode == 'AnchoredFit' then Mode = 'Fit' end

		local Scale
		if Mode == 'None' then
			Scale = 1
		elseif Mode == 'Width' then
			Scale = Viewport.X / Design.X
		elseif Mode == 'Height' then
			Scale = Viewport.Y / Design.Y
		elseif Mode == 'Fill' then
			Scale = math.max(Viewport.X / Design.X, Viewport.Y / Design.Y)
		else
			Scale = math.min(Viewport.X / Design.X, Viewport.Y / Design.Y)
		end
		Scale = math.max(Scale, .001)

		return Scale, Vector2.new(Viewport.X / Scale, Viewport.Y / Scale), Design
	end

	function Responsive.ApplyStrokeLOD(Canvas, Scale, Reference)
		if not Canvas then return false end

		local Threshold = type(Reference) == 'table' and tonumber(Reference.StrokeLODThreshold)
			or Responsive.DefaultStrokeLODThreshold
		local Boost = type(Reference) == 'table' and tonumber(Reference.StrokeLODBoost)
			or Responsive.DefaultStrokeLODBoost
		Threshold = Threshold or Responsive.DefaultStrokeLODThreshold
		Boost = math.max(Boost or Responsive.DefaultStrokeLODBoost, 0)

		local Active = Scale < Threshold
		for _, Descendant in ipairs(Canvas:GetDescendants()) do
			if Descendant:IsA('UIStroke') then
				local State = StrokeState[Descendant]
				if not State then
					State = {
						Base = Descendant.Thickness,
						Applied = Descendant.Thickness
					}
					StrokeState[Descendant] = State
				elseif math.abs(Descendant.Thickness - State.Applied) > .0001 then
					State.Base = Descendant.Thickness
				end

				local Target = State.Base + (Active and Boost or 0)
				if math.abs(Descendant.Thickness - Target) > .0001 then
					Descendant.Thickness = Target
				end
				State.Applied = Target
			end
		end

		return Active
	end

	function Responsive.Apply(Canvas, ScaleObject, ViewportSize, Reference, ScaleMode)
		assert(Canvas and Canvas:IsA('GuiObject'), 'Responsive.Apply requires a GuiObject canvas.')
		assert(ScaleObject and ScaleObject:IsA('UIScale'), 'Responsive.Apply requires a UIScale.')

		local Scale, LogicalSize = Responsive.Calculate(ViewportSize, Reference, ScaleMode)
		Canvas.AnchorPoint = Vector2.zero
		Canvas.Position = UDim2.fromOffset(0, 0)
		Canvas.Size = UDim2.fromOffset(LogicalSize.X, LogicalSize.Y)
		ScaleObject.Scale = Scale
		Responsive.ApplyStrokeLOD(Canvas, Scale, Reference)
		return Scale, LogicalSize
	end

	function Responsive.Bind(Viewport, Canvas, ScaleObject, Reference, ScaleMode)
		assert(Viewport and Viewport:IsA('GuiObject'), 'Responsive.Bind requires a GuiObject viewport.')

		local Handle = {
			Viewport = Viewport,
			Canvas = Canvas,
			ScaleObject = ScaleObject,
			Reference = Reference,
			ScaleMode = ScaleMode or 'Fit',
			Scale = 1,
			LogicalSize = ResolveReference(Reference),
			Connection = nil,
			Destroyed = false
		}

		function Handle:Update()
			if self.Destroyed or not self.Viewport.Parent then return self.Scale, self.LogicalSize end
			local Size = self.Viewport.AbsoluteSize
			if Size.X <= 0 or Size.Y <= 0 then return self.Scale, self.LogicalSize end

			self.Scale, self.LogicalSize = Responsive.Apply(
				self.Canvas,
				self.ScaleObject,
				Size,
				self.Reference,
				self.ScaleMode
			)
			return self.Scale, self.LogicalSize
		end

		function Handle:Destroy()
			if self.Destroyed then return end
			self.Destroyed = true
			if self.Connection then self.Connection:Disconnect(); self.Connection = nil end
			if self.DescendantConnection then self.DescendantConnection:Disconnect(); self.DescendantConnection = nil end
		end

		Handle.Connection = Viewport:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()
			Handle:Update()
		end)
		Handle.DescendantConnection = Canvas.DescendantAdded:Connect(function(Descendant)
			if Descendant:IsA('UIStroke') then task.defer(function() Handle:Update() end) end
		end)
		task.defer(function() Handle:Update() end)
		return Handle
	end
end

return table.freeze(Responsive);
