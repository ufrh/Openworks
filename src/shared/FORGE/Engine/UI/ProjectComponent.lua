local UserWidget = require(script.Parent.UserWidget)

local ProjectComponent = setmetatable({}, UserWidget) do
	ProjectComponent.__index = ProjectComponent
	ProjectComponent.ClassName = 'Component'

	function ProjectComponent:Extend(Name)
		local Base = self
		local Class = setmetatable({}, Base)
		Class.__index = Class
		Class.ClassName = Name or 'Component'

		function Class.new(...)
			local self = setmetatable(UserWidget.new(Class.ClassName), Class)
			self.ClassName = Class.ClassName
			if self.Build then
				local Root = self:Build(...)
				if Root then self:SetRootWidget(Root) end
			end
			return self
		end
		return Class
	end

	function ProjectComponent.new(Name)
		local self = setmetatable(UserWidget.new(Name or 'Component'), ProjectComponent)
		self.ClassName = Name or 'Component'
		return self
	end
end

return ProjectComponent
