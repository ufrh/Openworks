-- Author -> lolokdev.
-- Last Edit -> September 13, 2026 8:44 AM CDT

local Config = require(script.Parent.Parent.Core.Config)

local Protocol = {
	Version = Config.ProtocolVersion,
	Directions = {
		Request = 'C2S',
		Response = 'S2C:R',
		Event = 'S2C:E';
	};
}

return Protocol;
