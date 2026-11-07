-- Author -> lolokdev.
-- Last Edit -> September 13, 2026 8:44 AM CDT

local RunService = game:GetService('RunService')

local State = {
	Environment = RunService:IsServer() and 'Server' or 'Client',
	Registered = {},
	Order = {},
	Bridge = nil,
	Started = false,
	Starting = false,
	Roots = {},
	Connections = {},

	BootReport = {
		Loaded = {},
		Initialized = {},
		Started = {},
		Skipped = {},
		Errors = {};
	};
}

return State;
