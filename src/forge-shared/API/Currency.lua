local Currency = {} do
	Currency.__index = Currency
	Currency.ClassName = 'Currency'

	local function getPath(Root, Path)
		local Current = Root
		for Segment in string.gmatch(Path, '[^%.]+') do
			if type(Current) ~= 'table' then return nil end
			Current = Current[Segment]
		end
		return Current
	end

	local function setPath(Root, Path, Value)
		local Parts = {}
		for Segment in string.gmatch(Path, '[^%.]+') do table.insert(Parts, Segment) end
		local Current = Root

		for Index = 1, #Parts - 1 do
			local Key = Parts[Index]
			if type(Current[Key]) ~= 'table' then Current[Key] = {} end
			Current = Current[Key]
		end

		Current[Parts[#Parts]] = Value
	end

	function Currency.new(Name, Options, ResolveProfile)
		Options = Options or {}
		assert(type(Name) == 'string' and Name ~= '', 'FORGE.Currency requires a name.')
		assert(type(ResolveProfile) == 'function', 'FORGE.Currency requires a profile resolver.')

		local self = setmetatable({}, Currency)
		self.Name = Name
		self.Store = Options.Store or 'Player'
		self.Path = Options.Path or ('Currency.' .. Name)
		self._ResolveProfile = ResolveProfile
		return self
	end

	function Currency:_Profile(Player)
		return self._ResolveProfile(Player, {Store = self.Store})
	end

	function Currency:Get(Player)
		local Profile = self:_Profile(Player)
		return Profile and tonumber(Profile:Get(self.Path)) or 0
	end

	function Currency:Set(Player, Amount)
		Amount = math.floor(tonumber(Amount) or 0)
		local Profile = self:_Profile(Player)
		if not Profile then return false, 'profile unavailable' end
		return Profile:Set(self.Path, Amount)
	end

	function Currency:Add(Player, Amount)
		Amount = math.floor(tonumber(Amount) or 0)
		if Amount == 0 then return true, self:Get(Player) end

		local Profile = self:_Profile(Player)
		if not Profile then return false, 'profile unavailable' end
		return Profile:Increment(self.Path, Amount)
	end

	function Currency:CanAfford(Player, Amount)
		Amount = math.max(math.floor(tonumber(Amount) or 0), 0)
		return self:Get(Player) >= Amount
	end

	function Currency:Spend(Player, Amount)
		Amount = math.max(math.floor(tonumber(Amount) or 0), 0)
		if Amount <= 0 then return true, self:Get(Player) end

		local Profile = self:_Profile(Player)
		if not Profile then return false, 'profile unavailable' end

		local Balance
		local Enough = false
		local Success, Reason = Profile:Transaction(function(Draft)
			local Current = tonumber(getPath(Draft, self.Path)) or 0
			if Current < Amount then return false end
			Balance = Current - Amount
			Enough = true
			setPath(Draft, self.Path, Balance)
		end)

		if not Success then
			if not Enough then return false, 'insufficient funds' end
			return false, Reason
		end

		return true, Balance
	end
end

return Currency
