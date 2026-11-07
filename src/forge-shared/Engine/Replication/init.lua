local Players = game:GetService('Players')
local RunService = game:GetService('RunService')

local Replication = {
	Scopes = {},
	Attributes = {},
	States = setmetatable({}, {__mode = 'k'})
}

local To = {} do
	local function descriptor(Kind, Values)
		Values = Values or {}
		Values._FORGEAudience = true
		Values.Kind = Kind
		return Values
	end

	To.All = descriptor('All')

	function To.Player(Player)
		assert(typeof(Player) == 'Instance' and Player:IsA('Player'), 'FORGE.To.Player requires a Player.')
		return descriptor('Player', {Player = Player})
	end

	function To.Players(PlayersList)
		assert(type(PlayersList) == 'table', 'FORGE.To.Players requires a player list.')
		return descriptor('Players', {Players = table.clone(PlayersList)})
	end

	setmetatable(To, {
		__index = function(_, Name)
			if not Replication.Scopes[Name] then return nil end
			return function(Key)
				return descriptor('Scope', {
					Scope = Name,
					Key = Key
				})
			end
		end
	})
end

Replication.To = To

local function attributeName(Name)
	return Replication.Attributes[Name] or ('FORGE_' .. Name)
end

local function scopeValue(Player, Name)
	local Resolver = Replication.Scopes[Name]
	if type(Resolver) == 'function' then return Resolver(Player) end
	return Player:GetAttribute(attributeName(Name))
end

function Replication:RegisterScope(Name, Resolver)
	assert(type(Name) == 'string' and Name ~= '', 'Replication scope requires a name.')
	assert(Resolver == nil or type(Resolver) == 'function' or type(Resolver) == 'string', 'Replication scope resolver must be a function or attribute name.')

	if type(Resolver) == 'string' then
		self.Attributes[Name] = Resolver
		self.Scopes[Name] = true
	else
		self.Scopes[Name] = Resolver or true
	end

	return self
end

function Replication:SetScope(Player, Name, Key)
	assert(RunService:IsServer(), 'Replication:SetScope is server-only.')
	assert(typeof(Player) == 'Instance' and Player:IsA('Player'), 'Replication:SetScope requires a Player.')
	assert(self.Scopes[Name], 'Unknown replication scope ' .. tostring(Name) .. '.')
	Player:SetAttribute(attributeName(Name), Key)

	for State in pairs(self.States) do
		if type(State.Refresh) == 'function' then State:Refresh({Player}) end
	end

	return self
end

function Replication:GetScope(Player, Name)
	assert(typeof(Player) == 'Instance' and Player:IsA('Player'), 'Replication:GetScope requires a Player.')
	return scopeValue(Player, Name)
end

function Replication:CanSee(Player, Audience)
	if Audience == nil or Audience == true or Audience == 'All' or Audience == To.All then return true end
	if Audience == false then return false end

	if type(Audience) == 'function' then
		local Success, Result = pcall(Audience, Player)
		if not Success then return false end
		if type(Result) == 'boolean' then return Result end
		return self:CanSee(Player, Result)
	end

	if typeof(Audience) == 'Instance' and Audience:IsA('Player') then return Player == Audience end
	if type(Audience) ~= 'table' then return false end

	if Audience._FORGEAudience then
		if Audience.Kind == 'All' then return true end
		if Audience.Kind == 'Player' then return Player == Audience.Player end

		if Audience.Kind == 'Players' then
			for _, Candidate in ipairs(Audience.Players or {}) do
				if Player == Candidate then return true end
			end
			return false
		end

		if Audience.Kind == 'Scope' then
			return scopeValue(Player, Audience.Scope) == Audience.Key
		end
	end

	for _, Candidate in ipairs(Audience) do
		if Player == Candidate then return true end
	end

	return false
end

function Replication:Recipients(Audience)
	local Result = {}
	for _, Player in ipairs(Players:GetPlayers()) do
		if self:CanSee(Player, Audience) then table.insert(Result, Player) end
	end
	return Result
end

function Replication:RegisterState(State)
	self.States[State] = true
	return State
end

function Replication:UnregisterState(State)
	self.States[State] = nil
end

Replication:RegisterScope('Party', 'FORGE_Party')
Replication:RegisterScope('Match', 'FORGE_Match')

return Replication
