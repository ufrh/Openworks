local TweenService = game:GetService('TweenService')
local RunService = game:GetService('RunService')

local Widget = require(script.Parent.Widget)
local UserWidget = require(script.Parent.UserWidget)
local ProjectComponent = require(script.Parent.ProjectComponent)
local Animation = require(script.Parent.Animation)
local StyleSet = require(script.Parent.StyleSet)
local State = require(script.Parent.State)
local Responsive = require(script.Parent.Responsive)

local ProjectRuntime = {}
ProjectRuntime.__index = ProjectRuntime

local function ValidateProjectData(UI, Data)
	assert(type(Data) == 'table' and Data.Schema == 'FORGE.UI.Project', 'ProjectRuntime requires a FORGE UI project package.')
	assert(tonumber(Data.Version) == 1, 'ProjectRuntime requires FORGE.UI.Project version 1.')
	assert(Data.RuntimeAPI == UI.Version, 'ProjectRuntime package targets FORGE.UI ' .. tostring(Data.RuntimeAPI) .. ', runtime is ' .. tostring(UI.Version) .. '.')
	assert(type(Data.Screens) == 'table' and type(Data.StartScreen) == 'string' and Data.StartScreen ~= '', 'ProjectRuntime package is missing a valid start screen.')
	return Data
end

local function ResolveData(Data, Path)
	local Current = Data
	for Part in tostring(Path or ''):gmatch('[^%.]+') do
		if type(Current) ~= 'table' then return nil end
		Current = Current[Part]
		if Current == nil then return nil end
	end
	return Current
end

local function ResolveRelative(Object, Path)
	if not Object or Path == nil or Path == '' or Path == 'Root' then return Object end
	local Current = Object
	for Part in tostring(Path):gmatch('[^/]+') do
		Current = Current and Current:FindFirstChild(Part)
		if not Current then return nil end
	end
	return Current
end

local function SiblingKeys(Items)
	local Counts, Seen, Keys = {}, {}, {}

	for _, Item in ipairs(Items or {}) do
		local Name = tostring(Item.Name)
		Counts[Name] = (Counts[Name] or 0) + 1
	end

	for Index, Item in ipairs(Items or {}) do
		local Name = tostring(Item.Name)
		local RuntimeKey = type(Item) == 'table' and Item.RuntimeKey or nil
		Seen[Name] = (Seen[Name] or 0) + 1
		Keys[Index] = RuntimeKey
			or (Counts[Name] > 1 and (Name .. '#' .. Seen[Name]) or Name)
	end

	return Keys
end

local function ApplyProperties(Object, Properties)
	for Property, Value in pairs(Properties or {}) do
		pcall(function() Object[Property] = Value end)
	end
end

local function ReferenceViewport(Definition)
	local Reference = Definition and Definition.Reference
	if type(Reference) ~= 'table' then return nil end

	local Width = tonumber(Reference.Width)
	local Height = tonumber(Reference.Height)
	if not Width or not Height or Width <= 0 or Height <= 0 then return nil end

	return {
		Width = Width,
		Height = Height,
		Device = Reference.Device,
		ScaleMode = Reference.ScaleMode or 'Fit',
		StrokeLODThreshold = tonumber(Reference.StrokeLODThreshold) or .5,
		StrokeLODBoost = tonumber(Reference.StrokeLODBoost) or 1
	}
end

local function ReferenceViewportFromTemplate(Template)
	if not Template then return nil end

	local Width = tonumber(Template:GetAttribute('FORGEReferenceWidth'))
	local Height = tonumber(Template:GetAttribute('FORGEReferenceHeight'))
	if not Width or not Height or Width <= 0 or Height <= 0 then return nil end

	return {
		Width = Width,
		Height = Height,
		Device = Template:GetAttribute('FORGEReferenceDevice'),
		ScaleMode = Template:GetAttribute('FORGEReferenceScaleMode') or 'Fit',
		StrokeLODThreshold = tonumber(Template:GetAttribute('FORGEStrokeLODThreshold')) or .5,
		StrokeLODBoost = tonumber(Template:GetAttribute('FORGEStrokeLODBoost')) or 1
	}
end

local function EffectiveUIScale(Object)
	local Scale = 1
	local Current = Object
	while Current do
		if Current:IsA('GuiObject') then
			for _, Child in ipairs(Current:GetChildren()) do
				if Child:IsA('UIScale') then Scale *= Child.Scale end
			end
		end
		Current = Current.Parent
	end
	return math.max(Scale, .001)
end

local function RuntimeScrollerContentHeight(Root, Content)
	local Height, Count = 0, 0
	for _, Child in ipairs(Content:GetChildren()) do
		if Child:IsA('GuiObject')
			and Child:GetAttribute('FORGEStyleInternal') ~= true
			and Child:GetAttribute('FORGEHierarchyInternal') ~= true
		then
			Count += 1
			local Stored = tonumber(Child:GetAttribute('FORGEScrollerItemHeight'))
			if Stored and Stored > 0 then
				Height += Stored
			else
				local Axis = Child.Size.Y
				if math.abs(Axis.Scale) < .000001 then
					Height += math.max(0, Axis.Offset)
				else
					Height += math.max(0, Child.AbsoluteSize.Y / EffectiveUIScale(Child))
				end
			end
		end
	end

	local Gap = math.max(0, tonumber(Root:GetAttribute('FORGEGap')) or 0)
	local Padding = math.max(0, tonumber(Root:GetAttribute('FORGEPadding')) or 0)
	if Count > 1 then Height += Gap * (Count - 1) end
	return math.max(0, Height + Padding * 2)
end

local function BindRuntimeScroller(Screen, Root)
	if not Root or Root:GetAttribute('FORGESimpleKind') ~= 'Scroller' then return end

	local Viewport = Root:FindFirstChild('Viewport')
	local Scroll = Viewport and Viewport:FindFirstChild('Scroll')
	local Content = Scroll and Scroll:FindFirstChild('Content')
	local Track = Root:FindFirstChild('_FORGEScrollBar')
	local Inset = Track and Track:FindFirstChild('Inset')
	local Fill = Inset and Inset:FindFirstChild('Fill')
	if not Scroll or not Content or not Track or not Inset or not Fill then return end

	local function Refresh()
		local Scale = EffectiveUIScale(Scroll)
		local ViewportHeight = Scroll.AbsoluteWindowSize.Y / Scale
		if ViewportHeight <= 0 then ViewportHeight = Scroll.AbsoluteSize.Y / Scale end
		ViewportHeight = math.max(ViewportHeight, 1)

		local ContentHeight = RuntimeScrollerContentHeight(Root, Content)
		local DesiredCanvas = math.max(math.floor(ContentHeight + .5), 0)
		if Scroll.CanvasSize.Y.Scale ~= 0 or math.abs(Scroll.CanvasSize.Y.Offset - DesiredCanvas) > .5 then
			Scroll.CanvasSize = UDim2.fromOffset(0, DesiredCanvas)
		end

		local Canvas = math.max(ContentHeight, ViewportHeight)
		local Inner = math.max(Inset.AbsoluteSize.Y / Scale, 0)
		if Inner <= 0 then
			local Pixels = math.max(0, tonumber(Root:GetAttribute('FORGEScrollBarInset')) or 2)
			Inner = math.max(Track.AbsoluteSize.Y / Scale - Pixels * 2, 0)
		end

		local Ratio = Canvas > 0 and math.clamp(ViewportHeight / Canvas, 0, 1) or 1
		local MinThumb = math.min(math.max(tonumber(Root:GetAttribute('FORGEScrollBarMinThumb')) or 18, 1), Inner)
		local ThumbHeight = math.clamp(Inner * Ratio, MinThumb, Inner)
		if ContentHeight <= ViewportHeight + 1 then ThumbHeight = Inner end

		local Travel = math.max(Inner - ThumbHeight, 0)
		local MaxCanvas = math.max(ContentHeight - ViewportHeight, 0)
		local CanvasY = math.clamp(Scroll.CanvasPosition.Y, 0, MaxCanvas)
		local Alpha = MaxCanvas > 0 and CanvasY / MaxCanvas or 0

		Track.Visible = true
		Fill.AnchorPoint = Vector2.zero
		Fill.Position = UDim2.fromOffset(0, math.floor(Travel * Alpha + .5))
		Fill.Size = UDim2.new(1, 0, 0, math.max(math.floor(ThumbHeight + .5), 0))
	end

	local RefreshQueued = false
	local function Queue()
		if RefreshQueued then return end
		RefreshQueued = true
		task.defer(function()
			RefreshQueued = false
			if Root.Parent then Refresh() end
		end)
	end

	Screen.ScrollerConnections = Screen.ScrollerConnections or {}
	table.insert(Screen.ScrollerConnections, Scroll:GetPropertyChangedSignal('CanvasPosition'):Connect(Queue))
	table.insert(Screen.ScrollerConnections, Scroll:GetPropertyChangedSignal('AbsoluteWindowSize'):Connect(Queue))
	table.insert(Screen.ScrollerConnections, Scroll:GetPropertyChangedSignal('AbsoluteSize'):Connect(Queue))
	table.insert(Screen.ScrollerConnections, Content:GetPropertyChangedSignal('AbsoluteSize'):Connect(Queue))

	local Layout = Content:FindFirstChild('_FORGELayout')
	if Layout and Layout:IsA('UIListLayout') then
		table.insert(Screen.ScrollerConnections, Layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(Queue))
	end

	Queue()
end

local function ApplyAttributes(Object, Attributes)
	for Name, Value in pairs(Attributes or {}) do
		pcall(function() Object:SetAttribute(Name, Value) end)
	end
end

local function LerpValue(A, B, Alpha)
	Alpha = math.clamp(Alpha, 0, 1)
	local Type = typeof(A)
	if Type ~= typeof(B) then return Alpha >= 1 and B or A end
	if Type == 'number' then return A + (B - A) * Alpha end
	if Type == 'Color3' then return A:Lerp(B, Alpha) end
	if Type == 'Vector2' then return A:Lerp(B, Alpha) end
	if Type == 'Vector3' then return A:Lerp(B, Alpha) end
	if Type == 'CFrame' then return A:Lerp(B, Alpha) end
	if Type == 'UDim' then
		return UDim.new(
			A.Scale + (B.Scale - A.Scale) * Alpha,
			A.Offset + (B.Offset - A.Offset) * Alpha
		)
	end
	if Type == 'UDim2' then
		return UDim2.new(
			A.X.Scale + (B.X.Scale - A.X.Scale) * Alpha,
			A.X.Offset + (B.X.Offset - A.X.Offset) * Alpha,
			A.Y.Scale + (B.Y.Scale - A.Y.Scale) * Alpha,
			A.Y.Offset + (B.Y.Offset - A.Y.Offset) * Alpha
		)
	end
	return Alpha >= 1 and B or A
end

local SemanticAnimationAttributes = {
	PrimaryColor = 'FORGEPrimaryColor',
	SecondaryColor = 'FORGESecondaryColor',
	SatinVisible = 'FORGESatinVisible',
	ShadowVisible = 'FORGEShadowVisible',
	ShadowColor = 'FORGEShadowColor',
	ShadowOpacity = 'FORGEShadowOpacity',
	ShadowBlur = 'FORGEShadowBlur',
	InsetPixels = 'FORGEInsetPixels',
	StrokeThickness = 'FORGEStrokeThickness',
	Value = 'FORGEValue',
	TextSize = 'FORGETextSize',
	TextTransparency = 'FORGETextTransparency',
	LineHeight = 'FORGELineHeight',
	TextStrokeColor = 'FORGETextStrokeColor',
	TextStrokeOpacity = 'FORGETextStrokeOpacity',
	ShadowSize = 'FORGEShadowOffsetX',
	ShadowOffsetX = 'FORGEShadowOffsetX',
	ShadowOffsetY = 'FORGEShadowOffsetY',
	Gap = 'FORGEGap',
	Padding = 'FORGEPadding'
}

local function GetSemanticAnimationValue(Object, Property)
	if not Object then return nil end
	local Attribute = SemanticAnimationAttributes[Property]
	local Value = Attribute and Object:GetAttribute(Attribute) or nil
	if Value ~= nil then return Value end

	if Property == 'TextSize' then
		local Label = Object:FindFirstChild('Label')
		return Label and Label:IsA('TextLabel') and Label.TextSize or nil
	elseif Property == 'TextTransparency' then
		local Label = Object:FindFirstChild('Label')
		return Label and Label:IsA('TextLabel') and Label.TextTransparency or nil
	elseif Property == 'LineHeight' then
		local Label = Object:FindFirstChild('Label')
		return Label and Label:IsA('TextLabel') and Label.LineHeight or nil
	elseif Property == 'StrokeThickness' then
		local Stroke = Object:FindFirstChildWhichIsA('UIStroke', true)
		return Stroke and Stroke.Thickness or nil
	end
	return nil
end

local function SetSemanticAttribute(Object, Property, Value)
	local Attribute = SemanticAnimationAttributes[Property]
	if Attribute then Object:SetAttribute(Attribute, Value) end
	if Property == 'ShadowSize' then Object:SetAttribute('FORGEShadowOffsetY', Value) end
end

local function ScaleAnimationValue(Base, Factor)
	local Type = typeof(Base)
	if Type == 'number' then return Base * Factor end
	if Type == 'Color3' then
		return Color3.new(
			math.clamp(Base.R * Factor, 0, 1),
			math.clamp(Base.G * Factor, 0, 1),
			math.clamp(Base.B * Factor, 0, 1)
		)
	end
	if Type == 'Vector2' then return Base * Factor end
	if Type == 'Vector3' then return Base * Factor end
	if Type == 'UDim' then return UDim.new(Base.Scale * Factor, Base.Offset * Factor) end
	if Type == 'UDim2' then
		return UDim2.new(
			Base.X.Scale * Factor,
			Base.X.Offset * Factor,
			Base.Y.Scale * Factor,
			Base.Y.Offset * Factor
		)
	end
	return nil
end

local function AddAnimationPixels(Base, Delta)
	local Type = typeof(Base)
	if Type == 'number' then return Base + Delta end
	if Type == 'Vector2' then return Base + Vector2.new(Delta, Delta) end
	if Type == 'Vector3' then return Base + Vector3.new(Delta, Delta, Delta) end
	if Type == 'UDim' then return UDim.new(Base.Scale, Base.Offset + Delta) end
	if Type == 'UDim2' then
		return UDim2.new(
			Base.X.Scale,
			Base.X.Offset + Delta,
			Base.Y.Scale,
			Base.Y.Offset + Delta
		)
	end
	return nil
end

local function ResolveAnimationEndpoint(DefaultBase, CurrentBase, Fallback, Expression)
	if not Expression or Expression == '' then return Fallback, true end
	if Expression == 'Current' then return CurrentBase, CurrentBase ~= nil end
	if Expression == 'Default' then return DefaultBase, DefaultBase ~= nil end

	local Percent = tostring(Expression):match('^([%+%-]?%d*%.?%d+)%%$')
	if Percent then
		local Result = ScaleAnimationValue(DefaultBase, 1 + (tonumber(Percent) or 0) / 100)
		return Result, Result ~= nil
	end

	local Pixels = string.lower(tostring(Expression)):match('^([%+%-]?%d*%.?%d+)px$')
	if Pixels then
		local Result = AddAnimationPixels(DefaultBase, tonumber(Pixels) or 0)
		return Result, Result ~= nil
	end
	return nil, false
end

local function NormalizeBarGeometry(Root)
	if not Root or not Root:IsA('GuiObject') then return end

	local Kind = Root:GetAttribute('FORGESimpleKind')
	if Kind ~= 'ProgressBar' and Kind ~= 'Slider' then return end

	local Track = Root:FindFirstChild('Track')
	local Inset = Track and Track:FindFirstChild('Inset')
	if not Inset or not Inset:IsA('GuiObject') then return end

	local Pixels = math.max(0, math.floor((tonumber(Root:GetAttribute('FORGEInsetPixels')) or 2) + .5))
	Inset:SetAttribute('FORGEFixedPixelGeometry', nil)
	Inset.Position = UDim2.fromOffset(Pixels, Pixels)
	Inset.Size = UDim2.new(1, -Pixels * 2, 1, -Pixels * 2)

	local Fill = Root:FindFirstChild('Fill', true)
	if Fill and Fill:IsA('GuiObject') and Fill.Parent ~= Inset then
		Fill.Parent = Inset
	end
end

local function ApplySemanticAnimationValue(Object, Property, Value)
	if not Object or not Object:IsA('GuiObject') then return false end
	SetSemanticAttribute(Object, Property, Value)

	if Property == 'InsetPixels' then
		local Pixels = math.max(0, tonumber(Value) or 0)
		local Kind = Object:GetAttribute('FORGESimpleKind')

		if Kind == 'ProgressBar' or Kind == 'Slider' then
			local Track = Object:FindFirstChild('Track')
			local Inset = Track and Track:FindFirstChild('Inset')

			if Inset and Inset:IsA('GuiObject') then
				Inset.Position = UDim2.fromOffset(Pixels, Pixels)
				Inset.Size = UDim2.new(1, -Pixels * 2, 1, -Pixels * 2)
			end
		else
			local Inset = Object:FindFirstChild('_FORGEInset')
			if Inset and Inset:IsA('GuiObject') then
				Inset.Position = UDim2.fromOffset(Pixels, Pixels)
				Inset.Size = UDim2.new(1, -Pixels * 2, 1, -Pixels * 2)
			end
		end
	elseif Property == 'StrokeThickness' then
		for _, Descendant in ipairs(Object:GetDescendants()) do
			if Descendant:IsA('UIStroke') then Descendant.Thickness = math.max(0, tonumber(Value) or 0) end
		end
	elseif Property == 'PrimaryColor' and typeof(Value) == 'Color3' then
		local Material = Object:FindFirstChild('_FORGEMaterial')
		local Satin = Material and Material:FindFirstChild('_FORGESatin')
		if Satin and Satin:IsA('ImageLabel') then Satin.ImageColor3 = Value end
		local Gradient = Object:FindFirstChild('_FORGEBaseGradient')
		if Gradient and Gradient:IsA('UIGradient') then Gradient.Color = ColorSequence.new(Value) end
		local Kind = Object:GetAttribute('FORGESimpleKind')
		if Kind ~= 'Header' and Kind ~= 'Subtext' and Kind ~= 'Slider' and Kind ~= 'ProgressBar'
			and Object:GetAttribute('FORGELayoutKind') == nil
		then Object.BackgroundColor3 = Value end
		local Fill = Object:FindFirstChild('Fill', true)
		if Fill and Fill:IsA('Frame') then
			Fill.BackgroundColor3 = Value
			local Glow = Fill:FindFirstChild('Glow')
			if Glow and Glow:IsA('UIShadow') then Glow.Color = Value end
		end
	elseif Property == 'SecondaryColor' and typeof(Value) == 'Color3' then
		for _, Descendant in ipairs(Object:GetDescendants()) do
			if Descendant:GetAttribute('FORGEIgnoreSecondary') ~= true then
				if Descendant:IsA('TextLabel') or Descendant:IsA('TextButton') or Descendant:IsA('TextBox') then
					Descendant.TextColor3 = Value
				elseif Descendant:IsA('UIStroke') then
					Descendant.Color = Value
				elseif Descendant:IsA('Frame') and Descendant:GetAttribute('FORGEInheritSecondary') == true then
					Descendant.BackgroundColor3 = Value
				end
			end
		end
		if Object:IsA('ScrollingFrame') then Object.ScrollBarImageColor3 = Value end
	elseif Property == 'ShadowOpacity' then
		local Opacity = math.clamp(tonumber(Value) or 0, 0, 1)
		local Shadow = Object:FindFirstChild('_FORGEShadow')
		if Shadow and Shadow:IsA('UIShadow') then Shadow.Transparency = 1 - Opacity end
		local TextShadow = Object:FindFirstChild('Shadow')
		if TextShadow and TextShadow:IsA('TextLabel') then TextShadow.TextTransparency = 1 - Opacity end
	elseif Property == 'ShadowBlur' then
		local Shadow = Object:FindFirstChild('_FORGEShadow')
		if Shadow and Shadow:IsA('UIShadow') then Shadow.BlurRadius = UDim.new(0, math.max(0, tonumber(Value) or 0)) end
	elseif Property == 'ShadowColor' and typeof(Value) == 'Color3' then
		local Shadow = Object:FindFirstChild('_FORGEShadow')
		if Shadow and Shadow:IsA('UIShadow') then Shadow.Color = Value end
		local TextShadow = Object:FindFirstChild('Shadow')
		if TextShadow and TextShadow:IsA('TextLabel') then TextShadow.TextColor3 = Value end
	elseif Property == 'ShadowOffsetX' or Property == 'ShadowOffsetY' or Property == 'ShadowSize' then
		local Shadow = Object:FindFirstChild('Shadow')
		if Shadow and Shadow:IsA('TextLabel') then
			local X = tonumber(Object:GetAttribute('FORGEShadowOffsetX')) or 1
			local Y = tonumber(Object:GetAttribute('FORGEShadowOffsetY')) or 1
			Shadow.Position = UDim2.fromOffset(X, Y)
		end
	elseif Property == 'Value' then
		local Fill = Object:FindFirstChild('Fill', true)
		if Fill and Fill:IsA('Frame') then Fill.Size = UDim2.new(math.clamp(tonumber(Value) or 0, 0, 1), 0, 1, 0) end
	elseif Property == 'TextSize' or Property == 'TextTransparency' or Property == 'LineHeight'
		or Property == 'TextStrokeColor' or Property == 'TextStrokeOpacity'
	then
		for _, Name in ipairs({'Label', 'Shadow'}) do
			local Text = Object:FindFirstChild(Name)
			if Text and Text:IsA('TextLabel') then
				if Property == 'TextSize' then Text.TextSize = math.max(1, tonumber(Value) or 1)
				elseif Property == 'TextTransparency' and Name == 'Label' then Text.TextTransparency = math.clamp(tonumber(Value) or 0, 0, 1)
				elseif Property == 'LineHeight' then Text.LineHeight = math.max(.1, tonumber(Value) or 1)
				elseif Property == 'TextStrokeColor' and typeof(Value) == 'Color3' then Text.TextStrokeColor3 = Value
				elseif Property == 'TextStrokeOpacity' then Text.TextStrokeTransparency = 1 - math.clamp(tonumber(Value) or 0, 0, 1) end
			end
		end
	elseif Property == 'Gap' then
		local Layout = Object:FindFirstChild('_FORGELayout')
		if Layout and Layout:IsA('UIListLayout') then Layout.Padding = UDim.new(0, math.max(0, tonumber(Value) or 0)) end
	elseif Property == 'Padding' then
		local Padding = Object:FindFirstChild('_FORGEPadding', true)
		if Padding and Padding:IsA('UIPadding') then
			local V = UDim.new(0, math.max(0, tonumber(Value) or 0))
			Padding.PaddingLeft, Padding.PaddingRight, Padding.PaddingTop, Padding.PaddingBottom = V, V, V, V
		end
	end

	return true
end

local function GetAnimationValue(Target, Property, Kind)
	if not Target then return false, nil end
	if Kind == 'Semantic' then
		local Value = GetSemanticAnimationValue(Target, Property)
		return Value ~= nil, Value
	end
	local Success, Value = pcall(function() return Target[Property] end)
	return Success, Value
end

local function SetAnimationValue(Target, Property, Kind, Value)
	if not Target then return false end
	if Kind == 'Semantic' then return ApplySemanticAnimationValue(Target, Property, Value) end
	return pcall(function() Target[Property] = Value end)
end

local function AnimationPropertyKey(Property, Kind)
	return Kind == 'Semantic' and ('@' .. Property) or Property
end

local function Coerce(Object, Property, Value)
	local Success, Current = pcall(function() return Object[Property] end)
	if not Success or Value == nil then return Current end

	local CurrentType, ValueType = typeof(Current), typeof(Value)
	if CurrentType == 'string' and ValueType ~= 'string' then return tostring(Value) end
	if CurrentType == 'number' and ValueType == 'string' then return tonumber(Value) or Current end
	if CurrentType == 'boolean' and ValueType == 'string' then
		local Lower = string.lower(Value)
		if Lower == 'true' or Lower == '1' then return true end
		if Lower == 'false' or Lower == '0' then return false end
		return Current
	end
	return Value
end

local InstanceOwnedComponentProperties = {
	AnchorPoint = true,
	AutomaticSize = true,
	LayoutOrder = true,
	Position = true,
	Rotation = true,
	SelectionOrder = true,
	Size = true,
	SizeConstraint = true,
	Visible = true,
	ZIndex = true
}

local function FindCanonicalChild(Object, DescriptorChildren, Index)
	local ChildData = DescriptorChildren[Index]
	if not ChildData then return nil end

	local DescriptorKeys = SiblingKeys(DescriptorChildren)
	local TargetKey = ChildData.RuntimeKey or DescriptorKeys[Index]
	local Children = Object:GetChildren()
	local ChildKeys = SiblingKeys(Children)

	for ChildIndex, Child in ipairs(Children) do
		if ChildKeys[ChildIndex] == TargetKey and Child.ClassName == ChildData.Class then
			return Child
		end
	end

	return nil
end

local function FindDescriptorChild(Children, TargetChildren, TargetIndex)
	local Target = TargetChildren[TargetIndex]
	if not Target then return nil end

	local TargetKeys = SiblingKeys(TargetChildren)
	local TargetKey = Target.RuntimeKey or TargetKeys[TargetIndex]
	local Keys = SiblingKeys(Children)

	for Index, Child in ipairs(Children or {}) do
		if (Child.RuntimeKey or Keys[Index]) == TargetKey and Child.Class == Target.Class then
			return Child
		end
	end

	return nil
end

local function CaptureDescriptorBaseline(Object, Descriptor)
	if not Object or not Descriptor then return nil end

	local Baseline = {
		Properties = {},
		Children = {}
	}

	for Property in pairs(Descriptor.Properties or {}) do
		local Success, Value = pcall(function() return Object[Property] end)
		if Success then Baseline.Properties[Property] = Value end
	end

	local DescriptorChildren = Descriptor.Children or {}
	for Index, ChildData in ipairs(DescriptorChildren) do
		local Child = FindCanonicalChild(Object, DescriptorChildren, Index)
		if Child then
			Baseline.Children[Index] = CaptureDescriptorBaseline(Child, ChildData)
		end
	end

	return Baseline
end

local function RestoreDescriptorBaseline(Object, Descriptor, Baseline, PreservePersistent)
	if not Object or not Descriptor or not Baseline then return end

	for Property, Value in pairs(Baseline.Properties or {}) do
		pcall(function() Object[Property] = Value end)
	end

	local DescriptorChildren = Descriptor.Children or {}
	for Index, ChildData in ipairs(DescriptorChildren) do
		local PreserveChild = PreservePersistent
			and (ChildData.Name == '_FORGEOutline' or ChildData.Name == '_FORGEShine')

		if not PreserveChild then
			local Child = FindCanonicalChild(Object, DescriptorChildren, Index)
			if Child then
				RestoreDescriptorBaseline(
					Child,
					ChildData,
					Baseline.Children and Baseline.Children[Index],
					PreservePersistent
				)
			end
		end
	end
end

local function ApplyDescriptorDelta(Object, BaseDescriptor, TargetDescriptor, PreservePersistent, PreserveInstanceLayout)
	if not Object or not TargetDescriptor then return end

	local BaseProperties = BaseDescriptor and BaseDescriptor.Properties or {}
	for Property, Value in pairs(TargetDescriptor.Properties or {}) do
		local Changed = BaseDescriptor == nil or BaseProperties[Property] ~= Value
		if Changed and (not PreserveInstanceLayout or not InstanceOwnedComponentProperties[Property]) then
			pcall(function() Object[Property] = Value end)
		end
	end

	local TargetChildren = TargetDescriptor.Children or {}
	local BaseChildren = BaseDescriptor and BaseDescriptor.Children or {}

	for Index, ChildData in ipairs(TargetChildren) do
		local PreserveChild = PreservePersistent
			and (ChildData.Name == '_FORGEOutline' or ChildData.Name == '_FORGEShine')

		if not PreserveChild then
			local Child = FindCanonicalChild(Object, TargetChildren, Index)
			if Child then
				ApplyDescriptorDelta(
					Child,
					FindDescriptorChild(BaseChildren, TargetChildren, Index),
					ChildData,
					PreservePersistent,
					false
				)
			end
		end
	end
end

local function NewStyleSet(Name, Pack)
	local Set = StyleSet.new(Name)
	for ResourceName, Value in pairs(Pack.Color or {}) do Set:SetResource('Color.' .. ResourceName, Value) end
	for ResourceName, Value in pairs(Pack.Metric or {}) do Set:SetResource('Metric.' .. ResourceName, Value) end
	if Pack.Satin then Set:SetResource('Satin', Pack.Satin) end
	if Pack.FontAsset then Set:SetResource('FontAsset', Pack.FontAsset) end

	for SurfaceName, Surface in pairs(Pack.Surfaces or {}) do
		Set:SetResource('Surface.' .. SurfaceName, Surface)
		Set:Set('Surface.' .. SurfaceName, {
			BackgroundColor3 = Surface.Base
		})
	end

	for RarityName, Rarity in pairs(Pack.Rarities or {}) do
		Set:SetResource('Rarity.' .. RarityName, Rarity)
		Set:Set('Rarity.' .. RarityName, {
			BackgroundColor3 = Rarity.Color
		})
	end

	return Set
end

function ProjectRuntime.new(UI, Data, Options)
	assert(type(UI) == 'table' and UI.Version == '1.0.0', 'ProjectRuntime requires FORGE.UI 1.0.0.')
	ValidateProjectData(UI, Data)

	local self = setmetatable({}, ProjectRuntime)
	self.UI = UI
	self.Data = Data
	self.Options = Options or {}
	self.Package = self.Options.Package
	self.TemplateRoot = self.Package and self.Package:FindFirstChild('Templates')
	self.ScreenTemplateRoot = self.TemplateRoot and self.TemplateRoot:FindFirstChild('Screens')
	self.DataSource = self.Options.Data or {}
	self.Screens = {}
	self.StyleSets = {}
	self.StyleSetsBuilt = false
	self.ComponentControllers = {}
	self.CreatedComponents = {}
	self.ActiveAnimations = {}
	self.ActiveSemanticAnimations = {}
	self.ActiveAnimationOwners = {}
	self.AnimationBaselines = {}
	self.AnimationTriggersByPath = {}
	self.AnimationTriggersByKind = {}
	self.Stack = {}
	self.CurrentScreen = nil
	self.Transitioning = false
	self.Destroyed = false
	self.Layer = self.Options.Layer or 'Game'
	self.ZOrder = self.Options.ZOrder or 1
	self.BuildNodeCount = 0
	self.BuildYieldEvery = math.max(50, tonumber(self.Options.BuildYieldEvery) or 250)
	self:_IndexAnimationTriggers()
	return self
end

function ProjectRuntime:_BuildStyleSets()
	if self.StyleSetsBuilt then return end
	self.StyleSetsBuilt = true
	table.clear(self.StyleSets)
	for Name, Pack in pairs(self.Data.Styles and self.Data.Styles.Packs or {}) do
		self.StyleSets[Name] = NewStyleSet(Name, Pack)
	end
end

function ProjectRuntime:GetStyleSet(Name)
	self:_BuildStyleSets()
	return self.StyleSets[Name or self.Data.ActiveStylePack]
end

function ProjectRuntime:RefreshBindings(ScreenName)
	local Seen = {}
	local function RefreshScreen(Screen)
		if not Screen or Seen[Screen] then return end
		Seen[Screen] = true
		for _, CurrentWidget in pairs(Screen.Widgets or {}) do
			if CurrentWidget.SynchronizeProperties then CurrentWidget:SynchronizeProperties() end
		end
	end

	if ScreenName then
		RefreshScreen(self.Screens[ScreenName])
	else
		for _, Screen in pairs(self.Screens) do RefreshScreen(Screen) end
		for _, Controller in pairs(self.ComponentControllers) do
			if type(Controller) == 'table' then RefreshScreen(Controller.Screen) end
		end
	end
	return self
end

function ProjectRuntime:SetData(Data)
	self.DataSource = Data or {}
	return self:RefreshBindings()
end

function ProjectRuntime:GetData()
	return self.DataSource
end

function ProjectRuntime:_IndexAnimationTriggers()
	table.clear(self.AnimationTriggersByPath)
	table.clear(self.AnimationTriggersByKind)

	for AnimationName, Definition in pairs(self.Data.Animations or {}) do
		local Trigger = Definition.Trigger or 'Manual'
		local EventName = Trigger == 'Hover' and 'MouseEnter'
			or Trigger == 'HoverEnd' and 'MouseLeave'
			or Trigger == 'Press' and 'PointerDown'
			or Trigger == 'Release' and 'PointerUp'
			or Trigger == 'Click' and 'Clicked'

		if EventName then
			local Entry = {
				Name = AnimationName,
				Definition = Definition,
				Event = EventName
			}

			if Definition.PresetKind then
				local Bucket = self.AnimationTriggersByKind[Definition.PresetKind]
				if not Bucket then
					Bucket = {}
					self.AnimationTriggersByKind[Definition.PresetKind] = Bucket
				end
				table.insert(Bucket, Entry)
			elseif Definition.OwnerPath then
				local Relative = Definition.TriggerTargetPath or 'Root'
				local TriggerPath = Definition.OwnerPath
				if Relative ~= '' and Relative ~= 'Root' then TriggerPath ..= '/' .. Relative end

				local Bucket = self.AnimationTriggersByPath[TriggerPath]
				if not Bucket then
					Bucket = {}
					self.AnimationTriggersByPath[TriggerPath] = Bucket
				end
				table.insert(Bucket, Entry)
			end
		end
	end
end

function ProjectRuntime:_BuildNode(Descriptor, Screen, ParentWidget, ParentObject, Path)
	self.BuildNodeCount += 1
	if RunService:IsClient() and self.BuildNodeCount % self.BuildYieldEvery == 0 then
		RunService.Heartbeat:Wait()
	end

	local Success, Object = pcall(Instance.new, Descriptor.Class)
	if not Success or not Object then return nil end

	Object.Name = Descriptor.Name or Descriptor.Class
	ApplyProperties(Object, Descriptor.Properties)
	ApplyAttributes(Object, Descriptor.Attributes)
	Object.Parent = ParentObject

	local CurrentPath = Path or Object.Name
	Screen.Instances[CurrentPath] = Object

	local CurrentWidget
	local StyleInternal = (Descriptor.Attributes or {}).FORGEStyleInternal == true
	if Object:IsA('GuiObject') and not StyleInternal then
		CurrentWidget = Widget.new(Object)
		CurrentWidget:SetName(Object.Name)
		Screen.Widgets[CurrentPath] = CurrentWidget
		Screen.ObjectWidgets[Object] = CurrentWidget

		local ObjectKind = Object:GetAttribute('FORGESimpleKind') or Object:GetAttribute('FORGELayoutKind')
		if ObjectKind then
			Screen.KindWidgets[ObjectKind] = Screen.KindWidgets[ObjectKind] or {}
			table.insert(Screen.KindWidgets[ObjectKind], CurrentWidget)
		end

		local AuthoredInteractable = Descriptor.Properties and Descriptor.Properties.Interactable
		if AuthoredInteractable == false
			or not Object:IsA('GuiButton') and not Object:IsA('TextBox') and not Object:IsA('ScrollingFrame') then
			Object.Interactable = false
		end

		if ParentWidget then
			CurrentWidget.Parent = ParentWidget
			table.insert(ParentWidget.Children, CurrentWidget)
		end

		self:_BindWidget(Screen, CurrentPath, CurrentWidget, Descriptor)
	end

	local Children = Descriptor.Children or {}
	local Keys = SiblingKeys(Children)

	for Index, ChildData in ipairs(Children) do
		local ChildPath = CurrentPath .. '/' .. Keys[Index]
		self:_BuildNode(ChildData, Screen, CurrentWidget or ParentWidget, Object, ChildPath)
	end

	NormalizeBarGeometry(Object)

	if CurrentWidget and (Descriptor.Attributes or {}).FORGEComponentName then
		table.insert(Screen.PendingComponents, {
			Widget = CurrentWidget,
			Descriptor = Descriptor,
			Path = CurrentPath
		})
	end

	return CurrentWidget
end

function ProjectRuntime:_AttachNativeNode(Object, Screen, ParentWidget, Path)
	if not Object then return nil end

	self.BuildNodeCount += 1
	if RunService:IsClient() and self.BuildNodeCount % self.BuildYieldEvery == 0 then
		RunService.Heartbeat:Wait()
	end

	local CurrentPath = Path or Object.Name
	Screen.Instances[CurrentPath] = Object

	local CurrentWidget
	local StyleInternal = Object:GetAttribute('FORGEStyleInternal') == true
		or Object:GetAttribute('FORGEHierarchyInternal') == true

	if Object:IsA('GuiObject') and not StyleInternal then
		CurrentWidget = Widget.new(Object)
		CurrentWidget:SetName(Object.Name)
		Screen.Widgets[CurrentPath] = CurrentWidget
		Screen.ObjectWidgets[Object] = CurrentWidget

		local ObjectKind = Object:GetAttribute('FORGESimpleKind') or Object:GetAttribute('FORGELayoutKind')
		if ObjectKind then
			Screen.KindWidgets[ObjectKind] = Screen.KindWidgets[ObjectKind] or {}
			table.insert(Screen.KindWidgets[ObjectKind], CurrentWidget)
		end

		if not Object:IsA('GuiButton') and not Object:IsA('TextBox') and not Object:IsA('ScrollingFrame') then
			Object.Interactable = false
		end

		if ParentWidget then
			CurrentWidget.Parent = ParentWidget
			table.insert(ParentWidget.Children, CurrentWidget)
		end

		self:_BindWidget(Screen, CurrentPath, CurrentWidget, {
			Attributes = Object:GetAttributes(),
			Properties = {Interactable = Object.Interactable}
		})
	end

	local Children = Object:GetChildren()
	local Keys = SiblingKeys(Children)
	for Index, Child in ipairs(Children) do
		local ChildPath = CurrentPath .. '/' .. Keys[Index]
		self:_AttachNativeNode(Child, Screen, CurrentWidget or ParentWidget, ChildPath)
	end

	NormalizeBarGeometry(Object)

	if CurrentWidget and Object:GetAttribute('FORGEComponentName') then
		table.insert(Screen.PendingComponents, {
			Widget = CurrentWidget,
			Descriptor = nil,
			Path = CurrentPath
		})
	end

	return CurrentWidget
end

function ProjectRuntime:_BindWidget(Screen, Path, CurrentWidget, Descriptor)
	local Attributes = Descriptor.Attributes or {}

	for Name, DataPath in pairs(Attributes) do
		local Prefix = 'FORGEBinding_'
		if string.sub(Name, 1, #Prefix) == Prefix then
			local Property = string.sub(Name, #Prefix + 1)
			local Object = CurrentWidget.Object
			CurrentWidget:Bind(Property, function()
				return Coerce(Object, Property, ResolveData(self.DataSource, DataPath))
			end)
		end
	end

	local ObjectKind = CurrentWidget.Object:GetAttribute('FORGESimpleKind')
		or CurrentWidget.Object:GetAttribute('FORGELayoutKind')
	local Entries = {}

	for _, Entry in ipairs(self.AnimationTriggersByPath[Path] or {}) do
		table.insert(Entries, Entry)
	end
	for _, Entry in ipairs(self.AnimationTriggersByKind[ObjectKind] or {}) do
		table.insert(Entries, Entry)
	end

	for _, Entry in ipairs(Entries) do
		pcall(function() CurrentWidget.Object.Interactable = true end)
		CurrentWidget.Object.Active = true

		if Entry.Definition.PresetKind then
			CurrentWidget:On(Entry.Event, function()
				self:PlayAnimation(Entry.Name, CurrentWidget, false)
			end)
		else
			local OwnerPath = Entry.Definition.OwnerPath
			CurrentWidget:On(Entry.Event, function()
				local Owner = OwnerPath and Screen.Widgets[OwnerPath]
				if Owner then self:PlayAnimation(Entry.Name, Owner, false) end
			end)
		end
	end

	local ActionType = Attributes.FORGEActionType
	if ActionType and ActionType ~= 'None' then
		local Action = {
			Type = ActionType,
			Target = Attributes.FORGEActionTarget or '',
			Transition = Attributes.FORGEActionTransition or 'None',
			Duration = tonumber(Attributes.FORGEActionDuration) or .2
		}

		CurrentWidget:On('Clicked', function(Event)
			if self.Destroyed then return end
			task.spawn(function()
				self:_ExecuteAction(Screen.Name, Path, Action)
			end)
			if Event then Event:Handle() end
			return true
		end)
	end
end

function ProjectRuntime:_CaptureAnimationBaseline(Owner, Target, Property, Kind)
	if not Owner or not Target then return nil end
	local Key = AnimationPropertyKey(Property, Kind)
	self.AnimationBaselines[Owner] = self.AnimationBaselines[Owner] or {}
	self.AnimationBaselines[Owner][Target] = self.AnimationBaselines[Owner][Target] or {}

	local Existing = self.AnimationBaselines[Owner][Target][Key]
	if Existing ~= nil then return Existing end

	local Success, Value = GetAnimationValue(Target, Property, Kind)
	if Success then self.AnimationBaselines[Owner][Target][Key] = Value end
	return Success and Value or nil
end

function ProjectRuntime:_GetAnimationBaseline(Owner, Target, Property, Kind)
	local Key = AnimationPropertyKey(Property, Kind)
	local OwnerState = self.AnimationBaselines[Owner]
	local TargetState = OwnerState and OwnerState[Target]
	local Value = TargetState and TargetState[Key]
	if Value ~= nil then return Value end
	return self:_CaptureAnimationBaseline(Owner, Target, Property, Kind)
end

function ProjectRuntime:_CaptureAnimationDefinitionBaselines(Definition, Owner, Seen)
	if not Definition or not Owner or not Owner.Object then return end
	Seen = Seen or {}
	local Key = Definition.Name or tostring(Definition)
	if Seen[Key] then return end
	Seen[Key] = true

	if Definition.InheritEndFrom then
		self:_CaptureAnimationDefinitionBaselines(
			self.Data.Animations and self.Data.Animations[Definition.InheritEndFrom],
			Owner,
			Seen
		)
	end

	for _, Track in ipairs(Definition.Tracks or {}) do
		local Target = ResolveRelative(Owner.Object, Track.TargetPath)
		if Target then self:_CaptureAnimationBaseline(Owner, Target, Track.Property, Track.PropertyKind or 'Native') end
	end
end

function ProjectRuntime:_CaptureScreenAnimationBaselines(Screen)
	if not Screen then return end

	for _, Definition in pairs(self.Data.Animations or {}) do
		if Definition.PresetKind then
			for _, Owner in ipairs(Screen.KindWidgets[Definition.PresetKind] or {}) do
				self:_CaptureAnimationDefinitionBaselines(Definition, Owner)
			end
		elseif Definition.OwnerPath then
			local Owner = Screen.Widgets[Definition.OwnerPath]
			if Owner then self:_CaptureAnimationDefinitionBaselines(Definition, Owner) end
		end
	end
end

function ProjectRuntime:_RestoreAnimationOwnerBaseline(Owner)
	local OwnerState = self.AnimationBaselines[Owner]
	if not OwnerState then return end

	for Target, Properties in pairs(OwnerState) do
		if Target and Target.Parent then
			for Key, Value in pairs(Properties) do
				local Semantic = string.sub(Key, 1, 1) == '@'
				SetAnimationValue(
					Target,
					Semantic and string.sub(Key, 2) or Key,
					Semantic and 'Semantic' or 'Native',
					Value
				)
			end
		end
	end
end

function ProjectRuntime:_ApplyAnimationEndPose(Name, Owner, Seen)
	if not Name or not Owner or not Owner.Object then return false end
	Seen = Seen or {}
	if Seen[Name] then return false end
	Seen[Name] = true

	local Definition = self.Data.Animations and self.Data.Animations[Name]
	if not Definition then return false end
	if Definition.InheritEndFrom then self:_ApplyAnimationEndPose(Definition.InheritEndFrom, Owner, Seen) end

	for _, Track in ipairs(Definition.Tracks or {}) do
		local Target = ResolveRelative(Owner.Object, Track.TargetPath)
		if Target then
			local Kind = Track.PropertyKind or 'Native'
			local DefaultBase = self:_GetAnimationBaseline(Owner, Target, Track.Property, Kind)
			local Success, CurrentBase = GetAnimationValue(Target, Track.Property, Kind)
			if DefaultBase ~= nil and Success then
				local Value, OK = ResolveAnimationEndpoint(DefaultBase, CurrentBase, Track.To, Track.ToExpression)
				if OK then SetAnimationValue(Target, Track.Property, Kind, Value) end
			end
		end
	end
	return true
end

function ProjectRuntime:_CancelOwnerAnimation(Owner)
	local Active = self.ActiveAnimationOwners[Owner]
	if not Active then return end
	self.ActiveAnimationOwners[Owner] = nil

	if Active.Result then
		self.ActiveAnimations[Active.Result] = nil
		Active.Result:Destroy()
	end
	if Active.Dynamic then
		Active.Dynamic.Cancelled = true
		self.ActiveSemanticAnimations[Active.Dynamic] = nil
	end
end

function ProjectRuntime:_UpdateScreenViewport(Screen)
	if not Screen or not Screen.Reference or not Screen.CanvasObject or not Screen.CanvasScale then return end

	local Viewport = Screen.RootWidget and Screen.RootWidget.Object and Screen.RootWidget.Object.AbsoluteSize
	if not Viewport or Viewport.X <= 0 or Viewport.Y <= 0 then return end

	Responsive.Apply(
		Screen.CanvasObject,
		Screen.CanvasScale,
		Viewport,
		Screen.Reference,
		Screen.Reference.ScaleMode
	)
end

function ProjectRuntime:_BuildScreen(Name)
	if self.Screens[Name] then return self.Screens[Name] end

	local TemplateName = self.Data.ScreenTemplates and self.Data.ScreenTemplates[Name]
	local Template = TemplateName and self.ScreenTemplateRoot and self.ScreenTemplateRoot:FindFirstChild(TemplateName)
	local Definition
	if not Template then Definition = self.Data.Screens and self.Data.Screens[Name] end
	if not Template and not Definition then return nil end

	local User = UserWidget.new('Screen_' .. Name)
	local RootObject = Instance.new('CanvasGroup')
	RootObject.Name = 'Root'
	RootObject.BackgroundTransparency = 1
	RootObject.BorderSizePixel = 0
	RootObject.Size = UDim2.fromScale(1, 1)

	local RootWidget = Widget.new(RootObject)
	RootWidget:SetName('Root')

	local Reference = Template and ReferenceViewportFromTemplate(Template) or ReferenceViewport(Definition)
	local ParentObject = RootObject
	local CanvasObject
	local CanvasScale

	if Reference then
		CanvasObject = Instance.new('CanvasGroup')
		CanvasObject.Name = '_FORGEResponsiveCanvas'
		CanvasObject.BackgroundTransparency = 1
		CanvasObject.BorderSizePixel = 0
		CanvasObject.Position = UDim2.fromOffset(0, 0)
		CanvasObject.Size = UDim2.fromOffset(Reference.Width, Reference.Height)
		CanvasObject.ClipsDescendants = false
		CanvasObject.Parent = RootObject

		CanvasScale = Instance.new('UIScale')
		CanvasScale.Name = '_FORGEResponsiveScale'
		CanvasScale.Scale = 1
		CanvasScale.Parent = CanvasObject

		ParentObject = CanvasObject
	end

	local Screen = {
		Name = Name,
		UserWidget = User,
		RootWidget = RootWidget,
		Reference = Reference,
		CanvasObject = CanvasObject,
		CanvasScale = CanvasScale,
		ViewportConnection = nil,
		ScrollerConnections = {},
		Instances = {},
		Widgets = {},
		ObjectWidgets = {},
		KindWidgets = {},
		PendingComponents = {}
	}

	Screen.Instances.Root = RootObject
	Screen.Widgets.Root = RootWidget
	Screen.ObjectWidgets[RootObject] = RootWidget
	self.BuildNodeCount = 0

	if Template then
		local TemplateRoots = Template:GetChildren()
		local Keys = SiblingKeys(TemplateRoots)

		for Index, TemplateRoot in ipairs(TemplateRoots) do
			local Root = TemplateRoot:Clone()
			Root.Parent = ParentObject
			self:_AttachNativeNode(Root, Screen, RootWidget, Keys[Index])
		end
	else
		local Roots = Definition.Roots or {}
		local Keys = SiblingKeys(Roots)

		for Index, RootData in ipairs(Roots) do
			self:_BuildNode(
				RootData,
				Screen,
				RootWidget,
				ParentObject,
				Keys[Index]
			)
		end
	end

	for _, Object in pairs(Screen.Instances) do
		if Object:IsA('GuiObject') and Object:GetAttribute('FORGESimpleKind') == 'Scroller' then
			BindRuntimeScroller(Screen, Object)
		end
	end

	User:SetRootWidget(RootWidget)
	self.Screens[Name] = Screen

	if Reference then
		Screen.ViewportConnection = RootObject:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()
			self:_UpdateScreenViewport(Screen)
		end)
	end

	for _, Entry in ipairs(Screen.PendingComponents) do
		self:_AttachComponentState(Screen, Entry.Widget, Entry.Descriptor, Entry.Path)
	end
	table.clear(Screen.PendingComponents)
	self:_CaptureScreenAnimationBaselines(Screen)
	return Screen
end

function ProjectRuntime:_AnimateShine(Controller, Interaction)
	local Root = Controller.Widget.Object
	local Shine = Root and Root:FindFirstChild('_FORGEShine', true)
	if not Shine or not Shine:IsA('GuiObject') then return end

	local Persistent = Shine:GetAttribute('FORGEPersistentShine') == true
	local Target = 1
	if Controller.Disabled then
		Target = Persistent and .9 or 1
	elseif Interaction == 'Pressed' then
		Target = Persistent and .62 or .64
	elseif Interaction == 'Hover' then
		Target = Persistent and .72 or .78
	elseif Persistent then
		Target = .82
	end

	Shine.Active = false
	pcall(function() Shine.Interactable = false end)
	Shine.BackgroundColor3 = Color3.new(1, 1, 1)

	if Controller.ShineTween then Controller.ShineTween:Cancel() end
	local Duration = Interaction == 'Pressed' and .08 or Interaction == 'Hover' and .12 or .18
	Controller.ShineTween = TweenService:Create(
		Shine,
		TweenInfo.new(Duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{BackgroundTransparency = Target}
	)
	Controller.ShineTween:Play()
end

function ProjectRuntime:_RefreshComponentState(Controller, Interaction)
	if not Controller.State then
		self:_AnimateShine(Controller, Interaction)
		return
	end

	local BaseState = Controller.BaseState or 'Default'
	local StateName = Controller.Disabled and 'Disabled'
		or Controller.Pressed and 'Pressed'
		or Controller.Selected and 'Selected'
		or Controller.Hovered and 'Hover'
		or BaseState

	if StateName ~= 'Default' and not Controller.Definition.Variants[StateName] then
		StateName = Controller.Selected and Controller.Definition.Variants.Selected and 'Selected' or BaseState
	end
	if StateName ~= 'Default' and not Controller.Definition.Variants[StateName] then StateName = 'Default' end

	Controller.State:Set(StateName)
	self:_AnimateShine(Controller, Interaction)
end

function ProjectRuntime:_AttachComponentState(Screen, CurrentWidget, Descriptor, Path)
	local Attributes = Descriptor and Descriptor.Attributes or CurrentWidget.Object:GetAttributes()
	local ComponentName = Attributes.FORGEComponentName
	local Definition = self.Data.Components and self.Data.Components[ComponentName]
	if not Definition or not Definition.Source then return end

	local Variants = Definition.Variants or {}
	local HasVariants = next(Variants) ~= nil
	local InitialVariant = Attributes.FORGEComponentVariant or 'Default'
	local IsRuntimeState = InitialVariant == 'Hover'
		or InitialVariant == 'Pressed'
		or InitialVariant == 'Selected'
		or InitialVariant == 'Disabled'
	local PersistentShine = CurrentWidget.Object:FindFirstChild('_FORGEShine', true)
	local HasInteractiveShine = PersistentShine ~= nil and CurrentWidget.Object:IsA('GuiButton')
	local BaselineDescriptor = HasVariants and (
		Descriptor
		or (InitialVariant ~= 'Default' and Variants[InitialVariant])
		or Definition.Source
	) or nil

	local Controller = {
		Widget = CurrentWidget,
		Screen = Screen,
		Path = Path,
		Name = ComponentName,
		Definition = Definition,
		BaseState = IsRuntimeState and 'Default' or InitialVariant,
		State = HasVariants and State.new(InitialVariant) or nil,
		Selected = InitialVariant == 'Selected',
		Disabled = InitialVariant == 'Disabled' or CurrentWidget.Enabled == false,
		Hovered = false,
		Pressed = false,
		PersistentSurface = PersistentShine and PersistentShine:GetAttribute('FORGEPersistentShine') == true or false,
		BaselineDescriptor = BaselineDescriptor,
		Baseline = HasVariants and CaptureDescriptorBaseline(CurrentWidget.Object, BaselineDescriptor) or nil,
		Connections = {},
		ShineTween = nil
	}

	if Controller.State then
		local function ApplyState(StateName)
			RestoreDescriptorBaseline(
				CurrentWidget.Object,
				Controller.BaselineDescriptor,
				Controller.Baseline,
				Controller.PersistentSurface
			)

			if StateName == Controller.BaseState then return end
			if StateName == 'Default' and Controller.BaseState == 'Default' then return end

			local Variant = Variants[StateName]
			if not Variant then return end

			ApplyDescriptorDelta(
				CurrentWidget.Object,
				Definition.Source,
				Variant,
				Controller.PersistentSurface,
				true
			)
		end

		table.insert(Controller.Connections, Controller.State:Subscribe(function(StateName)
			ApplyState(StateName)
		end, false))
	end

	if HasVariants or HasInteractiveShine then
		CurrentWidget:On('MouseEnter', function()
			Controller.Hovered = true
			self:_RefreshComponentState(Controller, 'Hover')
		end)

		CurrentWidget:On('MouseLeave', function()
			Controller.Hovered = false
			Controller.Pressed = false
			self:_RefreshComponentState(Controller, 'Base')
		end)

		CurrentWidget:On('PointerDown', function()
			if Controller.Disabled then return end
			Controller.Pressed = true
			self:_RefreshComponentState(Controller, 'Pressed')
		end)

		CurrentWidget:On('PointerUp', function()
			Controller.Pressed = false
			self:_RefreshComponentState(Controller, Controller.Hovered and 'Hover' or 'Base')
		end)

		table.insert(Controller.Connections, CurrentWidget.OnEnabledChanged:Connect(function(Enabled)
			Controller.Disabled = not Enabled
			Controller.Pressed = false
			self:_RefreshComponentState(Controller, 'Base')
		end))
	end

	self.ComponentControllers[CurrentWidget] = Controller
	self.ComponentControllers[CurrentWidget.Object] = Controller
	if Controller.Disabled then CurrentWidget:SetEnabled(false) end
	if HasInteractiveShine then self:_AnimateShine(Controller, 'Base') end
	return Controller
end

function ProjectRuntime:SetComponentSelected(Target, Selected)
	local Controller = self:_GetComponentController(Target)
	if not Controller then return false end

	Controller.Selected = Selected == true
	Controller.Pressed = false
	self:_RefreshComponentState(Controller, Controller.Hovered and 'Hover' or 'Base')
	return true
end

function ProjectRuntime:SetComponentEnabled(Target, Enabled)
	local Controller = self:_GetComponentController(Target)
	if not Controller then return false end
	Controller.Widget:SetEnabled(Enabled == true)
	return true
end

function ProjectRuntime:GetComponentState(Target)
	local Controller = self:_GetComponentController(Target)
	if not Controller then return nil end
	return Controller.State and Controller.State:Get() or Controller.BaseState
end

function ProjectRuntime:_SetObjectVisible(ScreenName, Path, Mode)
	local Screen = self.Screens[ScreenName] or self:_BuildScreen(ScreenName)
	local Object = Screen and Screen.Instances[Path]
	if not Object or not Object:IsA('GuiObject') then return false end

	if Mode == 'Show' then Object.Visible = true
	elseif Mode == 'Hide' then Object.Visible = false
	elseif Mode == 'Toggle' then Object.Visible = not Object.Visible end
	return true
end

function ProjectRuntime:_ExecuteAction(ScreenName, SourcePath, Action)
	if Action.Type == 'OpenScreen' then
		self:OpenScreen(Action.Target, Action.Transition, Action.Duration, true)
	elseif Action.Type == 'Back' then
		self:Back(Action.Transition, Action.Duration)
	elseif Action.Type == 'Show' or Action.Type == 'Hide' or Action.Type == 'Toggle' then
		self:_SetObjectVisible(ScreenName, Action.Target, Action.Type)
	end
end

function ProjectRuntime:_Tween(Object, Duration, Properties)
	local Tween = TweenService:Create(
		Object,
		TweenInfo.new(math.max(Duration, 0), Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		Properties
	)
	Tween:Play()
	Tween.Completed:Wait()
	return Tween
end

function ProjectRuntime:_MountScreen(Screen)
	self.UI.AddToViewport(Screen.UserWidget, self.ZOrder, self.Layer)
	self:_UpdateScreenViewport(Screen)
	return Screen
end

function ProjectRuntime:_UnmountScreen(Screen)
	if Screen then self.UI.RemoveFromViewport(Screen.UserWidget) end
end

function ProjectRuntime:OpenScreen(Name, Transition, Duration, PushCurrent)
	if self.Destroyed or self.Transitioning then return false end
	local Next = self:_BuildScreen(Name)
	if not Next then return false end

	local CurrentName = self.CurrentScreen
	if CurrentName == Name then return true end
	if PushCurrent and CurrentName then table.insert(self.Stack, CurrentName) end

	local Current = CurrentName and self.Screens[CurrentName] or nil
	Transition = Transition or 'None'
	Duration = math.max(tonumber(Duration) or .2, 0)
	self.Transitioning = true

	if not Current then
		self:_MountScreen(Next)
		self.CurrentScreen = Name
		self.Transitioning = false
		return true
	end

	local Half = Duration / 2
	if Transition == 'Fade' and Duration > 0 then
		self:_Tween(Current.RootWidget.Object, Half, {GroupTransparency = 1})
		self:_UnmountScreen(Current)
		Next.RootWidget.Object.GroupTransparency = 1
		self:_MountScreen(Next)
		self:_Tween(Next.RootWidget.Object, Half, {GroupTransparency = 0})
	elseif (Transition == 'SlideLeft' or Transition == 'SlideRight') and Duration > 0 then
		local Direction = Transition == 'SlideLeft' and -1 or 1
		self:_Tween(Current.UserWidget.Object, Half, {Position = UDim2.fromScale(Direction, 0)})
		self:_UnmountScreen(Current)
		Next.UserWidget.Object.Position = UDim2.fromScale(-Direction, 0)
		self:_MountScreen(Next)
		self:_Tween(Next.UserWidget.Object, Half, {Position = UDim2.fromScale(0, 0)})
	elseif Transition == 'Scale' and Duration > 0 then
		local Scale = Current.RootWidget.Object:FindFirstChild('_FORGERuntimeScale') or Instance.new('UIScale')
		Scale.Name = '_FORGERuntimeScale'
		Scale.Parent = Current.RootWidget.Object
		self:_Tween(Scale, Half, {Scale = .9})
		Current.RootWidget.Object.GroupTransparency = 1
		self:_UnmountScreen(Current)

		local NextScale = Next.RootWidget.Object:FindFirstChild('_FORGERuntimeScale') or Instance.new('UIScale')
		NextScale.Name = '_FORGERuntimeScale'
		NextScale.Scale = .9
		NextScale.Parent = Next.RootWidget.Object
		Next.RootWidget.Object.GroupTransparency = 1
		self:_MountScreen(Next)
		self:_Tween(Next.RootWidget.Object, Half, {GroupTransparency = 0})
		self:_Tween(NextScale, Half, {Scale = 1})
	else
		self:_UnmountScreen(Current)
		self:_MountScreen(Next)
	end

	Current.RootWidget.Object.GroupTransparency = 0
	Current.UserWidget.Object.Position = UDim2.fromScale(0, 0)
	local CurrentScale = Current.RootWidget.Object:FindFirstChild('_FORGERuntimeScale')
	if CurrentScale and CurrentScale:IsA('UIScale') then CurrentScale.Scale = 1 end

	Next.RootWidget.Object.GroupTransparency = 0
	Next.UserWidget.Object.Position = UDim2.fromScale(0, 0)
	local NextScale = Next.RootWidget.Object:FindFirstChild('_FORGERuntimeScale')
	if NextScale and NextScale:IsA('UIScale') then NextScale.Scale = 1 end

	self.CurrentScreen = Name
	self.Transitioning = false
	return true
end

function ProjectRuntime:Back(Transition, Duration)
	local Target = table.remove(self.Stack)
	if not Target then return false end
	return self:OpenScreen(Target, Transition, Duration, false)
end

function ProjectRuntime:Mount()
	local Start = self.Data.StartScreen
	return self:OpenScreen(Start, 'None', 0, false)
end

function ProjectRuntime:GetCurrentScreen()
	return self.CurrentScreen
end

function ProjectRuntime:GetWidget(Path, ScreenName)
	local Screen = self.Screens[ScreenName or self.CurrentScreen]
	return Screen and Screen.Widgets[Path] or nil
end

function ProjectRuntime:GetObject(Path, ScreenName)
	local Screen = self.Screens[ScreenName or self.CurrentScreen]
	return Screen and Screen.Instances[Path] or nil
end

function ProjectRuntime:CreateComponent(Name, Variant, Slots)
	local Definition = self.Data.Components and self.Data.Components[Name]
	if not Definition or not Definition.Source then return nil end
	Variant = Variant or 'Default'
	local Descriptor = Variant ~= 'Default' and Definition.Variants and Definition.Variants[Variant] or Definition.Source
	if not Descriptor then
		Variant = 'Default'
		Descriptor = Definition.Source
	end

	local Screen = {
		Name = '__Component',
		Instances = {},
		Widgets = {},
		ObjectWidgets = {},
		KindWidgets = {},
		PendingComponents = {}
	}
	local RootPath = Descriptor.RuntimeKey or tostring(Descriptor.Name)
	local RootWidget = self:_BuildNode(Descriptor, Screen, nil, nil, RootPath)
	if not RootWidget then return nil end

	local RuntimeComponent = ProjectComponent.new(Name)
	local Properties = Descriptor.Properties or {}
	RuntimeComponent.Object.Interactable = false
	RuntimeComponent.Object.Position = Properties.Position or RuntimeComponent.Object.Position
	RuntimeComponent.Object.AnchorPoint = Properties.AnchorPoint or RuntimeComponent.Object.AnchorPoint
	RuntimeComponent.Object.Rotation = Properties.Rotation or RuntimeComponent.Object.Rotation
	RuntimeComponent.Object.Size = Properties.Size or RuntimeComponent.Object.Size
	RuntimeComponent:SetRootWidget(RootWidget)
	RootWidget.Object.Position = UDim2.fromScale(0, 0)
	RootWidget.Object.AnchorPoint = Vector2.zero
	RootWidget.Object.Rotation = 0

	local Controller = self:_AttachComponentState(Screen, RootWidget, {
		Attributes = {
			FORGEComponentName = Name,
			FORGEComponentVariant = Variant
		}
	}, RootPath)
	table.clear(Screen.PendingComponents)

	if Controller then self.ComponentControllers[RuntimeComponent] = Controller end
	for SlotName, Content in pairs(Slots or {}) do
		self:FillComponentSlot(RuntimeComponent, SlotName, Content)
	end

	self.CreatedComponents[RuntimeComponent] = true
	return RuntimeComponent
end

function ProjectRuntime:_GetComponentController(Target)
	local Controller = self.ComponentControllers[Target]
	if Controller then return Controller end
	if typeof(Target) == 'Instance' then return self.ComponentControllers[Target] end
	if type(Target) == 'string' and self.CurrentScreen then
		local Screen = self.Screens[self.CurrentScreen]
		local CurrentWidget = Screen and Screen.Widgets[Target]
		return CurrentWidget and self.ComponentControllers[CurrentWidget] or nil
	end
end

function ProjectRuntime:GetComponentSlots(Target)
	local Controller = self:_GetComponentController(Target)
	if not Controller then return {} end

	local Result = {}
	local Root = Controller.Widget.Object
	for Path, Object in pairs(Controller.Screen.Instances or {}) do
		if Object == Root or Object:IsDescendantOf(Root) then
			local SlotName = Object:GetAttribute('FORGESlotName')
			if type(SlotName) == 'string' and SlotName ~= '' then
				Result[SlotName] = {
					Object = Object,
					Widget = Controller.Screen.ObjectWidgets[Object],
					Path = Path
				}
			end
		end
	end
	return Result
end

function ProjectRuntime:ClearComponentSlot(Target, SlotName)
	local Controller = self:_GetComponentController(Target)
	if not Controller then return false end
	local Slot = self:GetComponentSlots(Controller.Widget)[SlotName]
	if not Slot then return false end

	local Destroyed = {}
	if Slot.Widget then
		for Index = #Slot.Widget.Children, 1, -1 do
			local Child = Slot.Widget.Children[Index]
			local Object = Child and Child.Object
			if Object and Object.Parent == Slot.Object and Object:GetAttribute('FORGESlotContent') == true then
				Destroyed[Object] = true
				Child:Destroy()
			end
		end
	end

	for _, Child in ipairs(Slot.Object:GetChildren()) do
		if not Destroyed[Child] and Child:GetAttribute('FORGESlotContent') == true then Child:Destroy() end
	end
	return true
end

function ProjectRuntime:FillComponentSlot(Target, SlotName, Content)
	local Controller = self:_GetComponentController(Target)
	if not Controller then return false end
	local Slot = self:GetComponentSlots(Controller.Widget)[SlotName]
	if not Slot then return false end

	local Contents = type(Content) == 'table' and Content.Object and {Content}
		or type(Content) == 'table' and Content
		or {Content}
	local SlotWidget = Slot.Widget

	for _, Entry in ipairs(Contents) do
		if type(Entry) == 'table' and Entry.Object then
			if Entry.Parent then
				local Parent = Entry.Parent
				if Parent.RemoveChild then
					Parent:RemoveChild(Entry)
				else
					local Index = table.find(Parent.Children or {}, Entry)
					if Index then table.remove(Parent.Children, Index) end
					Entry.Parent = nil
				end
			elseif Entry.Mounted then
				Entry:Unmount()
			end

			Entry.Object:SetAttribute('FORGESlotContent', true)
			Entry.Object.Parent = Slot.Object
			Entry.Parent = SlotWidget
			if SlotWidget then table.insert(SlotWidget.Children, Entry) end

			local Manager = Controller.Widget.Manager
			if Manager then Manager:RegisterWidgetTree(Entry) end
			if Controller.Widget.Mounted then Entry:_MountTree() end
		elseif typeof(Entry) == 'Instance' then
			Entry:SetAttribute('FORGESlotContent', true)
			Entry.Parent = Slot.Object
		end
	end

	return true
end

function ProjectRuntime:_BuildAnimation(Name)
	local Definition = self.Data.Animations and self.Data.Animations[Name]
	if not Definition then return nil end

	local Result = Animation.new()
	Result:SetPlayback(Definition.Loop and -1 or 0, Definition.Reverse == true, 0)
	local Stagger = tonumber(Definition.Stagger) or 0

	local TrackCount = 0
	for Index, Track in ipairs(Definition.Tracks or {}) do
		if Track.PropertyKind ~= 'Semantic' and not Track.FromExpression and not Track.ToExpression then
			TrackCount += 1
			local TargetPath = Track.TargetPath
			local Property = Track.Property
			local From, To = Track.From, Track.To

			Result:AddTrack(function(Owner)
				return Owner and ResolveRelative(Owner.Object, TargetPath) or nil
			end, function(Owner, Reverse)
				local Target = Owner and ResolveRelative(Owner.Object, TargetPath)
				if not Target then return {} end
				return {[Property] = Reverse and From or To}
			end, (tonumber(Track.Delay) or 0) + Stagger * (Index - 1), tonumber(Track.Duration) or .2, Track.EasingStyle, Track.EasingDirection)
		end
	end

	if TrackCount == 0 then
		Result:Destroy()
		return nil
	end
	return Result
end

function ProjectRuntime:_PlayDynamicAnimation(Name, Owner, Definition, Reverse)
	local Tracks = {}
	for Index, Track in ipairs(Definition.Tracks or {}) do
		if Track.PropertyKind == 'Semantic' or Track.FromExpression or Track.ToExpression then
			table.insert(Tracks, {Index = Index, Track = Track})
		end
	end
	if #Tracks == 0 then return nil end

	local Session = {Cancelled = false, Remaining = #Tracks, Name = Name, Owner = Owner}
	self.ActiveSemanticAnimations[Session] = true
	local Stagger = math.max(0, tonumber(Definition.Stagger) or 0)

	local function Complete()
		Session.Remaining -= 1
		if Session.Remaining <= 0 then
			self.ActiveSemanticAnimations[Session] = nil
			local Active = self.ActiveAnimationOwners[Owner]
			if Active and Active.Dynamic == Session then
				Active.Dynamic = nil
				if not Active.Result then self.ActiveAnimationOwners[Owner] = nil end
			end
		end
	end

	for _, Entry in ipairs(Tracks) do
		task.spawn(function()
			local Track, Index = Entry.Track, Entry.Index
			local Target = ResolveRelative(Owner.Object, Track.TargetPath)
			if not Target then Complete() return end

			local Kind = Track.PropertyKind or 'Native'
			local DefaultBase = self:_GetAnimationBaseline(Owner, Target, Track.Property, Kind)
			local Success, CurrentBase = GetAnimationValue(Target, Track.Property, Kind)
			if DefaultBase == nil or not Success then Complete() return end

			local ForwardFrom, FromOK = ResolveAnimationEndpoint(DefaultBase, CurrentBase, Track.From, Track.FromExpression)
			local ForwardTo, ToOK = ResolveAnimationEndpoint(DefaultBase, CurrentBase, Track.To, Track.ToExpression)
			if not FromOK or not ToOK then Complete() return end

			local Delay = math.max(0, tonumber(Track.Delay) or 0) + Stagger * (Index - 1)
			if Delay > 0 then task.wait(Delay) end
			if Session.Cancelled then Complete() return end

			local A = Reverse and ForwardTo or ForwardFrom
			local B = Reverse and ForwardFrom or ForwardTo
			local Duration = math.max(0, tonumber(Track.Duration) or 0)
			local Style = Track.EasingStyle or Enum.EasingStyle.Quad
			local Direction = Track.EasingDirection or Enum.EasingDirection.Out

			local function TweenDynamic(From, To)
				if Duration <= 0 then
					SetAnimationValue(Target, Track.Property, Kind, To)
					return
				end

				local Started = os.clock()
				while not Session.Cancelled do
					local Alpha = math.clamp((os.clock() - Started) / Duration, 0, 1)
					local Eased = TweenService:GetValue(Alpha, Style, Direction)
					SetAnimationValue(Target, Track.Property, Kind, LerpValue(From, To, Eased))
					if Alpha >= 1 then break end
					RunService.Heartbeat:Wait()
				end
			end

			repeat
				SetAnimationValue(Target, Track.Property, Kind, A)
				TweenDynamic(A, B)
				if Definition.Reverse and not Session.Cancelled then TweenDynamic(B, A) end
			until Session.Cancelled or not Definition.Loop

			Complete()
		end)
	end

	return Session
end


function ProjectRuntime:PlayAnimation(Name, Owner, Reverse)
	if type(Owner) == 'string' then Owner = self:GetWidget(Owner) end
	local ComponentController = self.ComponentControllers[Owner]
	if ComponentController then Owner = ComponentController.Widget end
	if typeof(Owner) == 'Instance' and self.CurrentScreen then
		local Screen = self.Screens[self.CurrentScreen]
		Owner = Screen and Screen.ObjectWidgets[Owner]
	end
	if type(Owner) ~= 'table' or not Owner.Object then return nil end

	local Definition = self.Data.Animations and self.Data.Animations[Name]
	if not Definition then return nil end

	self:_CancelOwnerAnimation(Owner)
	self:_CaptureAnimationDefinitionBaselines(Definition, Owner)

	if Definition.InheritEndFrom then
		self:_RestoreAnimationOwnerBaseline(Owner)
		self:_ApplyAnimationEndPose(Definition.InheritEndFrom, Owner)
	end

	for _, Track in ipairs(Definition.Tracks or {}) do
		if Track.From ~= nil
			and Track.PropertyKind ~= 'Semantic'
			and not Track.FromExpression
			and not Track.ToExpression
			and Reverse ~= true
		then
			local Target = ResolveRelative(Owner.Object, Track.TargetPath)
			if Target then pcall(function() Target[Track.Property] = Track.From end) end
		end
	end

	local Dynamic = self:_PlayDynamicAnimation(Name, Owner, Definition, Reverse == true)
	local Result = self:_BuildAnimation(Name)
	local Active = {Result = Result, Dynamic = Dynamic}
	if Result or Dynamic then self.ActiveAnimationOwners[Owner] = Active end

	if Result then
		self.ActiveAnimations[Result] = true
		Result.OnCompleted:Connect(function()
			if self.ActiveAnimations[Result] then
				self.ActiveAnimations[Result] = nil
				Result:Destroy()
			end
			local Current = self.ActiveAnimationOwners[Owner]
			if Current and Current.Result == Result then
				Current.Result = nil
				if not Current.Dynamic then self.ActiveAnimationOwners[Owner] = nil end
			end
		end)
		Result:Play(Owner, 1, Reverse == true)
	end

	return Result or Dynamic or Definition.InheritEndFrom ~= nil
end


function ProjectRuntime:StopAnimations()
	for Result in pairs(self.ActiveAnimations) do Result:Destroy() end
	table.clear(self.ActiveAnimations)

	for Session in pairs(self.ActiveSemanticAnimations) do Session.Cancelled = true end
	table.clear(self.ActiveSemanticAnimations)
	table.clear(self.ActiveAnimationOwners)
end

function ProjectRuntime:_DestroyScreens()
	local Seen = {}
	for _, Controller in pairs(self.ComponentControllers) do
		if type(Controller) == 'table' and Controller.Widget and not Seen[Controller] then
			Seen[Controller] = true
			if Controller.ShineTween then Controller.ShineTween:Cancel() end
			for _, Connection in ipairs(Controller.Connections or {}) do Connection:Disconnect() end
			if Controller.State then Controller.State:Destroy() end
		end
	end
	table.clear(self.ComponentControllers)

	for _, Screen in pairs(self.Screens) do
		if Screen.ViewportConnection then
			Screen.ViewportConnection:Disconnect()
			Screen.ViewportConnection = nil
		end
		for _, Connection in ipairs(Screen.ScrollerConnections or {}) do
			Connection:Disconnect()
		end
		Screen.ScrollerConnections = {}

		if Screen.UserWidget then
			self.UI.RemoveFromViewport(Screen.UserWidget)
			Screen.UserWidget:Destroy()
		end
	end
	table.clear(self.Screens)

	for Component in pairs(self.CreatedComponents) do
		if Component and not Component.Destroyed then Component:Destroy() end
	end
	table.clear(self.CreatedComponents)
	table.clear(self.AnimationBaselines)
end

function ProjectRuntime:Reload(Data)
	ValidateProjectData(self.UI, Data)
	local Previous = self.CurrentScreen
	self:StopAnimations()
	self:_DestroyScreens()
	self.Data = Data
	self.CurrentScreen = nil
	table.clear(self.Stack)
	self:_BuildStyleSets()

	local Target = Previous and Data.Screens and Data.Screens[Previous] and Previous or Data.StartScreen
	return self:OpenScreen(Target, 'None', 0, false)
end

function ProjectRuntime:Destroy()
	if self.Destroyed then return end
	self.Destroyed = true
	self:StopAnimations()
	self:_DestroyScreens()
	table.clear(self.StyleSets)
	table.clear(self.Stack)
	self.CurrentScreen = nil
end

return ProjectRuntime
