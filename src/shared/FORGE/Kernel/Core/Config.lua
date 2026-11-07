-- Author -> lolokdev.
-- Last Edit -> September 15, 2026 1:55 PM CDT

local RunService = game:GetService('RunService')

local Config = {} do
	Config.Version = '4.4.1'
	Config.ProtocolVersion = 3

	Config.Runtime = {
		Debug = RunService:IsStudio(),
		FailFast = false,
		HotRegistration = true,
		AllowMissingRoots = true;
	}

	Config.Paths = {
		ServerServices = 'Services',
		ClientControllers = 'Controllers';
	}

	Config.Network = {
		FolderName = '__FORGE_NETWORK',
		BootstrapName = 'Bootstrap',

		HandshakeTimeout = 60,
		HandshakeInterval = .35,

		BootstrapRate = {
			Capacity = 60,
			Refill = 20
		},

		ClockSkew = 12,
		MaximumPayloadBytes = 32768,
		MaximumArguments = 32,
		NonceWindow = 64,

		GlobalRate = {
			Capacity = 90,
			Refill = 60;
		},

		DefaultEndpointRate = {
			Capacity = 20,
			Refill = 12;
		};
	}

	Config.Security = {
		RandomizeRemoteNames = true,
		ObfuscatePayloads = true,
		RequireIntegrityTag = true,
		RejectReplay = true;
	}
end

return Config;
