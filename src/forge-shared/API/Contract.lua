local Validator = require(script.Parent.Parent.Kernel.Networking.Validator)

local Contract = {} do
	Contract.__index = Contract
	Contract.ClassName = 'Contract'

	local function copy(Value)
		local Result = {}
		for Key, Entry in pairs(Value or {}) do Result[Key] = Entry end
		return Result
	end

	function Contract.new(Schema, Options)
		if Schema and Schema.Type then Schema = {Schema} end
		Schema = Schema or {}
		assert(type(Schema) == 'table', 'FORGE.Contract requires a schema table.')

		local self = setmetatable({}, Contract)
		self._FORGEContract = true
		self.Schema = table.clone(Schema)
		self.Options = copy(Options)
		return self
	end

	function Contract:ToOptions(Overrides)
		local Result = copy(self.Options)
		for Key, Value in pairs(Overrides or {}) do Result[Key] = Value end
		Result.Schema = self.Schema
		return Result
	end

	function Contract:Validate(...)
		local Packed = table.pack(...)
		return Validator.ValidateArguments(Packed, self:ToOptions())
	end

	function Contract:Rate(Capacity, Refill)
		if Capacity == false then
			self.Options.Rate = false
		else
			self.Options.Rate = {
				Capacity = assert(tonumber(Capacity), 'Contract:Rate requires capacity.'),
				Refill = assert(tonumber(Refill), 'Contract:Rate requires refill.')
			}
		end
		return self
	end

	function Contract:Middleware(...)
		self.Options.Middleware = {...}
		return self
	end

	function Contract:AllowExtra(Allowed)
		self.Options.AllowExtraArguments = Allowed ~= false
		return self
	end

	function Contract:Permission(Permission)
		self.Options.Permission = Permission
		return self
	end
end

return Contract
