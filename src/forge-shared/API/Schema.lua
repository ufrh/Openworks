local Schema = {} do
	Schema.__index = Schema
	Schema.ClassName = 'Schema'

	local function clone(Value)
		if type(Value) ~= 'table' then return Value end
		local Result = {}
		for Key, Entry in pairs(Value) do Result[Key] = clone(Entry) end
		return Result
	end

	function Schema.Migration(Version, Callback)
		assert(type(Version) == 'number' and Version >= 1 and Version % 1 == 0, 'FORGE.Migration requires a positive integer version.')
		assert(type(Callback) == 'function', 'FORGE.Migration requires a callback.')
		return {
			_FORGEMigration = true,
			Version = Version,
			Callback = Callback
		}
	end

	function Schema.new(Definition)
		assert(type(Definition) == 'table', 'FORGE.Schema requires a definition table.')

		local Result = clone(Definition)
		local Migrations = {}

		for Key, Entry in pairs(Result.Migrations or {}) do
			if type(Entry) == 'table' and Entry._FORGEMigration then
				Migrations[Entry.Version] = Entry.Callback
			elseif type(Key) == 'number' and type(Entry) == 'function' then
				Migrations[Key] = Entry
			end
		end

		Result.Migrations = Migrations
		Result._FORGESchema = true
		return Result
	end
end

return Schema
