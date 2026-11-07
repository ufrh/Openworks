local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local ServerScriptService = game:GetService('ServerScriptService')

local Root = script

local function RequireChild(Parent, Name)
	local Child = Parent:FindFirstChild(Name) or Parent:WaitForChild(Name, 5)
	if Child then return Child end

	error(string.format(
		'FORGE source tree is incomplete: %s is missing %q. Pull the latest dev branch, restart the RUCKUS Rojo servers, and reconnect the correct place port.',
		Parent:GetFullName(),
		Name
	), 2)
end

local APIRoot = RequireChild(Root, 'API')
local KernelRoot = RequireChild(Root, 'Kernel')
local EngineRoot = RequireChild(Root, 'Engine')
local CoreRoot = RequireChild(KernelRoot, 'Core')
local NetworkRoot = RequireChild(KernelRoot, 'Networking')
local GameplayRoot = RequireChild(EngineRoot, 'Gameplay')

local KernelConfig = require(CoreRoot.Config)
local RuntimeState = require(CoreRoot.State)
local Class = require(CoreRoot.Class)
local Registry = require(CoreRoot.Registry)
local Loader = require(CoreRoot.Loader)
local DependencyGraph = require(CoreRoot.DependencyGraph)
local Lifecycle = require(CoreRoot.Lifecycle)
local Logger = require(CoreRoot.Logger)
local Signal = require(CoreRoot.Signal)
local Janitor = require(CoreRoot.Janitor)
local Types = require(CoreRoot.Types)
local ClientBridge = require(NetworkRoot.ClientBridge)

local Context = require(APIRoot.Context)
local Scope = require(APIRoot.Scope)
local Contract = require(APIRoot.Contract)
local Event = require(APIRoot.Event)
local StateAPI = require(APIRoot.State)
local Permissions = require(APIRoot.Permissions)
local ConfigAPI = require(APIRoot.Config)
local Diagnostics = require(APIRoot.Diagnostics)
local ProfileAPI = require(APIRoot.Profile)
local CurrencyAPI = require(APIRoot.Currency)
local InventoryAPI = require(APIRoot.Inventory)
local SchemaAPI = require(APIRoot.Schema)

local Avatar = require(GameplayRoot.Avatar)
local Progression = require(GameplayRoot.Progression)
local Replication = require(EngineRoot.Replication)
local Tooling = require(EngineRoot.Tooling)
local UI = require(EngineRoot.UI)

local function Callable(Module)
	return setmetatable({}, {
		__index = Module,
		__call = function(_, ...)
			return Module.new(...)
		end
	})
end

local function Definition(Name, Options)
	if type(Name) == 'table' then
		Options = Name
		Name = Options.Name
	end

	local Result = type(Options) == 'table' and table.clone(Options) or {}
	Result.Name = Name or Result.Name
	assert(type(Result.Name) == 'string' and Result.Name ~= '', 'FORGE component requires a name.')
	return Result
end

local PublicConfig = ConfigAPI.new(KernelConfig, Context)

local FORGE = {} do
	FORGE.Version = KernelConfig.Version
	FORGE.Context = Context
	FORGE.Config = PublicConfig
	FORGE.Types = Types
	FORGE.Type = Types

	FORGE.Signal = Callable(Signal)
	FORGE.State = Callable(StateAPI)
	FORGE.Scope = Callable(Scope)
	FORGE.Contract = Callable(Contract)
	FORGE.Event = Callable(Event)

	FORGE.Any = Types.Any
	FORGE.String = Types.String
	FORGE.Number = Types.Number
	FORGE.Boolean = Types.Boolean
	FORGE.Vector2 = Types.Vector2
	FORGE.Vector3 = Types.Vector3
	FORGE.CFrame = Types.CFrame
	FORGE.Color3 = Types.Color3
	FORGE.Table = Types.Table
	FORGE.Enum = Types.Enum
	FORGE.Maybe = Types.Optional

	FORGE.IsServer = Context.Server
	FORGE.IsClient = Context.Client
	FORGE.IsStudio = Context.Studio
	FORGE.IsProduction = Context.Production

	FORGE.Janitor = Janitor
	FORGE.UI = UI
	FORGE.Replication = Replication
	FORGE.Tooling = Tooling
	FORGE.To = Replication.To
	FORGE.Permissions = Permissions
	FORGE.Avatar = Avatar
	FORGE.Progression = Progression
	FORGE.Data = nil
	FORGE.Matchmaking = nil

	FORGE.Kernel = {
		Config = KernelConfig,
		Types = Types,
		Registry = Registry,
		Loader = Loader,
		Lifecycle = Lifecycle,
		Logger = Logger,
		Signal = Signal,
		Janitor = Janitor
	}

	FORGE.Engine = {
		UI = UI,
		Replication = Replication,
		Tooling = Tooling,
		Avatar = Avatar,
		Progression = Progression,
		Data = nil,
		Matchmaking = nil
	}

	FORGE.Diagnostics = Diagnostics.new(FORGE.Version, Context, Tooling)

	FORGE.Simulate = Tooling.Simulate
	FORGE.Tests = {
		Run = function(_, Filter)
			return Tooling:RunTests(Filter)
		end,
		Snapshot = function()
			return Tooling:Snapshot().Tests
		end
	}

	function FORGE.Metric(SelfOrName, MaybeName)
		local Name = SelfOrName == FORGE and MaybeName or SelfOrName
		return Tooling:Metric(Name)
	end

	function FORGE.Pulse(SelfOrSource, Kind, Target, Fields)
		local Source
		if SelfOrSource == FORGE then
			Source = 'Runtime'
		else
			Source = SelfOrSource
		end
		return Tooling:Pulse(Source, Kind, Target, Fields)
	end

	function FORGE.Trace(SelfOrName, ...)
		if SelfOrName == FORGE then return Tooling:Trace(...) end
		return Tooling:Trace(SelfOrName, ...)
	end

	function FORGE.Test(SelfOrName, NameOrCallback, CallbackOrOptions, MaybeOptions)
		local Name, Callback, Options
		if SelfOrName == FORGE then
			Name, Callback, Options = NameOrCallback, CallbackOrOptions, MaybeOptions
		else
			Name, Callback, Options = SelfOrName, NameOrCallback, CallbackOrOptions
		end
		return Tooling:RegisterTest(Name, Callback, Options)
	end

	function FORGE.Graph()
		return FORGE.Diagnostics:Graph()
	end

	function FORGE.Health()
		return FORGE.Diagnostics:Health()
	end

	local ServerSubsystemsLoaded = false
	local RuntimeDestroyed = false
	local ServerProfiles = setmetatable({}, {__mode = 'k'})
	local ClientProfiles = {}
	local Currencies = {}
	local Inventories = {}
	local ClientDataService
	local ClientDataConnection

	local function Copy(Value, Seen)
		if type(Value) ~= 'table' then return Value end
		Seen = Seen or {}
		if Seen[Value] then return Seen[Value] end

		local Result = {}
		Seen[Value] = Result
		for Key, Entry in pairs(Value) do Result[Copy(Key, Seen)] = Copy(Entry, Seen) end
		return Result
	end

	local function PathGet(RootValue, DataPath)
		local Current = RootValue
		for Segment in string.gmatch(tostring(DataPath or ''), '[^%.]+') do
			if type(Current) ~= 'table' then return nil end
			Current = Current[Segment]
		end
		return Current
	end

	local function CallArguments(SelfOrValue, ValueOrOptions, Options)
		if SelfOrValue == FORGE then return ValueOrOptions, Options end
		return SelfOrValue, ValueOrOptions
	end

	local function AttachScope(Component)
		if Component._Scope then return Component end

		local ComponentScope = Scope.new()
		Component._Scope = ComponentScope
		Component.Scope = ComponentScope

		function Component:Track(Object, Method)
			return ComponentScope:Add(Object, Method)
		end

		local function activity(Kind, Target)
			Tooling:Pulse(Component.Name, Kind, Target)
		end

		function Component:Connect(Source, Callback)
			return ComponentScope:Connect(Source, function(...)
				activity('Signal', typeof(Source))
				return Callback(...)
			end)
		end

		function Component:After(Delay, Callback)
			return ComponentScope:After(Delay, function(...)
				activity('Timer', 'After')
				return Callback(...)
			end)
		end

		function Component:Every(Interval, Callback, Immediate)
			return ComponentScope:Every(Interval, function(...)
				activity('Timer', 'Every')
				return Callback(...)
			end, Immediate)
		end

		function Component:Spawn(Callback, ...)
			local Args = table.pack(...)
			return ComponentScope:Spawn(function()
				activity('Task', 'Spawn')
				return Callback(table.unpack(Args, 1, Args.n))
			end)
		end

		return Component
	end

	local function EndpointOptions(Value)
		if type(Value) == 'table' and Value._FORGEContract and type(Value.ToOptions) == 'function' then
			Value = Value:ToOptions()
		end
		return Permissions:Apply(type(Value) == 'table' and Value or {})
	end

	local function EnhanceService(Component)
		if Component.Expose then return Component end
		AttachScope(Component)

		function Component:Expose(Name, Options)
			assert(type(Name) == 'string' and Name ~= '', 'Service:Expose requires a method name.')
			local Method = self[Name]
			assert(type(Method) == 'function', 'Service:Expose could not find method ' .. Name .. '.')

			self.Client[Name] = function(Player, ...)
				Tooling:Pulse(self.Name, 'Endpoint', Name, {Direction = 'Inbound'})
				return Method(self, Player, ...)
			end

			Options = EndpointOptions(Options)
			if Options then self:ConfigureEndpoint(Name, Options) end
			return self
		end

		function Component:Event(Name, Options)
			assert(type(Name) == 'string' and Name ~= '', 'Service:Event requires a name.')
			local Value = Event.new(Options)
			Value:_Attach(self, Name)
			rawset(self, Name, Value)
			return Value
		end

		local Meta = getmetatable(Component) or {}
		Meta.__newindex = function(Self, Key, Value)
			if type(Value) == 'table' and type(Value._Attach) == 'function' then
				if Value._FORGEEvent or Value._FORGEReplicatedState then Value:_Attach(Self, Key) end
			end
			rawset(Self, Key, Value)
		end
		setmetatable(Component, Meta)
		return Component
	end

	local function EnhanceController(Component)
		return AttachScope(Component)
	end

	local function LoadServerSubsystems()
		if not RunService:IsServer() or ServerSubsystemsLoaded then return end

		local ServerRoot = ServerScriptService:FindFirstChild('FORGE') or ServerScriptService:WaitForChild('FORGE', 3)
		assert(ServerRoot, 'FORGE server folder is missing from ServerScriptService.')

		local ServerEngine = ServerRoot:FindFirstChild('Engine') or ServerRoot:WaitForChild('Engine', 3)
		assert(ServerEngine, 'FORGE Engine is missing from ServerScriptService.FORGE.')

		local DataRoot = ServerEngine:FindFirstChild('Data') or ServerEngine:WaitForChild('Data', 3)
		local MatchmakingRoot = ServerEngine:FindFirstChild('Matchmaking') or ServerEngine:WaitForChild('Matchmaking', 3)

		assert(DataRoot, 'FORGE.Engine.Data is missing from ServerScriptService.FORGE.Engine.')
		assert(MatchmakingRoot, 'FORGE.Engine.Matchmaking is missing from ServerScriptService.FORGE.Engine.')

		FORGE.Data = require(DataRoot)
		FORGE.Matchmaking = require(MatchmakingRoot)
		FORGE.Engine.Data = FORGE.Data
		FORGE.Engine.Matchmaking = FORGE.Matchmaking

		local ProjectData = ServerScriptService:FindFirstChild('Data')
		local Stores = ProjectData and ProjectData:FindFirstChild('Stores')
		if Stores then FORGE.Data.Load(Stores) end

		ServerSubsystemsLoaded = true
	end

	local function ServerAdapter(Raw, StoreName)
		return {
			ReadOnly = false,
			Raw = Raw,
			Store = StoreName,
			UserId = Raw.UserId,
			Changed = Raw.Changed,

			Get = function(_, Path)
				return Raw:Get(Path)
			end,

			Has = function(_, Path)
				return Raw:Has(Path)
			end,

			Set = function(_, Path, Value)
				return Raw:Set(Path, Value)
			end,

			Increment = function(_, Path, Delta)
				return Raw:Increment(Path, Delta)
			end,

			Update = function(_, Path, Callback)
				return Raw:Update(Path, Callback)
			end,

			Transaction = function(_, Callback)
				return Raw:Transaction(Callback)
			end,

			Snapshot = function()
				return Raw:Snapshot()
			end,

			Save = function()
				return Raw:Save()
			end
		}
	end

	local function ClientAdapter(StoreName, UserId, Snapshot)
		local Adapter = {
			ReadOnly = true,
			Store = StoreName,
			UserId = UserId,
			Changed = Signal.new(),
			_Data = Copy(Snapshot or {})
		}

		function Adapter:Get(Path)
			return Copy(PathGet(self._Data, Path))
		end

		function Adapter:Has(Path)
			return PathGet(self._Data, Path) ~= nil
		end

		function Adapter:Snapshot()
			return Copy(self._Data)
		end

		function Adapter:Replace(Snapshot)
			local Previous = self._Data
			self._Data = Copy(Snapshot or {})
			self.Changed:Fire('*', Copy(self._Data), Copy(Previous))
		end

		return Adapter
	end

	local function GetClientDataService()
		if ClientDataService then return ClientDataService end
		assert(RuntimeState.Bridge, 'FORGE is not started.')

		ClientDataService = RuntimeState.Bridge:GetService('__FORGE_DATA')
		ClientDataConnection = ClientDataService.Changed:Connect(function(StoreName, Snapshot)
			local Entry = ClientProfiles[StoreName]
			if Entry then Entry.Adapter:Replace(Snapshot) end
		end)

		return ClientDataService
	end

	local function ResolveProfile(Player, Options)
		Options = type(Options) == 'table' and Options or {}
		local StoreName = Options.Store or 'Player'

		if RunService:IsServer() then
			LoadServerSubsystems()

			local Store = FORGE.Engine.Data.GetStore(StoreName)
			assert(Store, 'FORGE.Profile could not find data store ' .. tostring(StoreName) .. '.')

			local Raw = Store:GetProfile(Player)
			if not Raw and Options.Wait ~= false then
				Raw = Store:WaitForProfile(Player, tonumber(Options.Timeout) or 30)
			end
			if not Raw then return nil end

			local Existing = ServerProfiles[Raw]
			if Existing then return Existing end

			local Created = ProfileAPI.new(ServerAdapter(Raw, StoreName))
			ServerProfiles[Raw] = Created
			return Created
		end

		local LocalPlayer = Players.LocalPlayer
		Player = Player or LocalPlayer
		assert(Player == LocalPlayer, 'Client FORGE.Profile can only read the local player profile.')

		local Existing = ClientProfiles[StoreName]
		if Existing then return Existing.Profile end

		local Service = GetClientDataService()
		local Snapshot = Service:Get(StoreName)
		if Snapshot == nil then return nil end

		local Adapter = ClientAdapter(StoreName, LocalPlayer and LocalPlayer.UserId or 0, Snapshot)
		local Created = ProfileAPI.new(Adapter)
		ClientProfiles[StoreName] = {
			Adapter = Adapter,
			Profile = Created
		}
		return Created
	end

	local function DisconnectRuntimeConnections()
		for _, Connection in ipairs(RuntimeState.Connections) do Connection:Disconnect() end
		table.clear(RuntimeState.Connections)
	end

	local function ResetBootReport()
		for _, Group in pairs(RuntimeState.BootReport) do
			if type(Group) == 'table' then table.clear(Group) end
		end
	end

	function FORGE.Service(SelfOrName, NameOrOptions, Options)
		assert(RunService:IsServer(), 'FORGE.Service is server-only.')
		local Name, DefinitionOptions = CallArguments(SelfOrName, NameOrOptions, Options)
		return EnhanceService(Class.Create('Service', Definition(Name, DefinitionOptions)))
	end

	function FORGE.Controller(SelfOrName, NameOrOptions, Options)
		assert(RunService:IsClient(), 'FORGE.Controller is client-only.')
		local Name, DefinitionOptions = CallArguments(SelfOrName, NameOrOptions, Options)
		return EnhanceController(Class.Create('Controller', Definition(Name, DefinitionOptions)))
	end

	function FORGE.Class(Kind, Options)
		return Class.Create(Kind, Options)
	end

	function FORGE.Get(SelfOrName, MaybeName)
		local Name = SelfOrName == FORGE and MaybeName or SelfOrName
		assert(type(Name) == 'string' and Name ~= '', 'FORGE:Get requires a name.')

		local Local = Registry.Get(Name)
		if Local then return Local end

		if RunService:IsClient() then
			assert(RuntimeState.Bridge, 'FORGE is not started.')
			return RuntimeState.Bridge:GetService(Name)
		end

		return nil
	end

	function FORGE.Find(SelfOrName, MaybeName)
		local Name = SelfOrName == FORGE and MaybeName or SelfOrName
		assert(type(Name) == 'string' and Name ~= '', 'FORGE:Find requires a name.')

		local Local = Registry.Get(Name)
		if Local then return Local end
		if RunService:IsClient() and RuntimeState.Bridge and RuntimeState.Bridge.FindService then
			return RuntimeState.Bridge:FindService(Name)
		end
		return nil
	end

	function FORGE.GetService(SelfOrName, MaybeName)
		local Name = SelfOrName == FORGE and MaybeName or SelfOrName
		if RunService:IsServer() then return Registry.GetService(Name) end
		assert(RuntimeState.Bridge, 'FORGE is not started.')
		return RuntimeState.Bridge:GetService(Name)
	end

	function FORGE.GetController(SelfOrName, MaybeName)
		local Name = SelfOrName == FORGE and MaybeName or SelfOrName
		return Registry.GetController(Name)
	end

	function FORGE.Profile(SelfOrPlayer, PlayerOrOptions, MaybeOptions)
		local Player, Options

		if SelfOrPlayer == FORGE then
			Player, Options = PlayerOrOptions, MaybeOptions
		elseif typeof(SelfOrPlayer) == 'Instance' then
			Player, Options = SelfOrPlayer, PlayerOrOptions
		elseif type(SelfOrPlayer) == 'table' then
			Player, Options = nil, SelfOrPlayer
		else
			Player, Options = SelfOrPlayer, PlayerOrOptions
		end

		return ResolveProfile(Player, Options)
	end

	function FORGE.Transaction(SelfOrTarget, TargetOrCallback, CallbackOrOptions, MaybeOptions)
		local Target, Callback, Options

		if SelfOrTarget == FORGE then
			Target, Callback, Options = TargetOrCallback, CallbackOrOptions, MaybeOptions
		else
			Target, Callback, Options = SelfOrTarget, TargetOrCallback, CallbackOrOptions
		end

		assert(type(Callback) == 'function', 'FORGE.Transaction requires a callback.')
		local Profile = type(Target) == 'table' and rawget(Target, '_Adapter') and Target or ResolveProfile(Target, Options)
		if not Profile then return false, 'profile unavailable' end
		return Profile:Transaction(Callback)
	end

	function FORGE.Currency(SelfOrName, NameOrOptions, MaybeOptions)
		local Name, Options = CallArguments(SelfOrName, NameOrOptions, MaybeOptions)
		assert(type(Name) == 'string' and Name ~= '', 'FORGE.Currency requires a name.')

		Options = type(Options) == 'table' and Options or {}
		local StoreName = Options.Store or 'Player'
		local Key = StoreName .. '\0' .. Name
		local Existing = Currencies[Key]
		if Existing then return Existing end

		local Created = CurrencyAPI.new(Name, Options, ResolveProfile)
		Currencies[Key] = Created
		return Created
	end

	function FORGE.Inventory(SelfOrName, NameOrOptions, MaybeOptions)
		local Name, Options = CallArguments(SelfOrName, NameOrOptions, MaybeOptions)
		assert(type(Name) == 'string' and Name ~= '', 'FORGE.Inventory requires a name.')

		Options = type(Options) == 'table' and Options or {}
		local StoreName = Options.Store or 'Player'
		local Key = StoreName .. '\0' .. Name
		local Existing = Inventories[Key]
		if Existing then return Existing end

		local Created = InventoryAPI.new(Name, Options, ResolveProfile)
		Inventories[Key] = Created
		return Created
	end

	function FORGE.Schema(SelfOrDefinition, MaybeDefinition)
		local Definition = SelfOrDefinition == FORGE and MaybeDefinition or SelfOrDefinition
		return SchemaAPI.new(Definition)
	end

	function FORGE.Migration(SelfOrVersion, VersionOrCallback, MaybeCallback)
		local Version, Callback
		if SelfOrVersion == FORGE then
			Version, Callback = VersionOrCallback, MaybeCallback
		else
			Version, Callback = SelfOrVersion, VersionOrCallback
		end
		return SchemaAPI.Migration(Version, Callback)
	end

	function FORGE.Permission(SelfOrName, NameOrCallback, MaybeCallback)
		local Name, Callback
		if SelfOrName == FORGE then
			Name, Callback = NameOrCallback, MaybeCallback
		else
			Name, Callback = SelfOrName, NameOrCallback
		end
		return Permissions:Register(Name, Callback)
	end

	function FORGE.Configure(SelfOrValues, MaybeValues)
		local Values = SelfOrValues == FORGE and MaybeValues or SelfOrValues
		return PublicConfig:Merge(Values)
	end

	function FORGE.Inspect()
		return FORGE.Diagnostics:Snapshot()
	end

	function FORGE.Debug()
		return FORGE.Diagnostics:Print()
	end

	function FORGE.GetData()
		assert(RunService:IsServer(), 'FORGE Data is server-only.')
		LoadServerSubsystems()
		return FORGE.Engine.Data
	end

	function FORGE.GetMatchmaking()
		assert(RunService:IsServer(), 'FORGE Matchmaking is server-only.')
		LoadServerSubsystems()
		return FORGE.Engine.Matchmaking
	end

	function FORGE.Queue(SelfOrName, NameOrDefinition, MaybeDefinition)
		assert(RunService:IsServer(), 'FORGE.Queue is server-only.')

		local Name, Definition
		if SelfOrName == FORGE then
			Name, Definition = NameOrDefinition, MaybeDefinition
		else
			Name, Definition = SelfOrName, NameOrDefinition
		end

		assert(type(Name) == 'string' and Name ~= '', 'FORGE.Queue requires a name.')
		LoadServerSubsystems()

		local Matchmaking = FORGE.Engine.Matchmaking
		local Existing = Matchmaking.GetQueue(Name)
		if Existing or Definition == nil then return Existing end
		return Matchmaking.CreateQueue(Name, Definition)
	end

	function FORGE.Match(SelfOrId, MaybeId)
		assert(RunService:IsServer(), 'FORGE.Match is server-only.')
		local MatchId = SelfOrId == FORGE and MaybeId or SelfOrId
		assert(type(MatchId) == 'string' and MatchId ~= '', 'FORGE.Match requires a match id.')
		LoadServerSubsystems()
		return FORGE.Engine.Matchmaking.GetMatch(MatchId)
	end

	local function StartMatchmakingIfNeeded()
		if not RunService:IsServer() or not FORGE.Engine.Matchmaking then return end
		if next(FORGE.Engine.Matchmaking.Queues) ~= nil then FORGE.Engine.Matchmaking.Start() end
	end

	local function Rebuild()
		local Kind = RunService:IsServer() and 'Service' or 'Controller'
		local Ordered = DependencyGraph.Resolve(Registry.List(Kind))
		Lifecycle.Init(Ordered)

		if RunService:IsServer() and RuntimeState.Bridge and RuntimeState.Bridge.RebuildRoutes then
			RuntimeState.Bridge:RebuildRoutes()
			StartMatchmakingIfNeeded()
		end

		Lifecycle.Start(Ordered)
		RuntimeState.Ordered = Ordered
	end

	function FORGE.Start(Options)
		Options = Options or {}
		if RuntimeState.Started then return RuntimeState.BootReport end
		if RuntimeState.Starting then error('FORGE is already starting.') end

		DisconnectRuntimeConnections()
		ResetBootReport()
		RuntimeDestroyed = false
		RuntimeState.Starting = true
		RuntimeState.Roots = Options.Roots or RuntimeState.Roots or {}

		local Success, Result = xpcall(function()
			if RunService:IsClient() then
				RuntimeState.Bridge = Options.Bridge or RuntimeState.Bridge or ClientBridge.new()
				if RuntimeState.Bridge.SetActivityHook then
					RuntimeState.Bridge:SetActivityHook(function(Kind, Target, Fields)
						Tooling:Pulse('Network', Kind, Target, Fields)
					end)
				end
				RuntimeState.Bridge:Start()
			elseif Options.Bridge then
				RuntimeState.Bridge = Options.Bridge
				RuntimeState.Bridge:Start()
			elseif RuntimeState.Bridge then
				RuntimeState.Bridge:Start()
			else
				error('FORGE server startup requires a ServerBridge instance.')
			end

			Loader.Load(RuntimeState.Roots)

			if RunService:IsServer() and RuntimeState.Bridge.RebuildRoutes then
				RuntimeState.Bridge:RebuildRoutes()
				LoadServerSubsystems()
			end

			local Kind = RunService:IsServer() and 'Service' or 'Controller'
			local Ordered = DependencyGraph.Resolve(Registry.List(Kind))
			Lifecycle.Init(Ordered)

			if RunService:IsServer() then
				RuntimeState.Bridge:RebuildRoutes()
				StartMatchmakingIfNeeded()
			end

			Lifecycle.Start(Ordered)
			RuntimeState.Ordered = Ordered

			if RunService:IsServer() and RuntimeState.Bridge.SetReady then RuntimeState.Bridge:SetReady(true) end

			for _, RuntimeRoot in ipairs(RuntimeState.Roots) do
				local Connection = Loader.Watch(RuntimeRoot, Rebuild)
				if Connection then table.insert(RuntimeState.Connections, Connection) end
			end

			RuntimeState.Started = true
			Logger.Info('Runtime', string.format('FORGE %s started in %s mode.', KernelConfig.Version, RuntimeState.Environment))
			return RuntimeState.BootReport
		end, debug.traceback)

		RuntimeState.Starting = false

		if not Success then
			RuntimeState.Started = false
			if RunService:IsServer() and RuntimeState.Bridge and RuntimeState.Bridge.SetBootError then
				RuntimeState.Bridge:SetBootError(Result)
			end
			error(Result)
		end

		return Result
	end

	function FORGE.RegisterMiddleware(Name, Callback)
		assert(RunService:IsServer(), 'RegisterMiddleware is server-only.')
		assert(RuntimeState.Bridge and RuntimeState.Bridge.RegisterMiddleware, 'FORGE server bridge is not active.')
		RuntimeState.Bridge:RegisterMiddleware(Name, Callback)
	end

	function FORGE.UseMiddleware(Callback)
		assert(RunService:IsServer(), 'UseMiddleware is server-only.')
		assert(RuntimeState.Bridge and RuntimeState.Bridge.Use, 'FORGE server bridge is not active.')
		RuntimeState.Bridge:Use(Callback)
	end

	function FORGE.Stop()
		if RunService:IsServer() and RuntimeState.Bridge and RuntimeState.Bridge.SetReady then RuntimeState.Bridge:SetReady(false) end
		DisconnectRuntimeConnections()
		if not RuntimeState.Started then return end
		Lifecycle.Stop(RuntimeState.Ordered or {})
		if RunService:IsServer() and FORGE.Engine.Matchmaking then FORGE.Engine.Matchmaking.Stop() end
		RuntimeState.Started = false
	end

	function FORGE.Destroy()
		if RuntimeDestroyed then return end
		FORGE.Stop()
		Lifecycle.Destroy(RuntimeState.Ordered or {})

		if ClientDataConnection then ClientDataConnection:Disconnect(); ClientDataConnection = nil end
		ClientDataService = nil
		for _, Entry in pairs(ClientProfiles) do
			if Entry.Adapter and Entry.Adapter.Changed then Entry.Adapter.Changed:Destroy() end
		end
		table.clear(ClientProfiles)
		table.clear(Currencies)
		table.clear(Inventories)

		if RuntimeState.Bridge and RuntimeState.Bridge.Destroy then RuntimeState.Bridge:Destroy() end

		RuntimeState.Started = false
		RuntimeState.Starting = false
		RuntimeDestroyed = true
	end

	function FORGE.Shutdown()
		if RunService:IsClient() then UI.Destroy() end
		FORGE.Destroy()

		if RunService:IsServer() then
			if FORGE.Engine.Matchmaking then FORGE.Engine.Matchmaking.Destroy() end
			if FORGE.Engine.Data then FORGE.Engine.Data.DestroyAll() end
		end
	end

	function FORGE.GetBootReport()
		return RuntimeState.BootReport
	end
end

return FORGE
