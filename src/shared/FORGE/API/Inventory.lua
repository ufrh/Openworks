local Inventory = {} do
	Inventory.__index = Inventory
	Inventory.ClassName = 'Inventory'

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

	function Inventory.new(Name, Options, ResolveProfile)
		Options = Options or {}
		assert(type(Name) == 'string' and Name ~= '', 'FORGE.Inventory requires a name.')
		assert(type(ResolveProfile) == 'function', 'FORGE.Inventory requires a profile resolver.')

		local self = setmetatable({}, Inventory)
		self.Name = Name
		self.Store = Options.Store or 'Player'
		self.OwnedPath = Options.Owned or Options.Path or 'Inventory.Owned'
		self.EquippedPath = Options.Equipped or 'Inventory.Equipped'
		self._ResolveProfile = ResolveProfile
		return self
	end

	function Inventory:_Profile(Player)
		return self._ResolveProfile(Player, {Store = self.Store})
	end

	function Inventory:GetOwned(Player)
		local Profile = self:_Profile(Player)
		return Profile and Profile:Get(self.OwnedPath) or {}
	end

	function Inventory:GetEquipped(Player)
		local Profile = self:_Profile(Player)
		return Profile and Profile:Get(self.EquippedPath) or {}
	end

	function Inventory:Has(Player, Item)
		local Owned = self:GetOwned(Player)
		return Owned[Item] == true
	end

	function Inventory:Grant(Player, Item)
		assert(type(Item) == 'string' and Item ~= '', 'Inventory:Grant requires an item id.')
		local Profile = self:_Profile(Player)
		if not Profile then return false, 'profile unavailable' end

		local Owned = Profile:Get(self.OwnedPath) or {}
		if Owned[Item] == true then return true, false end
		Owned[Item] = true

		local Success, Reason = Profile:Set(self.OwnedPath, Owned)
		if not Success then return false, Reason end
		return true, true
	end

	function Inventory:Remove(Player, Item)
		assert(type(Item) == 'string' and Item ~= '', 'Inventory:Remove requires an item id.')
		local Profile = self:_Profile(Player)
		if not Profile then return false, 'profile unavailable' end

		local Owned = Profile:Get(self.OwnedPath) or {}
		if Owned[Item] ~= true then return true, false end
		Owned[Item] = nil

		local Equipped = Profile:Get(self.EquippedPath) or {}
		for Slot, EquippedItem in pairs(Equipped) do
			if EquippedItem == Item then Equipped[Slot] = nil end
		end

		return Profile:Transaction(function(Draft)
			setPath(Draft, self.OwnedPath, Owned)
			setPath(Draft, self.EquippedPath, Equipped)
		end)
	end

	function Inventory:Equip(Player, Slot, Item)
		assert(type(Slot) == 'string' and Slot ~= '', 'Inventory:Equip requires a slot.')
		assert(type(Item) == 'string' and Item ~= '', 'Inventory:Equip requires an item id.')

		local Profile = self:_Profile(Player)
		if not Profile then return false, 'profile unavailable' end
		if not self:Has(Player, Item) then return false, 'item not owned' end

		local Equipped = Profile:Get(self.EquippedPath) or {}
		Equipped[Slot] = Item
		return Profile:Set(self.EquippedPath, Equipped)
	end

	function Inventory:Unequip(Player, Slot)
		assert(type(Slot) == 'string' and Slot ~= '', 'Inventory:Unequip requires a slot.')

		local Profile = self:_Profile(Player)
		if not Profile then return false, 'profile unavailable' end

		local Equipped = Profile:Get(self.EquippedPath) or {}
		Equipped[Slot] = nil
		return Profile:Set(self.EquippedPath, Equipped)
	end
end

return Inventory
