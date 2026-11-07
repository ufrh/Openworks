local PanelWidget = require(script.Parent.PanelWidget)
local ContentWidget = require(script.Parent.ContentWidget)
local CanvasSlot = require(script.Parent.CanvasSlot)
local BoxSlot = require(script.Parent.BoxSlot)
local GridSlot = require(script.Parent.GridSlot)
local OverlaySlot = require(script.Parent.OverlaySlot)
local SizeBoxSlot = require(script.Parent.SizeBoxSlot)

local Panels = {}

local function ResolveAxis(Size, ParentSize, Horizontal)
	local Axis = Horizontal and Size.X or Size.Y
	return math.max(ParentSize * Axis.Scale + Axis.Offset, 0)
end

local function Frame(Name)
	local Object = Instance.new('Frame')
	Object.Name = Name
	Object.BackgroundTransparency = 1
	Object.BorderSizePixel = 0
	return Object
end

local function LayoutPanel(Name, FillDirection)
	local self = PanelWidget.new(Frame(Name))
	self.ClassName = Name
	self.Orientation = FillDirection == Enum.FillDirection.Horizontal and 'Horizontal' or 'Vertical'
	self.Spacing = 0

	function self:CreateSlot(Content)
		return BoxSlot.new(self, Content)
	end

	function self:ApplyLayout()
		local Horizontal = self.Orientation == 'Horizontal'
		local ParentSize = Horizontal and self.Object.AbsoluteSize.X or self.Object.AbsoluteSize.Y
		if ParentSize <= 0 then return self end

		local Fixed, FillWeight, Visible = 0, 0, 0
		for _, Child in ipairs(self.Children) do
			if Child.Visibility ~= 'Collapsed' then
				Visible += 1
				local Slot = Child.Slot
				local Before, CrossBefore, After, CrossAfter = Slot:GetPadding()
				if Horizontal then
					Fixed += Before + After
				else
					Fixed += CrossBefore + CrossAfter
				end
				if Slot.Fill > 0 then
					FillWeight += Slot.Fill
				else
					local Size = Slot.Size or Child.Object.Size
					Fixed += ResolveAxis(Size, ParentSize, Horizontal)
				end
			end
		end

		Fixed += math.max(Visible - 1, 0) * self.Spacing
		local Remaining = math.max(ParentSize - Fixed, 0)
		local Cursor = 0

		for _, Child in ipairs(self.Children) do
			if Child.Visibility ~= 'Collapsed' then
				local Slot, Object = Child.Slot, Child.Object
				local Left, Top, Right, Bottom = Slot:GetPadding()
				local MainBefore = Horizontal and Left or Top
				local MainAfter = Horizontal and Right or Bottom
				local CrossBefore = Horizontal and Top or Left
				local CrossAfter = Horizontal and Bottom or Right
				local MainSize

				if Slot.Fill > 0 and FillWeight > 0 then
					MainSize = Remaining * Slot.Fill / FillWeight
				else
					local Size = Slot.Size or Object.Size
					MainSize = ResolveAxis(Size, ParentSize, Horizontal)
				end

				Cursor += MainBefore
				if Horizontal then
					Object.AnchorPoint = Vector2.zero
					Object.Position = UDim2.fromOffset(math.floor(Cursor), CrossBefore)
					Object.Size = UDim2.new(0, math.floor(MainSize), 1, -(CrossBefore + CrossAfter))
				else
					Object.AnchorPoint = Vector2.zero
					Object.Position = UDim2.fromOffset(CrossBefore, math.floor(Cursor))
					Object.Size = UDim2.new(1, -(CrossBefore + CrossAfter), 0, math.floor(MainSize))
				end
				Cursor += MainSize + MainAfter + self.Spacing
			end
		end

		return self
	end

	function self:InvalidateLayout()
		self:ApplyLayout()
		return self
	end

	function self:SetSpacing(Spacing)
		self.Spacing = math.max(tonumber(Spacing) or 0, 0)
		self:ApplyLayout()
		return self
	end

	function self:SetClipping(Enabled)
		self.Object.ClipsDescendants = Enabled == true
		return self
	end

	table.insert(self.Connections, self.Object:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()
		self:ApplyLayout()
	end))

	return self
end
function Panels.CanvasPanel()
	local self = PanelWidget.new(Frame('CanvasPanel'))
	self.ClassName = 'CanvasPanel'
	function self:CreateSlot(Content) return CanvasSlot.new(self, Content) end
	function self:SetClipping(Enabled) self.Object.ClipsDescendants = Enabled == true return self end
	return self
end

function Panels.Overlay()
	local self = PanelWidget.new(Frame('Overlay'))
	self.ClassName = 'Overlay'
	function self:CreateSlot(Content) return OverlaySlot.new(self, Content) end
	function self:SetClipping(Enabled) self.Object.ClipsDescendants = Enabled == true return self end
	return self
end

function Panels.HorizontalBox()
	return LayoutPanel('HorizontalBox', Enum.FillDirection.Horizontal)
end

function Panels.VerticalBox()
	return LayoutPanel('VerticalBox', Enum.FillDirection.Vertical)
end

function Panels.GridPanel(CellSize, CellPadding)
	local self = PanelWidget.new(Frame('GridPanel'))
	self.ClassName = 'GridPanel'
	self.MaxColumns = 1

	local Layout = Instance.new('UIGridLayout')
	Layout.CellSize = CellSize or UDim2.fromOffset(100, 100)
	Layout.CellPadding = CellPadding or UDim2.fromOffset(0, 0)
	Layout.FillDirectionMaxCells = 1
	Layout.SortOrder = Enum.SortOrder.LayoutOrder
	Layout.Parent = self.Object
	self.Layout = Layout

	function self:CreateSlot(Content)
		return GridSlot.new(self, Content)
	end

	function self:SetCellSize(Size)
		self.Layout.CellSize = Size
		return self
	end

	function self:SetCellPadding(Padding)
		self.Layout.CellPadding = Padding
		return self
	end

	function self:SetMaxColumns(Columns)
		self.MaxColumns = math.max(math.floor(Columns or 1), 1)
		self.Layout.FillDirectionMaxCells = self.MaxColumns
		self:InvalidateLayout()
		return self
	end

	function self:SetStartCorner(Corner)
		self.Layout.StartCorner = Corner
		return self
	end

	function self:SetFillDirection(Direction)
		self.Layout.FillDirection = Direction
		return self
	end

	function self:SetHorizontalAlignment(Alignment)
		self.Layout.HorizontalAlignment = Alignment
		return self
	end

	function self:SetVerticalAlignment(Alignment)
		self.Layout.VerticalAlignment = Alignment
		return self
	end

	function self:SetClipping(Enabled)
		self.Object.ClipsDescendants = Enabled == true
		return self
	end

	return self
end

function Panels.ScrollBox()
	local Object = Instance.new('ScrollingFrame')
	Object.Name = 'ScrollBox'
	Object.BackgroundTransparency = 1
	Object.BorderSizePixel = 0
	Object.CanvasSize = UDim2.new()
	Object.AutomaticCanvasSize = Enum.AutomaticSize.Y
	Object.ScrollBarImageTransparency = 0
	Object.ClipsDescendants = true

	local self = PanelWidget.new(Object)
	self.ClassName = 'ScrollBox'
	self.Orientation = 'Vertical'

	local Layout = Instance.new('UIListLayout')
	Layout.SortOrder = Enum.SortOrder.LayoutOrder
	Layout.Parent = Object
	self.Layout = Layout

	function self:CreateSlot(Content)
		return BoxSlot.new(self, Content)
	end

	function self:GetFillFraction(Target)
		local Total = 0
		for _, Child in ipairs(self.Children) do
			if Child.Slot and Child.Slot.Fill then Total += Child.Slot.Fill end
		end
		return Total > 0 and Target.Fill / Total or 0
	end

	function self:SetOrientation(Orientation)
		assert(Orientation == 'Horizontal' or Orientation == 'Vertical', 'Invalid ScrollBox orientation.')
		self.Orientation = Orientation
		self.Layout.FillDirection = Orientation == 'Horizontal' and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
		self.Object.AutomaticCanvasSize = Orientation == 'Horizontal' and Enum.AutomaticSize.X or Enum.AutomaticSize.Y
		self.Object.ScrollingDirection = Orientation == 'Horizontal' and Enum.ScrollingDirection.X or Enum.ScrollingDirection.Y
		self:InvalidateLayout()
		return self
	end

	function self:SetSpacing(Spacing)
		self.Layout.Padding = UDim.new(0, Spacing)
		return self
	end

	function self:SetScrollBarThickness(Thickness)
		self.Object.ScrollBarThickness = math.max(math.floor(tonumber(Thickness) or 0), 0)
		return self
	end

	function self:SetBackgroundTransparency(Transparency)
		self.Object.BackgroundTransparency = math.clamp(tonumber(Transparency) or 0, 0, 1)
		return self
	end

	function self:SetScrollBarVisible(Visible)
		self.Object.ScrollBarImageTransparency = Visible == false and 1 or 0
		return self
	end

	function self:SetCanvasPadding(Left, Top, Right, Bottom)
		local Padding = self.Object:FindFirstChild('CanvasPadding') or Instance.new('UIPadding')
		Padding.Name = 'CanvasPadding'
		Padding.PaddingLeft = UDim.new(0, Left or 0)
		Padding.PaddingTop = UDim.new(0, Top or Left or 0)
		Padding.PaddingRight = UDim.new(0, Right or Left or 0)
		Padding.PaddingBottom = UDim.new(0, Bottom or Top or Left or 0)
		Padding.Parent = self.Object
		return self
	end

	function self:SetClipping(Enabled)
		self.Object.ClipsDescendants = Enabled == true
		return self
	end

	return self
end

function Panels.SizeBox()
	local self = ContentWidget.new(Frame('SizeBox'))
	self.ClassName = 'SizeBox'
	self.WidthOverride = nil
	self.HeightOverride = nil
	self.MinDesiredWidth = nil
	self.MinDesiredHeight = nil
	self.MaxDesiredWidth = nil
	self.MaxDesiredHeight = nil

	function self:CreateSlot(Content)
		return SizeBoxSlot.new(self, Content)
	end

	function self:SetWidthOverride(Width)
		self.WidthOverride = Width
		self.Object.Size = UDim2.new(self.Object.Size.X.Scale, Width or self.Object.Size.X.Offset, self.Object.Size.Y.Scale, self.Object.Size.Y.Offset)
		return self
	end

	function self:SetHeightOverride(Height)
		self.HeightOverride = Height
		self.Object.Size = UDim2.new(self.Object.Size.X.Scale, self.Object.Size.X.Offset, self.Object.Size.Y.Scale, Height or self.Object.Size.Y.Offset)
		return self
	end

	function self:SetMinDesiredWidth(Width)
		self.MinDesiredWidth = Width
		self.Object.Size = UDim2.new(self.Object.Size.X.Scale, math.max(self.Object.Size.X.Offset, Width or 0), self.Object.Size.Y.Scale, self.Object.Size.Y.Offset)
		return self
	end

	function self:SetMinDesiredHeight(Height)
		self.MinDesiredHeight = Height
		self.Object.Size = UDim2.new(self.Object.Size.X.Scale, self.Object.Size.X.Offset, self.Object.Size.Y.Scale, math.max(self.Object.Size.Y.Offset, Height or 0))
		return self
	end

	function self:SetAutomaticSize(Axis)
		self.Object.AutomaticSize = Axis or Enum.AutomaticSize.XY
		return self
	end

	return self
end

function Panels.Border()
	local Object = Frame('Border')
	Object.BackgroundTransparency = 0
	local self = ContentWidget.new(Object)
	self.ClassName = 'Border'

	function self:SetBrushColor(Color)
		self.Object.BackgroundColor3 = Color
		return self
	end

	function self:SetBrushTransparency(Transparency)
		self.Object.BackgroundTransparency = Transparency
		return self
	end

	function self:SetClipping(Enabled)
		self.Object.ClipsDescendants = Enabled == true
		return self
	end

	return self
end

function Panels.ScaleBox()
	local self = ContentWidget.new(Frame('ScaleBox'))
	self.ClassName = 'ScaleBox'
	local Scale = Instance.new('UIScale')
	Scale.Parent = self.Object
	self.Scale = Scale
	function self:SetScale(Value) self.Scale.Scale = Value return self end
	return self
end

function Panels.SafeZone()
	local self = ContentWidget.new(Frame('SafeZone'))
	self.ClassName = 'SafeZone'
	local Padding = Instance.new('UIPadding')
	Padding.Parent = self.Object
	self.Padding = Padding
	function self:SetPadding(Left, Top, Right, Bottom)
		Padding.PaddingLeft = UDim.new(0, Left or 0)
		Padding.PaddingTop = UDim.new(0, Top or Left or 0)
		Padding.PaddingRight = UDim.new(0, Right or Left or 0)
		Padding.PaddingBottom = UDim.new(0, Bottom or Top or Left or 0)
		return self
	end
	return self
end

function Panels.WidgetSwitcher()
	local self = PanelWidget.new(Frame('WidgetSwitcher'))
	self.ClassName = 'WidgetSwitcher'
	self.ActiveIndex = 1

	function self:SetActiveWidgetIndex(Index)
		self.ActiveIndex = math.clamp(math.floor(Index or 1), 1, math.max(#self.Children, 1))
		for ChildIndex, Child in ipairs(self.Children) do Child:_SetInternalVisible(ChildIndex == self.ActiveIndex) end
		return self
	end

	function self:GetActiveWidgetIndex()
		return self.ActiveIndex
	end

	function self:GetActiveWidget()
		return self.Children[self.ActiveIndex]
	end

	function self:SetActiveWidget(Widget)
		local Index = table.find(self.Children, Widget)
		if Index then self:SetActiveWidgetIndex(Index) end
		return self
	end

	local BaseAddChild, BaseRemoveChild = self.AddChild, self.RemoveChild

	function self:AddChild(Content)
		local Slot = BaseAddChild(self, Content)
		self:SetActiveWidgetIndex(self.ActiveIndex)
		return Slot
	end

	function self:RemoveChild(Content)
		local ActiveWidget = self:GetActiveWidget()
		local RemovedIndex = self:GetChildIndex(Content)
		local WasActive = ActiveWidget == Content
		local Removed = BaseRemoveChild(self, Content)

		if Removed then
			if #self.Children == 0 then
				self.ActiveIndex = 1
			elseif not WasActive and ActiveWidget then
				self.ActiveIndex = table.find(self.Children, ActiveWidget) or math.clamp(self.ActiveIndex, 1, #self.Children)
			else
				self.ActiveIndex = math.clamp(RemovedIndex, 1, #self.Children)
			end

			if #self.Children > 0 then self:SetActiveWidgetIndex(self.ActiveIndex) end
		end

		return Removed
	end

	return self
end

return Panels;