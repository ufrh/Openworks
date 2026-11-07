local Config = {} do
	Config.__index = function(self, Key)
		local Method = rawget(Config, Key)
		if Method ~= nil then return Method end

		local Value = self._Values[Key]
		if Value ~= nil then return Value end
		return self._Kernel[Key]
	end
	Config.ClassName = 'Config'

	local function copy(Value)
		if type(Value) ~= 'table' then return Value end
		local Result = {}
		for Key, Entry in pairs(Value) do Result[Key] = copy(Entry) end
		return Result
	end

	local function merge(Target, Source)
		for Key, Value in pairs(Source or {}) do
			if type(Value) == 'table' and type(Target[Key]) == 'table' then
				merge(Target[Key], Value)
			else
				Target[Key] = copy(Value)
			end
		end
		return Target
	end

	local function path(Path)
		if type(Path) == 'table' then return Path end
		local Result = {}
		for Segment in string.gmatch(tostring(Path), '[^%.]+') do table.insert(Result, Segment) end
		return Result
	end

	function Config.new(Kernel, Context)
		local self = setmetatable({}, Config)
		self._Kernel = Kernel
		self._Context = Context
		self._Values = {}
		self._Layers = {}
		return self
	end

	function Config:Get(Path, Default)
		local Current = self
		for _, Segment in ipairs(path(Path)) do
			Current = Current[Segment]
			if Current == nil then return Default end
		end
		return Current
	end

	function Config:Set(Path, Value)
		local Segments = path(Path)
		assert(#Segments > 0, 'Config:Set requires a path.')

		local Current = self._Values
		for Index = 1, #Segments - 1 do
			local Segment = Segments[Index]
			if type(Current[Segment]) ~= 'table' then Current[Segment] = {} end
			Current = Current[Segment]
		end
		Current[Segments[#Segments]] = Value
		return self
	end

	function Config:Merge(Values)
		assert(type(Values) == 'table', 'Config:Merge requires a table.')
		merge(self._Values, Values)
		return self
	end

	function Config:Layer(Name, Values)
		assert(type(Name) == 'string' and Name ~= '', 'Config:Layer requires a name.')
		assert(type(Values) == 'table', 'Config:Layer requires values.')
		self._Layers[Name] = copy(Values)
		if self._Context:Is(Name) then merge(self._Values, Values) end
		return self
	end

	function Config:Snapshot()
		local Result = copy(self._Kernel)
		merge(Result, self._Values)
		return Result
	end
end

return Config
