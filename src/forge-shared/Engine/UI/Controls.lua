local Widget = require(script.Parent.Widget)
local ContentWidget = require(script.Parent.ContentWidget)
local Signal = require(script.Parent.Parent.Parent.Kernel.Core.Signal)

local Controls = {}

local function Apply(Object, Properties)
	for Property, Value in pairs(Properties or {}) do Object[Property] = Value end
end

function Controls.TextBlock(Text, Properties)
	local Object = Instance.new('TextLabel')
	Object.Name = 'TextBlock'
	Object.BackgroundTransparency = 1
	Object.BorderSizePixel = 0
	Object.Text = Text or ''
	Apply(Object, Properties)

	local self = Widget.new(Object)
	self.ClassName = 'TextBlock'
	function self:SetText(Value) self.Object.Text = Value return self end
	function self:GetText() return self.Object.Text end
	return self
end

function Controls.Image(Asset, Properties)
	local Object = Instance.new('ImageLabel')
	Object.Name = 'Image'
	Object.BackgroundTransparency = 1
	Object.BorderSizePixel = 0
	Object.Image = Asset or ''
	Apply(Object, Properties)

	local self = Widget.new(Object)
	self.ClassName = 'Image'
	function self:SetBrush(Brush) self.Object.Image = Brush return self end
	return self
end

function Controls.Spacer(Size)
	local Object = Instance.new('Frame')
	Object.Name = 'Spacer'
	Object.BackgroundTransparency = 1
	Object.BorderSizePixel = 0
	Object.Size = Size or UDim2.fromOffset(8, 8)
	local self = Widget.new(Object)
	self.ClassName = 'Spacer'
	return self
end

function Controls.Button(Properties)
	local Object = Instance.new('TextButton')
	Object.Name = 'Button'
	Object.BackgroundTransparency = 1
	Object.BorderSizePixel = 0
	Object.Text = ''
	Object.AutoButtonColor = false
	Apply(Object, Properties)

	local self = ContentWidget.new(Object)
	self.ClassName = 'Button'
	self.IsPressed = false
	self.IsHovered = false
	self.OnPressed = Signal.new()
	self.OnReleased = Signal.new()

	self:On('MouseEnter', function()
		self.IsHovered = true
	end)

	self:On('MouseLeave', function()
		self.IsHovered = false
	end)

	self:On('PointerDown', function(Event)
		if not self.Enabled then return end
		self.IsPressed = true
		self.OnPressed:Fire(Event)
		return true
	end)

	self:On('PointerUp', function(Event)
		if not self.Enabled then return end
		self.IsPressed = false
		self.OnReleased:Fire(Event)
		return true
	end)

	local BaseDestroy = self.Destroy
	function self:Destroy()
		if self.Destroyed then return end
		self.OnPressed:Destroy()
		self.OnReleased:Destroy()
		BaseDestroy(self)
	end

	return self
end

function Controls.ProgressBar(Properties)
	local Root = Instance.new('Frame')
	Root.Name = 'ProgressBar'
	Root.BorderSizePixel = 0
	Apply(Root, Properties)

	local Fill = Instance.new('Frame')
	Fill.Name = 'Fill'
	Fill.BorderSizePixel = 0
	Fill.Size = UDim2.fromScale(0, 1)
	Fill.Parent = Root

	local self = Widget.new(Root)
	self.ClassName = 'ProgressBar'
	self.Fill = Fill
	self.Percent = 0

	function self:SetPercent(Percent)
		self.Percent = math.clamp(Percent, 0, 1)
		self.Fill.Size = UDim2.fromScale(self.Percent, 1)
		return self
	end

	return self
end

function Controls.CheckBox(Properties)
	local Object = Instance.new('TextButton')
	Object.Name = 'CheckBox'
	Object.Text = ''
	Object.AutoButtonColor = false
	Object.BorderSizePixel = 0
	Object.BackgroundTransparency = 1
	Apply(Object, Properties)

	local self = ContentWidget.new(Object)
	self.ClassName = 'CheckBox'
	self.Checked = false
	self.OnCheckStateChanged = Signal.new()

	function self:SetChecked(Checked, Silent)
		local Value = Checked == true
		if self.Checked == Value then return self end
		self.Checked = Value
		self.Object:SetAttribute('Checked', self.Checked)
		if Silent ~= true then self.OnCheckStateChanged:Fire(self.Checked) end
		return self
	end

	function self:IsChecked()
		return self.Checked
	end

	self:On('Clicked', function()
		if self.Enabled then self:SetChecked(not self.Checked) end
	end)

	local BaseDestroy = self.Destroy
	function self:Destroy()
		if self.Destroyed then return end
		self.OnCheckStateChanged:Destroy()
		BaseDestroy(self)
	end
	return self
end

function Controls.Slider(Properties)
	local Object = Instance.new('TextButton')
	Object.Name = 'Slider'
	Object.Text = ''
	Object.AutoButtonColor = false
	Object.BorderSizePixel = 0
	Apply(Object, Properties)

	local Fill = Instance.new('Frame')
	Fill.Name = 'Fill'
	Fill.BorderSizePixel = 0
	Fill.Size = UDim2.fromScale(0, 1)
	Fill.Parent = Object

	local self = Widget.new(Object)
	self.ClassName = 'Slider'
	self.MinValue = 0
	self.MaxValue = 1
	self.Value = 0
	self.StepSize = 0
	self.Fill = Fill
	self.Dragging = false
	self.OnValueChanged = Signal.new()

	function self:SetRange(Minimum, Maximum)
		assert(Maximum > Minimum, 'Slider maximum must be greater than minimum.')
		self.MinValue, self.MaxValue = Minimum, Maximum
		return self:SetValue(self.Value)
	end

	function self:SetStepSize(Step)
		self.StepSize = math.max(Step or 0, 0)
		return self:SetValue(self.Value)
	end

	function self:SetValue(Value, Silent)
		local Next = math.clamp(Value, self.MinValue, self.MaxValue)
		if self.StepSize > 0 then
			Next = self.MinValue + math.round((Next - self.MinValue) / self.StepSize) * self.StepSize
			Next = math.clamp(Next, self.MinValue, self.MaxValue)
		end
		local Changed = self.Value ~= Next
		self.Value = Next
		local Alpha = (self.Value - self.MinValue) / (self.MaxValue - self.MinValue)
		self.Fill.Size = UDim2.fromScale(Alpha, 1)
		if Changed and Silent ~= true then self.OnValueChanged:Fire(self.Value) end
		return self
	end

	function self:GetValue()
		return self.Value
	end

	function self:SetValueFromPosition(Position)
		local Width = self.Object.AbsoluteSize.X
		if Width <= 0 then return self end
		local Alpha = math.clamp((Position.X - self.Object.AbsolutePosition.X) / Width, 0, 1)
		return self:SetValue(self.MinValue + (self.MaxValue - self.MinValue) * Alpha)
	end

	self:On('PointerDown', function(Event)
		if not self.Enabled then return end
		self.Dragging = true
		self:SetValueFromPosition(Event.Position)
		return true
	end)

	self:On('MouseMove', function(Event)
		if self.Dragging then self:SetValueFromPosition(Event.Position) return true end
	end)

	self:On('PointerUp', function(Event)
		if not self.Dragging then return end
		self.Dragging = false
		self:SetValueFromPosition(Event.Position)
		return true
	end)

	local BaseDestroy = self.Destroy
	function self:Destroy()
		if self.Destroyed then return end
		self.OnValueChanged:Destroy()
		BaseDestroy(self)
	end
	return self
end

function Controls.TextBox(Text, Properties)
	local Object = Instance.new('TextBox')
	Object.Name = 'TextBox'
	Object.BackgroundTransparency = 1
	Object.BorderSizePixel = 0
	Object.Text = Text or ''
	Apply(Object, Properties)

	local self = Widget.new(Object)
	self.ClassName = 'TextBox'
	function self:SetText(Value) self.Object.Text = Value return self end
	function self:GetText() return self.Object.Text end
	function self:SetPlaceholder(Value) self.Object.PlaceholderText = Value return self end
	return self
end

return Controls;