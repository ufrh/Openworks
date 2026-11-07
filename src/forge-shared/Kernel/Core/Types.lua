-- Author -> lolokdev.
-- Last Edit -> September 13, 2026 8:44 AM CDT

local Types = {} do
	-- descriptor -> table
	-- Creates one validation descriptor.
	-- @param Name, string -> Descriptor type name.
	-- @param Options, table? -> Validation options.
	local function descriptor(Name, Options)
		local Result = Options or {}
		Result.Type = Name
		return Result;
	end

	-- Any -> table
	-- Accepts any serializable value.
	-- @param Options, table? -> Validation options.
	function Types.Any(Options)
		return descriptor('Any', Options);
	end

	-- String -> table
	-- Validates a string argument.
	-- @param Options, table? -> MinLength, MaxLength or Pattern options.
	function Types.String(Options)
		return descriptor('String', Options);
	end

	-- Number -> table
	-- Validates a number argument.
	-- @param Options, table? -> Min, Max or Integer options.
	function Types.Number(Options)
		return descriptor('Number', Options);
	end

	-- Boolean -> table
	-- Validates a boolean argument.
	-- @param Options, table? -> Validation options.
	function Types.Boolean(Options)
		return descriptor('Boolean', Options);
	end

	-- Vector2 -> table
	-- Validates a Vector2 argument.
	-- @param Options, table? -> Magnitude limit options.
	function Types.Vector2(Options)
		return descriptor('Vector2', Options);
	end

	-- Vector3 -> table
	-- Validates a Vector3 argument.
	-- @param Options, table? -> Magnitude limit options.
	function Types.Vector3(Options)
		return descriptor('Vector3', Options);
	end

	-- CFrame -> table
	-- Validates a CFrame argument.
	-- @param Options, table? -> Validation options.
	function Types.CFrame(Options)
		return descriptor('CFrame', Options);
	end

	-- Color3 -> table
	-- Validates a Color3 argument.
	-- @param Options, table? -> Validation options.
	function Types.Color3(Options)
		return descriptor('Color3', Options);
	end

	-- Table -> table
	-- Validates a table argument and optional size bounds.
	-- @param Options, table? -> MaxEntries option.
	function Types.Table(Options)
		return descriptor('Table', Options);
	end

	-- Enum -> table
	-- Validates an EnumItem and optional EnumType name.
	-- @param EnumType, Enum -> Expected enum type.
	function Types.Enum(EnumType)
		return descriptor('Enum', {EnumType = EnumType;});
	end

	-- Optional -> table
	-- Makes another descriptor accept nil.
	-- @param Inner, table -> Wrapped descriptor.
	function Types.Optional(Inner)
		return descriptor('Optional', {Inner = Inner;});
	end
end

return Types;
