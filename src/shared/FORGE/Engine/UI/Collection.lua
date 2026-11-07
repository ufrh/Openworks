local Collection = {}
Collection.__index = Collection
Collection.ClassName = 'Collection'

local function ResolvePath(Root, Path)
	if Path == nil or Path == '' or Path == 'Root' then return Root end

	local Current = Root
	for Segment in tostring(Path):gmatch('[^%.]+') do
		Current = Current and Current:FindFirstChild(Segment)
		if not Current then return nil end
	end
	return Current
end

function Collection.new(Runtime, Adornee, Populator)
	assert(type(Runtime) == 'table' and type(Runtime.Component) == 'function', 'Collection requires a component runtime.')
	assert(typeof(Adornee) == 'Instance', 'Collection requires an Instance adornee.')
	assert(type(Populator) == 'string' and Populator ~= '', 'Collection requires a component name.')

	local self = setmetatable({}, Collection)
	self.Adornee = Adornee
	self.Runtime = Runtime
	self.Populator = Populator
	self.Items = {}
	return self
end

function Collection:Clear()
	for _, Item in ipairs(self.Items) do
		Item:Destroy()
	end
	table.clear(self.Items)
	return self
end

function Collection:Mount(Fields)
	assert(type(Fields) == 'table', 'Collection:Mount requires an array of field maps.')

	for _, Field in ipairs(Fields) do
		local Item = self.Runtime:Component(self.Populator)
		if not Item then
			warn(string.format('[FORGE.UI] Collection could not create component %q.', self.Populator))
			break
		end

		Item:Mount(self.Adornee)
		table.insert(self.Items, Item)

		for Path, Properties in pairs(Field) do
			local Target = ResolvePath(Item.Object, Path)
			if not Target then
				warn(string.format('[FORGE.UI] Collection path %q was not found in %q.', tostring(Path), self.Populator))
				continue
			end

			for Property, Value in pairs(Properties) do
				local Success, Error = pcall(function()
					Target[Property] = Value
				end)
				if not Success then
					warn(string.format('[FORGE.UI] Collection failed to set %s.%s: %s', tostring(Path), tostring(Property), tostring(Error)))
				end
			end
		end
	end

	return self.Items
end

function Collection:Destroy()
	self:Clear()
	self.Runtime = nil
	self.Adornee = nil
end

return Collection
