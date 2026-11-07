-- Author -> lolokdev.
-- Last Edit -> September 13, 2026 8:44 AM CDT

local bit32 = bit32

local Config = require(script.Parent.Parent.Core.Config)

local SecurityCodec = {} do
	local MOD = 4294967296

	-- hash32 -> number
	-- Produces a deterministic 32-bit hash using XOR and shift-add mixing.
	-- @param Value, string -> Input string.
	local function hash32(Value)
		local Hash = 2166136261

		for Index = 1, #Value do
			Hash = bit32.bxor(Hash, string.byte(Value, Index))
			Hash = bit32.band(Hash + bit32.lshift(Hash, 1) + bit32.lshift(Hash, 4) + bit32.lshift(Hash, 7) + bit32.lshift(Hash, 8) + bit32.lshift(Hash, 24), 0xffffffff)
		end

		return Hash % MOD;
	end

	-- nextState -> number
	-- Advances the deterministic XOR stream state.
	-- @param State, number -> Current 32-bit state.
	local function nextState(State)
		State = bit32.bxor(State, bit32.lshift(State, 13))
		State = bit32.bxor(State, bit32.rshift(State, 17))
		State = bit32.bxor(State, bit32.lshift(State, 5))
		return bit32.band(State, 0xffffffff);
	end

	-- toHex -> string
	-- Converts a binary string into lowercase hexadecimal.
	-- @param Value, string -> Binary string.
	local function toHex(Value)
		local Result = table.create(#Value)
		for Index = 1, #Value do Result[Index] = string.format('%02x', string.byte(Value, Index)) end
		return table.concat(Result);
	end

	-- fromHex -> string
	-- Converts lowercase or uppercase hexadecimal back into bytes.
	-- @param Value, string -> Hexadecimal string.
	local function fromHex(Value)
		if #Value % 2 ~= 0 then error('Invalid hexadecimal payload.') end
		local Result = table.create(#Value / 2)

		for Index = 1, #Value, 2 do
			local Byte = tonumber(string.sub(Value, Index, Index + 1), 16)
			if not Byte then error('Invalid hexadecimal payload.') end
			Result[#Result + 1] = string.char(Byte)
		end

		return table.concat(Result);
	end

	-- xorBytes -> string
	-- Applies the per-packet deterministic XOR stream.
	-- @param Value, string -> Plain or encrypted bytes.
	-- @param Key, string -> Session token.
	-- @param Nonce, number -> Monotonic packet nonce.
	-- @param Direction, string -> Protocol direction identifier.
	local function xorBytes(Value, Key, Nonce, Direction)
		local State = hash32(Key .. '|' .. tostring(Nonce) .. '|' .. Direction)
		if State == 0 then State = 2463534242 end

		local Result = table.create(#Value)
		for Index = 1, #Value do
			State = nextState(State)
			Result[Index] = string.char(bit32.bxor(string.byte(Value, Index), bit32.band(State, 0xff)))
		end

		return table.concat(Result);
	end

	-- Hash -> string
	-- Exposes a compact deterministic route/name hash.
	-- @param Value, string -> Input string.
	function SecurityCodec.Hash(Value)
		local A = hash32('A|' .. Value)
		local B = hash32('B|' .. Value)
		return string.format('%08x%08x', A, B);
	end

	-- Encode -> string
	-- Obfuscates a serialized payload for this session packet.
	-- @param Plaintext, string -> Serialized payload.
	-- @param Key, string -> Per-player session token.
	-- @param Nonce, number -> Packet nonce.
	-- @param Direction, string -> Protocol direction.
	function SecurityCodec.Encode(Plaintext, Key, Nonce, Direction)
		if not Config.Security.ObfuscatePayloads then return Plaintext end
		return toHex(xorBytes(Plaintext, Key, Nonce, Direction));
	end

	-- Decode -> string
	-- Reverses session payload obfuscation.
	-- @param Payload, string -> Encoded payload.
	-- @param Key, string -> Per-player session token.
	-- @param Nonce, number -> Packet nonce.
	-- @param Direction, string -> Protocol direction.
	function SecurityCodec.Decode(Payload, Key, Nonce, Direction)
		if not Config.Security.ObfuscatePayloads then return Payload end
		return xorBytes(fromHex(Payload), Key, Nonce, Direction);
	end

	-- Tag -> string
	-- Creates a keyed packet integrity tag tied to route, time, nonce and payload.
	-- @param Key, string -> Per-player session token.
	-- @param Nonce, number -> Packet nonce.
	-- @param Timestamp, number -> Synced server timestamp.
	-- @param Route, string -> Opaque route id.
	-- @param Payload, string -> Encoded payload.
	-- @param Direction, string -> Protocol direction.
	function SecurityCodec.Tag(Key, Nonce, Timestamp, Route, Payload, Direction)
		local Canonical = table.concat({Key, tostring(Nonce), string.format('%.3f', Timestamp), Route, Direction, Payload;}, '|')
		return SecurityCodec.Hash(Canonical);
	end

	-- Equal -> boolean
	-- Compares two integrity tags without early exiting on the first mismatch.
	-- @param A, string -> First tag.
	-- @param B, string -> Second tag.
	function SecurityCodec.Equal(A, B)
		if type(A) ~= 'string' or type(B) ~= 'string' or #A ~= #B then return false end
		local Difference = 0
		for Index = 1, #A do Difference = bit32.bor(Difference, bit32.bxor(string.byte(A, Index), string.byte(B, Index))) end
		return Difference == 0;
	end
end

return SecurityCodec;
