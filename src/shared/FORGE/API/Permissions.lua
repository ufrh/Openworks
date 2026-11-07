local Permissions = {
	Named = {}
}

local function evaluate(Permission, Context)
	if Permission == nil then return true end

	if type(Permission) == 'string' then
		local Callback = Permissions.Named[Permission]
		if not Callback then return false, 'unknown permission ' .. Permission end
		return evaluate(Callback, Context)
	end

	if type(Permission) == 'function' then
		local Success, Allowed, Reason = pcall(Permission, Context.Player, Context)
		if not Success then return false, 'permission check failed' end
		if Allowed == false then return false, Reason or 'permission denied' end
		return true
	end

	if type(Permission) == 'table' then
		if Permission.Any then
			local LastReason
			for _, Entry in ipairs(Permission.Any) do
				local Allowed, Reason = evaluate(Entry, Context)
				if Allowed then return true end
				LastReason = Reason
			end
			return false, LastReason or 'permission denied'
		end

		if Permission.All then
			for _, Entry in ipairs(Permission.All) do
				local Allowed, Reason = evaluate(Entry, Context)
				if not Allowed then return false, Reason end
			end
			return true
		end
	end

	return false, 'invalid permission'
end

function Permissions:Register(Name, Callback)
	assert(type(Name) == 'string' and Name ~= '', 'FORGE.Permission requires a name.')
	assert(type(Callback) == 'function', 'FORGE.Permission requires a callback.')
	self.Named[Name] = Callback
	return Callback
end

function Permissions:Check(Permission, Player, Context)
	Context = Context or {}
	Context.Player = Player or Context.Player
	return evaluate(Permission, Context)
end

function Permissions:Middleware(Permission)
	return function(Context)
		return evaluate(Permission, Context)
	end
end

function Permissions:Apply(Options)
	Options = type(Options) == 'table' and table.clone(Options) or {}
	if Options.Permission == nil then return Options end

	local Middleware = {}
	for _, Entry in ipairs(Options.Middleware or {}) do table.insert(Middleware, Entry) end
	table.insert(Middleware, self:Middleware(Options.Permission))
	Options.Middleware = Middleware
	return Options
end

return Permissions
