local StyleSet = {} do
	StyleSet.__index = StyleSet

	function StyleSet.new(Name, Parent)
		local self = setmetatable({}, StyleSet)
		self.Name = Name or 'StyleSet'
		self.Parent = Parent
		self.Resources = {}
		self.Styles = {}
		return self
	end

	function StyleSet:SetResource(Name, Value)
		self.Resources[Name] = Value
		return self
	end

	function StyleSet:GetResource(Name, Default)
		local Value = self.Resources[Name]
		if Value ~= nil then return Value end
		if self.Parent then return self.Parent:GetResource(Name, Default) end
		return Default
	end

	function StyleSet:Set(Name, Style)
		self.Styles[Name] = Style
		return self
	end

	function StyleSet:Get(Name)
		return self.Styles[Name] or self.Parent and self.Parent:Get(Name)
	end

	function StyleSet:Has(Name)
		return self:Get(Name) ~= nil
	end

	function StyleSet:Resolve(Value)
		if type(Value) == 'table' and Value.Resource then return self:GetResource(Value.Resource, Value.Default) end
		return Value
	end

	function StyleSet:Apply(Name, Widget)
		local Style = self:Get(Name)
		assert(Style, string.format('Style %q does not exist in %s.', Name, self.Name))
		if type(Style) == 'function' then
			Style(Widget, self)
		else
			for Property, Value in pairs(Style) do Widget.Object[Property] = self:Resolve(Value) end
		end
		Widget.StyleSet = self
		Widget.StyleName = Name
		return Widget
	end
end

function StyleSet.Resource(Name, Default)
	return {Resource = Name, Default = Default}
end

return StyleSet;