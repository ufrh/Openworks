local Profile = {} do
	Profile.ClassName = 'Profile'

	Profile.__index = function(self, Key)
		local Method = rawget(Profile, Key)
		if Method ~= nil then return Method end
		if Key == 'Changed' then return self._Adapter.Changed end
		if Key == 'ReadOnly' then return self._Adapter.ReadOnly == true end
		if Key == 'Store' then return self._Adapter.Store end
		if Key == 'UserId' then return self._Adapter.UserId end
		return self:_Value(tostring(Key))
	end

	Profile.__newindex = function(self, Key, Value)
		if string.sub(tostring(Key), 1, 1) == '_' then rawset(self, Key, Value); return end
		self:_Write(tostring(Key), Value)
	end

	Profile.__iter = function(self)
		local Snapshot = self:Snapshot()
		return next, Snapshot, nil
	end

	local Node = {}
	Node.__index = function(self, Key)
		local Method = rawget(Node, Key)
		if Method ~= nil then return Method end
		return self._Profile:_Value(self:_Path(Key))
	end

	Node.__newindex = function(self, Key, Value)
		if string.sub(tostring(Key), 1, 1) == '_' then rawset(self, Key, Value); return end
		self._Profile:_Write(self:_Path(Key), Value)
	end

	Node.__iter = function(self)
		local Snapshot = self:Snapshot()
		return next, Snapshot, nil
	end

	local function join(A, B)
		if A == '' then return tostring(B) end
		return A .. '.' .. tostring(B)
	end

	function Node:_Path(Key)
		return join(self._Base, Key)
	end

	function Node:Get(Key)
		if Key == nil then return self:Snapshot() end
		return self._Profile:Get(self:_Path(Key))
	end

	function Node:Set(Key, Value)
		return self._Profile:Set(self:_Path(Key), Value)
	end

	function Node:Update(Key, Callback)
		return self._Profile:Update(self:_Path(Key), Callback)
	end

	function Node:Snapshot()
		return self._Profile:Get(self._Base)
	end

	function Node:Has(Key)
		return self._Profile:Has(self:_Path(Key))
	end

	function Profile.new(Adapter)
		assert(type(Adapter) == 'table', 'FORGE Profile requires an adapter.')
		assert(type(Adapter.Get) == 'function', 'FORGE Profile adapter requires Get.')
		assert(type(Adapter.Snapshot) == 'function', 'FORGE Profile adapter requires Snapshot.')

		local self = {
			_Adapter = Adapter,
			_Nodes = {}
		}

		return setmetatable(self, Profile)
	end

	function Profile:_Node(Path)
		local Existing = self._Nodes[Path]
		if Existing then return Existing end

		local Created = setmetatable({
			_Profile = self,
			_Base = Path
		}, Node)

		self._Nodes[Path] = Created
		return Created
	end

	function Profile:_Value(Path)
		local Value = self._Adapter:Get(Path)
		if type(Value) == 'table' then return self:_Node(Path) end
		return Value
	end

	function Profile:_Write(Path, Value)
		assert(self._Adapter.ReadOnly ~= true, 'Cannot write to a replicated read-only FORGE Profile.')
		assert(type(self._Adapter.Set) == 'function', 'FORGE Profile adapter does not support writes.')

		local Success, Result = self._Adapter:Set(Path, Value)
		if not Success then error(tostring(Result), 3) end
		return Result
	end

	function Profile:Get(Path)
		if Path == nil or Path == '' then return self:Snapshot() end
		return self._Adapter:Get(Path)
	end

	function Profile:Set(Path, Value)
		assert(self._Adapter.ReadOnly ~= true, 'Cannot write to a replicated read-only FORGE Profile.')
		local Success, Result = self._Adapter:Set(Path, Value)
		return Success, Result
	end

	function Profile:Has(Path)
		if type(self._Adapter.Has) == 'function' then return self._Adapter:Has(Path) end
		return self._Adapter:Get(Path) ~= nil
	end

	function Profile:Increment(Path, Delta)
		assert(self._Adapter.ReadOnly ~= true, 'Cannot write to a replicated read-only FORGE Profile.')
		assert(type(self._Adapter.Increment) == 'function', 'FORGE Profile adapter does not support Increment.')
		return self._Adapter:Increment(Path, Delta)
	end

	function Profile:Update(Path, Callback)
		assert(self._Adapter.ReadOnly ~= true, 'Cannot write to a replicated read-only FORGE Profile.')
		assert(type(self._Adapter.Update) == 'function', 'FORGE Profile adapter does not support Update.')
		return self._Adapter:Update(Path, Callback)
	end

	function Profile:Transaction(Callback)
		assert(self._Adapter.ReadOnly ~= true, 'Cannot transact on a replicated read-only FORGE Profile.')
		assert(type(self._Adapter.Transaction) == 'function', 'FORGE Profile adapter does not support transactions.')
		return self._Adapter:Transaction(Callback)
	end

	function Profile:Snapshot()
		return self._Adapter:Snapshot()
	end

	function Profile:Watch(Path, Callback)
		assert(type(Path) == 'string' and Path ~= '', 'Profile:Watch requires a path.')
		assert(type(Callback) == 'function', 'Profile:Watch requires a callback.')

		return self.Changed:Connect(function(ChangedPath, NewValue, OldValue)
			if ChangedPath == '*' then
				Callback(self:Get(Path), nil, ChangedPath)
				return
			end

			if ChangedPath == Path
				or string.sub(ChangedPath, 1, #Path + 1) == Path .. '.'
				or string.sub(Path, 1, #ChangedPath + 1) == ChangedPath .. '.'
			then
				Callback(self:Get(Path), OldValue, ChangedPath)
			end
		end)
	end

	function Profile:Save()
		assert(self._Adapter.ReadOnly ~= true, 'Cannot save a replicated read-only FORGE Profile.')
		assert(type(self._Adapter.Save) == 'function', 'FORGE Profile adapter does not support Save.')
		return self._Adapter:Save()
	end

	function Profile:Raw()
		return self._Adapter.Raw
	end
end

return Profile
