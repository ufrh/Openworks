-- Author -> lolokdev.
-- Last Edit -> September 13, 2026 8:44 AM CDT

local HttpService = game:GetService('HttpService')

local Config = require(script.Parent.Parent.Core.Config)

local Serializer = {} do
	local MAX_DEPTH = 12
	local MAX_ENTRIES = 1024
	local MAX_STRING = 16384

	-- enumTypeName -> string
	-- Converts an EnumType into the lookup name used by Enum.
	-- @param EnumType, Enum -> Enum type being serialized.
	local function enumTypeName(EnumType)
		return string.gsub(tostring(EnumType), '^Enum%.', '');
	end

	-- encodeValue -> any
	-- Converts Roblox values into JSON-safe tagged values.
	-- @param Value, any -> Value being encoded.
	-- @param Depth, number -> Current recursion depth.
	local function encodeValue(Value, Depth)
		if Depth > MAX_DEPTH then error('Serializer maximum depth exceeded.') end
		local ValueType = typeof(Value)

		if Value == nil then return {__forge = 'nil';} end
		if ValueType == 'boolean' then return Value end
		if ValueType == 'number' then
			if Value ~= Value or Value == math.huge or Value == -math.huge then error('Serializer cannot encode non-finite numbers.') end
			return Value
		end
		if ValueType == 'string' then
			if #Value > MAX_STRING then error('Serializer string limit exceeded.') end
			return Value
		end
		if ValueType == 'Vector2' then return {__forge = 'v2'; x = Value.X; y = Value.Y;} end
		if ValueType == 'Vector3' then return {__forge = 'v3'; x = Value.X; y = Value.Y; z = Value.Z;} end
		if ValueType == 'Color3' then return {__forge = 'c3'; r = Value.R; g = Value.G; b = Value.B;} end
		if ValueType == 'UDim' then return {__forge = 'ud'; s = Value.Scale; o = Value.Offset;} end
		if ValueType == 'UDim2' then return {__forge = 'ud2'; xs = Value.X.Scale; xo = Value.X.Offset; ys = Value.Y.Scale; yo = Value.Y.Offset;} end
		if ValueType == 'CFrame' then return {__forge = 'cf'; v = {Value:GetComponents()};} end
		if ValueType == 'EnumItem' then return {__forge = 'enum'; e = enumTypeName(Value.EnumType); n = Value.Name;} end

		if ValueType == 'table' then
			local Entries = {}
			local Count = 0

			for Key, Item in pairs(Value) do
				Count += 1
				if Count > MAX_ENTRIES then error('Serializer table entry limit exceeded.') end
				table.insert(Entries, {k = encodeValue(Key, Depth + 1); v = encodeValue(Item, Depth + 1);})
			end

			return {__forge = 'table'; entries = Entries;}
		end

		error('Serializer rejected unsupported type ' .. ValueType)
	end

	-- decodeValue -> any
	-- Restores one JSON-safe tagged value back into its Roblox representation.
	-- @param Value, any -> Encoded value.
	-- @param Depth, number -> Current recursion depth.
	local function decodeValue(Value, Depth)
		if Depth > MAX_DEPTH then error('Serializer maximum depth exceeded.') end
		if type(Value) ~= 'table' then return Value end

		local Tag = Value.__forge
		if not Tag then return Value end
		if Tag == 'nil' then return nil end
		if Tag == 'v2' then return Vector2.new(Value.x, Value.y) end
		if Tag == 'v3' then return Vector3.new(Value.x, Value.y, Value.z) end
		if Tag == 'c3' then return Color3.new(Value.r, Value.g, Value.b) end
		if Tag == 'ud' then return UDim.new(Value.s, Value.o) end
		if Tag == 'ud2' then return UDim2.new(Value.xs, Value.xo, Value.ys, Value.yo) end
		if Tag == 'cf' then return CFrame.new(table.unpack(Value.v)) end
		if Tag == 'enum' then
			local EnumType = Enum[Value.e]
			if not EnumType then error('Serializer received unknown enum type.') end
			local Item = EnumType[Value.n]
			if not Item then error('Serializer received unknown enum item.') end
			return Item
		end

		if Tag == 'table' then
			local Result = {}
			local Entries = Value.entries or {}
			if #Entries > MAX_ENTRIES then error('Serializer table entry limit exceeded.') end

			for _, Entry in ipairs(Entries) do
				local Key = decodeValue(Entry.k, Depth + 1)
				local Item = decodeValue(Entry.v, Depth + 1)
				if Key ~= nil then Result[Key] = Item end
			end

			return Result
		end

		error('Serializer received unknown tag ' .. tostring(Tag))
	end

	-- EncodePacked -> string
	-- Serializes a table.pack style argument/result bundle into JSON.
	-- @param Packed, table -> Packed values with n field.
	function Serializer.EncodePacked(Packed)
		local Count = Packed.n or #Packed
		if Count > Config.Network.MaximumArguments then error('Maximum remote argument count exceeded.') end

		local Values = {}
		for Index = 1, Count do Values[Index] = encodeValue(Packed[Index], 0) end
		local JSON = HttpService:JSONEncode({n = Count; values = Values;})
		if #JSON > Config.Network.MaximumPayloadBytes then error('Maximum remote payload size exceeded.') end
		return JSON;
	end

	-- DecodePacked -> table
	-- Decodes JSON into a table.pack style bundle while preserving nil slots.
	-- @param JSON, string -> Encoded payload.
	function Serializer.DecodePacked(JSON)
		if type(JSON) ~= 'string' then error('Serializer expected a string payload.') end
		if #JSON > Config.Network.MaximumPayloadBytes then error('Maximum remote payload size exceeded.') end

		local Decoded = HttpService:JSONDecode(JSON)
		local Count = tonumber(Decoded.n) or 0
		if Count < 0 or Count > Config.Network.MaximumArguments then error('Invalid remote argument count.') end

		local Packed = {n = Count;}
		for Index = 1, Count do Packed[Index] = decodeValue(Decoded.values[Index], 0) end
		return Packed;
	end
end

return Serializer;
