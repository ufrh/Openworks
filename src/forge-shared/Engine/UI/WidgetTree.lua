local WidgetTree = {} do
	WidgetTree.__index = WidgetTree

	function WidgetTree.new()
		local self = setmetatable({}, WidgetTree)
		self.RootWidget = nil
		return self
	end

	function WidgetTree:SetRootWidget(Widget)
		self.RootWidget = Widget
		return Widget
	end

	function WidgetTree:GetRootWidget()
		return self.RootWidget
	end

	function WidgetTree:FindWidget(Name)
		local function Search(Widget)
			if not Widget then return nil end
			if Widget.Name == Name then return Widget end
			for _, Child in ipairs(Widget.Children or {}) do
				local Result = Search(Child)
				if Result then return Result end
			end
		end
		return Search(self.RootWidget)
	end

	function WidgetTree:GetAllWidgets()
		local Result = {}
		local function Walk(Widget)
			if not Widget then return end
			table.insert(Result, Widget)
			for _, Child in ipairs(Widget.Children or {}) do Walk(Child) end
		end
		Walk(self.RootWidget)
		return Result
	end

	function WidgetTree:ForEachWidget(Callback)
		for _, Widget in ipairs(self:GetAllWidgets()) do Callback(Widget) end
	end
end

return WidgetTree;