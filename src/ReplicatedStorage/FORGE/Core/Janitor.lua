-- Author -> lolokdev.
-- Last Edit -> September 13, 2026 8:44 AM CDT

local Janitor = {} do
	Janitor.__index = Janitor
	Janitor.ClassName = 'Janitor'

	-- new -> Janitor
	-- Creates a cleanup container for connections, instances and callbacks.
	function Janitor.new()
		local this = setmetatable({}, Janitor)
		this._Entries = {}
		this._Destroyed = false
		return this;
	end

	-- Add -> any
	-- Registers one object or cleanup callback.
	-- @param Object, any -> Object to clean.
	-- @param Method, string? -> Explicit cleanup method.
	function Janitor:Add(Object, Method)
		assert(not self._Destroyed, 'Cannot add to a destroyed Janitor.')
		table.insert(self._Entries, {Object = Object; Method = Method;})
		return Object;
	end

	-- _CleanupEntry -> nil
	-- Cleans one Janitor entry according to its type.
	-- @param Entry, table -> Cleanup entry.
	function Janitor:_CleanupEntry(Entry)
		local Object = Entry.Object
		local Method = Entry.Method

		if type(Object) == 'function' then
			pcall(Object)
			return
		end

		if typeof(Object) == 'RBXScriptConnection' then
			Object:Disconnect()
			return
		end

		if typeof(Object) == 'Instance' then
			Object:Destroy()
			return
		end

		if Method and Object and type(Object[Method]) == 'function' then
			pcall(function() Object[Method](Object) end)
			return
		end

		if Object and type(Object.Destroy) == 'function' then
			pcall(function() Object:Destroy() end)
		end
	end

	-- Cleanup -> nil
	-- Cleans all registered resources while keeping the Janitor reusable.
	function Janitor:Cleanup()
		for Index = #self._Entries, 1, -1 do
			self:_CleanupEntry(self._Entries[Index])
			self._Entries[Index] = nil
		end
	end

	-- Destroy -> nil
	-- Cleans all resources and permanently closes the Janitor.
	function Janitor:Destroy()
		if self._Destroyed then return end
		self:Cleanup()
		self._Destroyed = true
	end
end

return Janitor;
