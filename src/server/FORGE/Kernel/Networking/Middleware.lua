-- Author -> lolokdev.
-- Last Edit -> September 14, 2026 4:25 PM CDT

local Middleware = {} do
	Middleware.__index = Middleware
	Middleware.ClassName = 'Middleware'

	-- characterAlive -> boolean, string
	-- Rejects endpoint calls when the requesting character has no living Humanoid.
	-- @param Context, table -> Request context.
	local function characterAlive(Context)
		local Character = Context.Player.Character
		local Humanoid = Character and Character:FindFirstChildOfClass('Humanoid')
		return Character ~= nil and Humanoid ~= nil and Humanoid.Health > 0, 'character is not alive';
	end

	-- notKnockedOut -> boolean, string
	-- Rejects endpoint calls while the requesting character is marked knocked out.
	-- @param Context, table -> Request context.
	local function notKnockedOut(Context)
		local Character = Context.Player.Character
		return not Character or Character:GetAttribute('KnockedOut') ~= true, 'character is knocked out';
	end

	-- new -> Middleware
	-- Creates a named middleware registry with practical server-authority defaults.
	function Middleware.new()
		local this = setmetatable({}, Middleware)
		this._Named = {}
		this._Global = {}
		this:Register('CharacterAlive', characterAlive)
		this:Register('NotKnockedOut', notKnockedOut)
		return this;
	end

	-- Register -> nil
	-- Registers one reusable named server middleware function.
	-- @param Name, string -> Middleware name.
	-- @param Callback, function -> Validation callback.
	function Middleware:Register(Name, Callback)
		assert(type(Name) == 'string' and Name ~= '', 'Middleware name required.')
		assert(type(Callback) == 'function', 'Middleware callback must be a function.')
		self._Named[Name] = Callback
	end

	-- Use -> nil
	-- Adds one global middleware callback that runs for every endpoint.
	-- @param Callback, function -> Global validation callback.
	function Middleware:Use(Callback)
		assert(type(Callback) == 'function', 'Middleware callback must be a function.')
		table.insert(self._Global, Callback)
	end

	-- runOne -> boolean, string?
	-- Executes one middleware callback safely.
	-- @param Callback, function -> Middleware function.
	-- @param Context, table -> Request context.
	local function runOne(Callback, Context)
		local Success, Allowed, Reason = pcall(Callback, Context)
		if not Success then return false, 'middleware error' end
		if Allowed == false then return false, Reason or 'middleware rejected request' end
		return true;
	end

	-- Run -> boolean, string?
	-- Runs global then endpoint-specific middleware for one request.
	-- @param Context, table -> Request context.
	-- @param Entries, table? -> Named or function middleware entries.
	function Middleware:Run(Context, Entries)
		for _, Callback in ipairs(self._Global) do
			local Allowed, Reason = runOne(Callback, Context)
			if not Allowed then return false, Reason end
		end

		for _, Entry in ipairs(Entries or {}) do
			local Callback = type(Entry) == 'string' and self._Named[Entry] or Entry
			if type(Callback) ~= 'function' then return false, 'unknown middleware ' .. tostring(Entry) end
			local Allowed, Reason = runOne(Callback, Context)
			if not Allowed then return false, Reason end
		end

		return true;
	end
end

return Middleware;
