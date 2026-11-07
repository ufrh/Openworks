-- Author -> lolokdev.
-- Last Edit -> September 15, 2026 1:55 PM CDT

local RunService = game:GetService('RunService')

local Config = require(script.Parent.Config)
local State = require(script.Parent.State)
local Registry = require(script.Parent.Registry)

local Class = {} do
	local function dependencyList(Definition)
		local Required, Optional, Aliases = {}, {}, {}
		local RequiredSeen, OptionalSeen = {}, {}

		local function add(Source, Target, Seen)
			if type(Source) ~= 'table' then return end
			for Key, Name in pairs(Source) do
				if type(Name) ~= 'string' or Name == '' then continue end
				if not Seen[Name] then
					Seen[Name] = true
					table.insert(Target, Name)
				end
				Aliases[type(Key) == 'string' and Key or Name] = Name
			end
		end

		add(Definition.Dependencies or Definition.Requires, Required, RequiredSeen)
		add(Definition.Uses, Required, RequiredSeen)
		add(Definition.OptionalDependencies, Optional, OptionalSeen)
		add(Definition.Optional, Optional, OptionalSeen)
		return Required, Optional, Aliases
	end

	-- endpointTable -> table
	-- Creates a proxy-backed endpoint namespace so every assignment triggers __newindex, including replacements.
	-- @param Component, table -> Owning FORGE component.
	-- @param Scope, string -> Server or Client namespace.
	local function endpointTable(Component, Scope)
		local Namespace = {}
		local Backing = {}

		local Meta = {}

		-- onAssign -> nil
		-- Tracks endpoint assignments and hot-rebuilds server routes when client methods change.
		-- @param _, table -> Proxy namespace.
		-- @param Key, any -> Assigned endpoint key.
		-- @param Value, any -> Assigned endpoint value.
		local function onAssign(_, Key, Value)
			Backing[Key] = Value
			if type(Key) == 'string' and Component.Kind == 'Service' and Scope == 'Client' then
				Component._RemoteMethods[Key] = type(Value) == 'function' and Value or nil
				if State.Started and State.Bridge and State.Bridge.RebuildRoutes then task.defer(function() State.Bridge:RebuildRoutes() end) end
			end
		end

		Meta.__index = Backing
		Meta.__newindex = onAssign
		setmetatable(Namespace, Meta)

		return Namespace;
	end

	-- ConfigureEndpoint -> table
	-- Applies validation, rate-limit and middleware rules to one client-callable Service endpoint.
	-- @param Name, string -> Endpoint method name.
	-- @param Options, table -> Endpoint security options.
	local function ConfigureEndpoint(self, Name, Options)
		assert(self.Kind == 'Service', 'Only Services can configure client endpoints.')
		assert(type(Name) == 'string' and Name ~= '', 'ConfigureEndpoint requires a method name.')
		assert(type(Options) == 'table', 'ConfigureEndpoint requires an options table.')

		if Options.Transport ~= nil then
			assert(Options.Transport == 'RPC' or Options.Transport == 'Event', 'ConfigureEndpoint Transport must be RPC or Event.')
		end

		local Resolved = table.clone(Options)
		if Resolved.Rate == false then
			Resolved.Rate = {Capacity = Config.Network.GlobalRate.Capacity; Refill = Config.Network.GlobalRate.Refill;}
		end

		self._EndpointOptions[Name] = Resolved
		return self;
	end

	-- CreateSignal -> table
	-- Declares one server-to-client remote signal on a Service.
	-- @param Name, string -> Signal name.
	local function CreateSignal(self, Name)
		assert(self.Kind == 'Service', 'Only Services can declare remote signals.')
		assert(type(Name) == 'string' and Name ~= '', 'CreateSignal requires a signal name.')
		self._RemoteSignals[Name] = true
		if State.Started and State.Bridge and State.Bridge.RebuildRoutes then task.defer(function() State.Bridge:RebuildRoutes() end) end
		return self;
	end

	-- FireClient -> nil
	-- Fires one declared Service signal to one player.
	-- @param Player, Player -> Signal recipient.
	-- @param SignalName, string -> Declared signal name.
	-- @param ..., any -> Signal arguments.
	local function FireClient(self, Player, SignalName, ...)
		assert(self.Kind == 'Service', 'Only Services can fire client signals.')
		assert(self._RemoteSignals[SignalName], 'Unknown remote signal: ' .. tostring(SignalName))
		assert(State.Bridge and State.Bridge.FireClient, 'FORGE server bridge is not active.')
		State.Bridge:FireClient(Player, self.Name, SignalName, ...)
	end

	-- FireAll -> nil
	-- Fires one declared Service signal to every connected player.
	-- @param SignalName, string -> Signal name.
	-- @param ..., any -> Signal arguments.
	local function FireAll(self, SignalName, ...)
		assert(self.Kind == 'Service', 'Only Services can fire client signals.')
		assert(self._RemoteSignals[SignalName], 'Unknown remote signal: ' .. tostring(SignalName))
		assert(State.Bridge and State.Bridge.FireAll, 'FORGE server bridge is not active.')
		State.Bridge:FireAll(self.Name, SignalName, ...)
	end

	-- GetDependency -> table?
	-- Returns an injected dependency by name.
	-- @param Name, string -> Dependency name.
	local function GetDependency(self, Name)
		return self.Dependencies[Name];
	end

	-- Destroy -> nil
	-- Runs optional component cleanup and marks the component destroyed.
	local function Destroy(self)
		if self._Destroyed then return end
		self._Destroyed = true
	end

	-- Create -> table
	-- Creates and registers a Service or Controller using the FORGE class API.
	-- @param Kind, string -> Service or Controller.
	-- @param Definition, table -> Component metadata.
	function Class.Create(Kind, Definition)
		assert(Kind == 'Service' or Kind == 'Controller', 'FORGE.Class kind must be Service or Controller.')
		assert(type(Definition) == 'table', 'FORGE.Class requires a definition table.')
		assert(type(Definition.Name) == 'string' and Definition.Name ~= '', 'FORGE.Class requires Definition.Name.')

		if Kind == 'Service' then assert(RunService:IsServer(), 'Services can only be created on the server.') end
		if Kind == 'Controller' then assert(RunService:IsClient(), 'Controllers can only be created on the client.') end

		local Component = {} do
			Component._FORGEComponent = true
			Component._Destroyed = false
			Component._Initialized = false
			Component._Started = false
			Component._Failed = false
			Component._RemoteMethods = {}
			Component._RemoteSignals = {}
			Component._RemoteStates = {}
			Component._EndpointOptions = {}

			Component.Kind = Kind
			Component.Name = Definition.Name
			Component.Priority = Definition.Priority or 0
			Component._Dependencies, Component._OptionalDependencies, Component._DependencyAliases = dependencyList(Definition)
			Component.Dependencies = {}

			Component.Server = endpointTable(Component, 'Server')
			Component.Client = endpointTable(Component, 'Client')

			Component.ConfigureEndpoint = ConfigureEndpoint
			Component.Secure = ConfigureEndpoint
			Component.CreateSignal = CreateSignal
			Component.FireClient = FireClient
			Component.FireAll = FireAll
			Component.GetDependency = GetDependency
			Component.Destroy = Destroy
		end

		for Key, Value in pairs(Definition) do
			if Key ~= 'Name'
				and Key ~= 'Priority'
				and Key ~= 'Dependencies'
				and Key ~= 'Requires'
				and Key ~= 'Uses'
				and Key ~= 'OptionalDependencies'
				and Key ~= 'Optional'
			then
				Component[Key] = Value
			end
		end

		return Registry.Register(Component);
	end
end

return Class;