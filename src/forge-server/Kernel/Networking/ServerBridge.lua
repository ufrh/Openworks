-- Author -> lolokdev.
-- Last Edit -> September 15, 2026 1:55 PM CDT

local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Workspace = game:GetService('Workspace')

local Config = require(ReplicatedStorage.FORGE.Kernel.Core.Config)
local Registry = require(ReplicatedStorage.FORGE.Kernel.Core.Registry)
local Validator = require(ReplicatedStorage.FORGE.Kernel.Networking.Validator)
local Serializer = require(ReplicatedStorage.FORGE.Kernel.Networking.Serializer)
local SecurityCodec = require(ReplicatedStorage.FORGE.Kernel.Networking.SecurityCodec)
local Protocol = require(ReplicatedStorage.FORGE.Kernel.Networking.Protocol)

local SessionManager = require(script.Parent.SessionManager)
local RateLimiter = require(script.Parent.RateLimiter)
local Middleware = require(script.Parent.Middleware)

local ServerBridge = {} do
	ServerBridge.__index = ServerBridge
	ServerBridge.ClassName = 'ServerBridge'

	local RPC_TRANSPORT = 'RPC'
	local EVENT_TRANSPORT = 'Event'

	-- copy -> table
	-- Deep copies manifest data before exposing it through the handshake.
	-- @param Value, any -> Value being copied.
	local function copy(Value)
		if type(Value) ~= 'table' then
			return Value
		end

		local Result = {}

		for Key, Item in pairs(Value) do
			Result[Key] = copy(Item)
		end

		return Result;
	end

	-- invokeRoute -> table
	-- Invokes one endpoint while preserving packed return values.
	-- @param Callback, function -> Server endpoint callback.
	-- @param Player, Player -> Requesting player.
	-- @param Arguments, table -> Packed endpoint arguments.
	local function invokeRoute(Callback, Player: Player, Arguments)
		return table.pack(Callback(Player, table.unpack(Arguments, 1, Arguments.n)));
	end

	-- encodeResponse -> table
	-- Wraps response encoding for protected calls.
	-- @param Bridge, ServerBridge -> Active bridge.
	-- @param Session, table -> Current player session.
	-- @param Nonce, number -> Request nonce.
	-- @param Route, string -> Opaque endpoint route.
	-- @param Result, table -> Packed endpoint results.
	local function encodeResponse(Bridge, Session, Nonce: number, Route: string, Result)
		return Bridge:_EncodeResponse(Session, Nonce, Route, Result);
	end

	-- new -> ServerBridge
	-- Creates the authoritative FORGE network transport and security runtime.
	function ServerBridge.new()
		local this = setmetatable({}, ServerBridge)

		this._Sessions = SessionManager.new()
		this._RateLimiter = RateLimiter.new()
		this._Middleware = Middleware.new()
		this._Routes = {}
		this._SignalRoutes = {}
		this._Manifest = {}
		this._Folder = nil
		this._Bootstrap = nil
		this._RPC = nil
		this._Event = nil
		this._Connections = {}
		this._Started = false
		this._ManifestReady = false
		this._Ready = false
		this._BootError = nil
		this._Stats = {
			Handshakes = 0,
			RPC = 0,
			Events = 0,
			Rejected = 0,
			Outbound = 0
		}

		return this;
	end

	-- _PublicError -> string
	-- Avoids leaking internal traceback details outside development mode.
	-- @param Reason, any -> Internal rejection reason.
	function ServerBridge:_PublicError(Reason)
		if Config.Runtime.Debug then
			return tostring(Reason)
		end

		return 'request rejected';
	end

	-- _Reject -> table
	-- Creates a standard rejected RPC packet.
	-- @param Reason, any -> Rejection reason.
	function ServerBridge:_Reject(Reason)
		self._Stats.Rejected += 1
		return {
			ok = false;
			v = Protocol.Version;
			error = self:_PublicError(Reason);
		};
	end

	-- _EncodeResponse -> table
	-- Serializes and signs one successful RPC result.
	-- @param Session, table -> Player session.
	-- @param Nonce, number -> Matching request nonce.
	-- @param Route, string -> Opaque route id.
	-- @param Packed, table -> Packed method results.
	function ServerBridge:_EncodeResponse(Session, Nonce: number, Route: string, Packed)
		local Plaintext = Serializer.EncodePacked(Packed)
		local Payload = SecurityCodec.Encode(Plaintext, Session.Token, Nonce, Protocol.Directions.Response)
		local Timestamp = Workspace:GetServerTimeNow()
		local Tag = SecurityCodec.Tag(Session.Token, Nonce, Timestamp, Route, Payload, Protocol.Directions.Response)

		return {
			ok = true;
			v = Protocol.Version;
			time = Timestamp;
			payload = Payload;
			tag = Tag;
		};
	end

	-- _DecodeRequest -> table
	-- Decodes one authenticated request payload.
	-- @param Session, table -> Current player session.
	-- @param Nonce, number -> Request nonce.
	-- @param Payload, string -> Encoded request body.
	function ServerBridge:_DecodeRequest(Session, Nonce: number, Payload: string)
		local Plaintext = SecurityCodec.Decode(Payload, Session.Token, Nonce, Protocol.Directions.Request)

		return Serializer.DecodePacked(Plaintext);
	end

	-- _ValidatePacket -> table?, string?
	-- Performs protocol, clock, integrity, replay and decode validation before endpoint logic runs.
	-- @param Player, Player -> Requesting player.
	-- @param Packet, table -> Client packet.
	function ServerBridge:_ValidatePacket(Player: Player, Packet)
		if type(Packet) ~= 'table' then
			return nil, 'malformed packet'
		end

		if Packet.v ~= Protocol.Version then
			return nil, 'protocol version mismatch'
		end

		local Session = self._Sessions:Get(Player)

		if not Session then
			return nil, 'session handshake required'
		end

		local Route = Packet.route
		local Nonce = tonumber(Packet.nonce)
		local Timestamp = tonumber(Packet.time)
		local Payload = Packet.payload

		if type(Route) ~= 'string' or type(Payload) ~= 'string' or not Nonce or not Timestamp then
			return nil, 'malformed packet fields'
		end

		if #Payload > Config.Network.MaximumPayloadBytes * 2 + 512 then
			return nil, 'payload limit exceeded'
		end

		if math.abs(Workspace:GetServerTimeNow() - Timestamp) > Config.Network.ClockSkew then
			return nil, 'packet timestamp outside accepted window'
		end

		local Expected = SecurityCodec.Tag(Session.Token, Nonce, Timestamp, Route, Payload, Protocol.Directions.Request)

		if Config.Security.RequireIntegrityTag and not SecurityCodec.Equal(Expected, Packet.tag) then
			return nil, 'integrity validation failed'
		end

		if Config.Security.RejectReplay and not self._Sessions:ValidateNonce(Player, Nonce) then
			return nil, 'replayed or expired packet'
		end

		local Success, Packed = pcall(ServerBridge._DecodeRequest, self, Session, Nonce, Payload)

		if not Success then
			return nil, 'payload decode failed'
		end

		return {
			Session = Session;
			Route = Route;
			Nonce = Nonce;
			Timestamp = Timestamp;
			Arguments = Packed;
		};
	end

	-- _CheckRates -> boolean, string?
	-- Applies request limits unless an endpoint explicitly opts out with Rate=false.
	-- @param Player, Player -> Requesting player.
	-- @param Route, string -> Endpoint route id.
	-- @param Options, table -> Endpoint options.
	function ServerBridge:_CheckRates(Player: Player, Route: string, Options)
		if Options.Rate == false then
			return true
		end

		local Global = Config.Network.GlobalRate
		local Endpoint = Options.Rate or Config.Network.DefaultEndpointRate
		local Capacity = Endpoint.Capacity or Config.Network.DefaultEndpointRate.Capacity
		local Refill = Endpoint.Refill or Config.Network.DefaultEndpointRate.Refill
		local GlobalKey = 'global:' .. tostring(Player.UserId)
		local EndpointKey = 'endpoint:' .. tostring(Player.UserId) .. ':' .. Route

		if not self._RateLimiter:Allow(GlobalKey, Global.Capacity, Global.Refill, 1) then
			return false, 'global rate limit exceeded'
		end

		if not self._RateLimiter:Allow(EndpointKey, Capacity, Refill, Options.Cost or 1) then
			return false, 'endpoint rate limit exceeded'
		end

		return true;
	end

	-- _ResolveRequest -> table?, table?, string?
	-- Validates one packet through transport, rate, schema and middleware boundaries.
	-- @param Player, Player -> Requesting player.
	-- @param Packet, table -> Client packet.
	-- @param Transport, string -> Expected RPC or Event transport.
	function ServerBridge:_ResolveRequest(Player: Player, Packet, Transport: string)
		if not self._Ready then
			return nil, nil, self._BootError and 'server startup failed' or 'server booting'
		end

		local Envelope, Reason = self:_ValidatePacket(Player, Packet)

		if not Envelope then
			return nil, nil, Reason
		end

		local Route = self._Routes[Envelope.Route]

		if not Route then
			return nil, nil, 'unknown endpoint route'
		end

		if Route.Transport ~= Transport then
			return nil, nil, 'endpoint transport mismatch'
		end

		local Options = Route.Service._EndpointOptions[Route.Name] or {}
		local Allowed, RateReason = self:_CheckRates(Player, Envelope.Route, Options)

		if not Allowed then
			return nil, nil, RateReason
		end

		local Valid, ValidationReason = Validator.ValidateArguments(Envelope.Arguments, Options)

		if not Valid then
			return nil, nil, ValidationReason
		end

		local Context = {
			Player = Player;
			Service = Route.Service;
			Endpoint = Route.Name;
			Route = Envelope.Route;
			Arguments = Envelope.Arguments;
			Options = Options;
			Transport = Transport;
		}

		local MiddlewareAllowed, MiddlewareReason = self._Middleware:Run(Context, Options.Middleware)

		if not MiddlewareAllowed then
			return nil, nil, MiddlewareReason
		end

		return Envelope, Route, nil;
	end

	-- _Invoke -> table
	-- Routes one validated RPC request into its Service endpoint and returns a signed result packet.
	-- @param Player, Player -> Requesting player.
	-- @param Packet, table -> Client request packet.
	function ServerBridge:_Invoke(Player: Player, Packet)
		self._Stats.RPC += 1
		local Envelope, Route, Reason = self:_ResolveRequest(Player, Packet, RPC_TRANSPORT)

		if not Envelope then
			return self:_Reject(Reason)
		end

		local Success, Result = xpcall(invokeRoute, debug.traceback, Route.Callback, Player, Envelope.Arguments)

		if not Success then
			return self:_Reject(Result)
		end

		local Encoded, Response = pcall(encodeResponse, self, Envelope.Session, Envelope.Nonce, Envelope.Route, Result)

		if not Encoded then
			return self:_Reject(Response)
		end

		return Response;
	end

	-- _DispatchEvent -> nil
	-- Routes one validated fire-and-forget packet without forcing the client to wait for a response.
	-- @param Player, Player -> Requesting player.
	-- @param Packet, table -> Client event packet.
	function ServerBridge:_DispatchEvent(Player: Player, Packet)
		self._Stats.Events += 1
		local Envelope, Route = self:_ResolveRequest(Player, Packet, EVENT_TRANSPORT)

		if not Envelope then
			return
		end

		local Success, Result = xpcall(invokeRoute, debug.traceback, Route.Callback, Player, Envelope.Arguments)

		if not Success and Config.Runtime.Debug then
			warn(string.format('[FORGE Event %s.%s] %s', Route.Service.Name, Route.Name, tostring(Result)))
		end
	end

	-- _Handshake -> table
	-- Issues the player's opaque session token and current randomized route manifest.
	-- @param Player, Player -> Player requesting transport information.
	-- @param Request, table? -> Client protocol request.
	function ServerBridge:_Handshake(Player: Player, Request)
		self._Stats.Handshakes += 1
		if type(Request) ~= 'table' or Request.v ~= Protocol.Version then
			return self:_Reject('protocol version mismatch')
		end

		local Key = 'bootstrap:' .. tostring(Player.UserId)

		local BootstrapRate = Config.Network.BootstrapRate or {Capacity = 60, Refill = 20}
		if not self._RateLimiter:Allow(Key, BootstrapRate.Capacity, BootstrapRate.Refill, 1) then
			return self:_Reject('bootstrap rate limit exceeded')
		end

		local Session = self._Sessions:Handshake(Player)

		return {
			ok = true;
			v = Protocol.Version;
			token = Session.Token;
			session = string.sub(SecurityCodec.Hash(self._Sessions.SessionId), 1, 16);
			rpc = self._RPC.Name;
			event = self._Event.Name;
			manifest = copy(self._Manifest);
			manifestReady = self._ManifestReady;
			ready = self._Ready;
			bootError = self._BootError;
		};
	end

	-- _OnBootstrap -> table
	-- Handles one bootstrap invocation.
	-- @param Player, Player -> Requesting player.
	-- @param Request, table -> Bootstrap request.
	function ServerBridge:_OnBootstrap(Player: Player, Request)
		return self:_Handshake(Player, Request);
	end

	-- _OnRPC -> table
	-- Handles one RPC invocation.
	-- @param Player, Player -> Requesting player.
	-- @param Packet, table -> Request packet.
	function ServerBridge:_OnRPC(Player: Player, Packet)
		return self:_Invoke(Player, Packet);
	end

	-- _OnEvent -> nil
	-- Handles one fire-and-forget endpoint request.
	-- @param Player, Player -> Requesting player.
	-- @param Packet, table -> Event packet.
	function ServerBridge:_OnEvent(Player: Player, Packet)
		self:_DispatchEvent(Player, Packet)
	end

	-- _OnPlayerRemoving -> nil
	-- Clears networking state associated with a disconnecting player.
	-- @param Player, Player -> Disconnecting player.
	function ServerBridge:_OnPlayerRemoving(Player: Player)
		self._Sessions:Remove(Player)
		self._RateLimiter:Clear('global:' .. tostring(Player.UserId))
		self._RateLimiter:Clear('bootstrap:' .. tostring(Player.UserId))
		self._RateLimiter:ClearPrefix('endpoint:' .. tostring(Player.UserId) .. ':')
	end

	-- Start -> ServerBridge
	-- Creates one discoverable bootstrap plus randomized per-server RPC and bidirectional event transports.
	function ServerBridge:Start()
		if self._Started then
			return self
		end

		self._Started = true

		local Existing = ReplicatedStorage:FindFirstChild(Config.Network.FolderName)

		if Existing then
			Existing:Destroy()
		end

		self._Folder = Instance.new('Folder')
		self._Folder.Name = Config.Network.FolderName
		self._Folder.Parent = ReplicatedStorage

		self._Bootstrap = Instance.new('RemoteFunction')
		self._Bootstrap.Name = Config.Network.BootstrapName
		self._Bootstrap.Parent = self._Folder

		self._RPC = Instance.new('RemoteFunction')
		self._RPC.Name = Config.Security.RandomizeRemoteNames and self._Sessions:RemoteName('rpc') or 'RPC'
		self._RPC.Parent = self._Folder

		self._Event = Instance.new('RemoteEvent')
		self._Event.Name = Config.Security.RandomizeRemoteNames and self._Sessions:RemoteName('event') or 'Event'
		self._Event.Parent = self._Folder

		self._Bootstrap.OnServerInvoke = function(Player, Request)
			return self:_OnBootstrap(Player, Request)
		end

		self._RPC.OnServerInvoke = function(Player, Packet)
			return self:_OnRPC(Player, Packet)
		end

		table.insert(self._Connections, self._Event.OnServerEvent:Connect(function(Player, Packet)
			self:_OnEvent(Player, Packet)
		end))

		table.insert(self._Connections, Players.PlayerRemoving:Connect(function(Player)
			self:_OnPlayerRemoving(Player)
		end))

		return self;
	end

	-- RebuildRoutes -> nil
	-- Rebuilds opaque RPC, event and signal ids from every currently registered Service.
	function ServerBridge:RebuildRoutes()
		self._Routes = {}
		self._SignalRoutes = {}
		self._Manifest = {}

		for _, Service in ipairs(Registry.List('Service')) do
			local Definition = {
				Methods = {};
				Events = {};
				Signals = {};
				States = {};
			}

			self._Manifest[Service.Name] = Definition

			for MethodName, Callback in pairs(Service._RemoteMethods) do
				local Options = Service._EndpointOptions[MethodName] or {}
				local Transport = Options.Transport == EVENT_TRANSPORT and EVENT_TRANSPORT or RPC_TRANSPORT
				local RouteName = Service.Name .. '/' .. string.lower(Transport) .. '/' .. MethodName
				local Route = self._Sessions:RouteId(RouteName)

				if Transport == EVENT_TRANSPORT then
					Definition.Events[MethodName] = Route
				else
					Definition.Methods[MethodName] = Route
				end

				self._Routes[Route] = {
					Service = Service;
					Name = MethodName;
					Callback = Callback;
					Transport = Transport;
				}
			end

			for SignalName in pairs(Service._RemoteSignals) do
				local RouteName = Service.Name .. '/signal/' .. SignalName
				local Route = self._Sessions:RouteId(RouteName)

				Definition.Signals[SignalName] = Route
				self._SignalRoutes[Service.Name .. '\0' .. SignalName] = Route
			end

			for StateName, StateDefinition in pairs(Service._RemoteStates or {}) do
				local GetRoute = Definition.Methods[StateDefinition.Get]
				local ChangedRoute = Definition.Signals[StateDefinition.Changed]

				if GetRoute and ChangedRoute then
					Definition.States[StateName] = {
						Get = GetRoute,
						Changed = ChangedRoute
					}

					Definition.Methods[StateDefinition.Get] = nil
					Definition.Signals[StateDefinition.Changed] = nil
				end
			end
		end

		self._ManifestReady = true
	end

	function ServerBridge:SetReady(Ready)
		self._Ready = Ready == true
		if self._Ready then
			self._BootError = nil
		end
	end

	function ServerBridge:SetBootError(Reason)
		self._Ready = false
		self._ManifestReady = true
		self._BootError = tostring(Reason or 'unknown server startup failure')
	end

	-- RegisterMiddleware -> nil
	-- Registers reusable server middleware by name.
	-- @param Name, string -> Middleware name.
	-- @param Callback, function -> Middleware callback.
	function ServerBridge:RegisterMiddleware(Name: string, Callback)
		self._Middleware:Register(Name, Callback)
	end

	-- Use -> nil
	-- Adds global middleware that runs on every client-to-server endpoint call.
	-- @param Callback, function -> Middleware callback.
	function ServerBridge:Use(Callback)
		self._Middleware:Use(Callback)
	end

	-- FireClient -> nil
	-- Sends one declared Service signal to one handshaken player using signed packet transport.
	-- @param Player, Player -> Signal recipient.
	-- @param ServiceName, string -> Owning Service name.
	-- @param SignalName, string -> Declared signal name.
	-- @param ..., any -> Signal arguments.
	function ServerBridge:FireClient(Player: Player, ServiceName: string, SignalName: string, ...)
		self._Stats.Outbound += 1
		if not Player or not Player.Parent then
			return
		end

		local Session = self._Sessions:Get(Player)

		if not Session then
			return
		end

		local Route = self._SignalRoutes[ServiceName .. '\0' .. SignalName]

		if not Route then
			error('Unknown FORGE remote signal ' .. ServiceName .. '.' .. SignalName)
		end

		local Nonce = self._Sessions:NextServerNonce(Player)
		local Timestamp = Workspace:GetServerTimeNow()
		local Plaintext = Serializer.EncodePacked(table.pack(...))
		local Payload = SecurityCodec.Encode(Plaintext, Session.Token, Nonce, Protocol.Directions.Event)
		local Tag = SecurityCodec.Tag(Session.Token, Nonce, Timestamp, Route, Payload, Protocol.Directions.Event)

		self._Event:FireClient(Player, {
			v = Protocol.Version;
			route = Route;
			nonce = Nonce;
			time = Timestamp;
			payload = Payload;
			tag = Tag;
		})
	end

	-- FireAll -> nil
	-- Sends one declared Service signal to every connected player.
	-- @param ServiceName, string -> Owning Service name.
	-- @param SignalName, string -> Declared signal name.
	-- @param ..., any -> Signal arguments.
	function ServerBridge:FireAll(ServiceName: string, SignalName: string, ...)
		local Packed = table.pack(...)

		for _, Player in ipairs(Players:GetPlayers()) do
			self:FireClient(Player, ServiceName, SignalName, table.unpack(Packed, 1, Packed.n))
		end
	end

	-- Destroy -> nil
	-- Destroys transport instances, sessions and middleware state.
	function ServerBridge:Destroy()
		for _, Connection in ipairs(self._Connections) do
			Connection:Disconnect()
		end

		self._Connections = {}
		self._RateLimiter:Destroy()
		self._Sessions:Destroy()

		if self._Folder then
			self._Folder:Destroy()
			self._Folder = nil
		end

		self._Started = false
		self._ManifestReady = false
		self._Ready = false
		self._BootError = nil
	end
end

return ServerBridge;
