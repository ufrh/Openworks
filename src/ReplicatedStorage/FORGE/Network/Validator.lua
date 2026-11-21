-- Author -> lolokdev.
-- Last Edit -> September 15, 2026 1:58 PM CDT

local Validator = {} do
	-- finite -> boolean
	-- Checks whether a number is finite and not NaN.
	-- @param Value, any -> Candidate number.
	local function finite(Value)
		return type(Value) == 'number' and Value == Value and Value < math.huge and Value > -math.huge;
	end

	-- tableSize -> number
	-- Counts keys in a table without trusting the length operator.
	-- @param Value, table -> Table being counted.
	local function tableSize(Value)
		local Count = 0
		for _ in pairs(Value) do Count += 1 end
		return Count;
	end

	-- ValidateValue -> boolean, string?
	-- Validates one decoded remote argument against a FORGE descriptor.
	-- @param Value, any -> Decoded value.
	-- @param Descriptor, table -> FORGE.Types descriptor.
	function Validator.ValidateValue(Value, Descriptor)
		if not Descriptor or Descriptor.Type == 'Any' then return true end

		if Descriptor.Type == 'Optional' then
			if Value == nil then return true end
			return Validator.ValidateValue(Value, Descriptor.Inner)
	end

		if Descriptor.Type == 'String' then
			if type(Value) ~= 'string' then return false, 'expected string' end
			if Descriptor.MinLength and #Value < Descriptor.MinLength then return false, 'string shorter than minimum' end
			if Descriptor.MaxLength and #Value > Descriptor.MaxLength then return false, 'string longer than maximum' end
			if Descriptor.Pattern and not string.match(Value, Descriptor.Pattern) then return false, 'string failed pattern' end
			return true
		end

		if Descriptor.Type == 'Number' then
			if not finite(Value) then return false, 'expected finite number' end
			if Descriptor.Integer and Value % 1 ~= 0 then return false, 'expected integer' end
			if Descriptor.Min and Value < Descriptor.Min then return false, 'number below minimum' end
			if Descriptor.Max and Value > Descriptor.Max then return false, 'number above maximum' end
			return true
		end

		if Descriptor.Type == 'Boolean' then
			return type(Value) == 'boolean', 'expected boolean'
		end

		if Descriptor.Type == 'Vector2' then
			if typeof(Value) ~= 'Vector2' then return false, 'expected Vector2' end
			if Descriptor.MaxMagnitude and Value.Magnitude > Descriptor.MaxMagnitude then return false, 'Vector2 magnitude exceeded' end
			return true
		end

		if Descriptor.Type == 'Vector3' then
			if typeof(Value) ~= 'Vector3' then return false, 'expected Vector3' end
			if Descriptor.MaxMagnitude and Value.Magnitude > Descriptor.MaxMagnitude then return false, 'Vector3 magnitude exceeded' end
			return true
		end

		if Descriptor.Type == 'CFrame' then
			return typeof(Value) == 'CFrame', 'expected CFrame'
		end

		if Descriptor.Type == 'Color3' then
			return typeof(Value) == 'Color3', 'expected Color3'
		end

		if Descriptor.Type == 'Table' then
			if type(Value) ~= 'table' then return false, 'expected table' end
			if Descriptor.MaxEntries and tableSize(Value) > Descriptor.MaxEntries then return false, 'table entry limit exceeded' end
			return true
		end

		if Descriptor.Type == 'Enum' then
			if typeof(Value) ~= 'EnumItem' then return false, 'expected EnumItem' end
			if Descriptor.EnumType and Value.EnumType ~= Descriptor.EnumType then return false, 'wrong EnumType' end
			return true
		end

		return false, 'unknown descriptor type ' .. tostring(Descriptor.Type)
	end

	-- ValidateArguments -> boolean, string?
	-- Validates a packed argument list against endpoint schema configuration.
	-- @param Packed, table -> Packed arguments with n field.
	-- @param Options, table? -> Endpoint security options.
	function Validator.ValidateArguments(Packed, Options)
		Options = Options or {}

		local Schema = Options.Schema or Options.Arguments

		if Schema then
			local Count = Packed.n or 0

			if not Options.AllowExtraArguments and Count > #Schema then
				return false, 'too many arguments';
			end

			for Index, Descriptor in ipairs(Schema) do
				local Valid, Reason = Validator.ValidateValue(Packed[Index], Descriptor)

				if not Valid then
					return false, string.format('argument %d: %s', Index, Reason or 'invalid');
				end
			end
		end

		if Options.Validate then
			local Success, Result, Reason = pcall(Options.Validate, Packed)

			if not Success then
				return false, 'custom validator errored';
			end

			if Result == false then
				return false, Reason or 'custom validator rejected request';
			end
		end

		return true;
	end
end

return Validator;
