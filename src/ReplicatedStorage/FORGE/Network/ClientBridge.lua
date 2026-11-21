-- Author -> lolokdev.
-- Last Edit -> September 15, 2026 1:55 PM CDT

local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Workspace = game:GetService('Workspace')

local Config = require(script.Parent.Parent.Config)
local Signal = require(script.Parent.Parent.Core.Signal)
local Serializer = require(script.Parent.Serializer)
local SecurityCodec = require(script.Parent.SecurityCodec)
local Protocol = require(script.Parent.Protocol)

local ClientBridge = {} do
	ClientBridge.__index = ClientBridge
	ClientBridge.ClassName = 'ClientBridge'

	-- new -> ClientBridge
	-- Creates the client-side authenticated transport proxy.
	function ClientBridge.new()
		local this = setmetatable({}, ClientBridge)

		this._Folder = nil
		this._Bootstrap = nil
		this._RPC = nil
		this._Event = nil
		this._Token = nil
		this._Nonce = 0
		this._LastServerNonce = 0
		this._Manifest = {}
		this._Services = {}
		this._SignalRoutes = {}
		this._EventConnection = nil
		this._ServerReady = false
		this._ManifestReady = false
		this._BootError = nil

		return this;
	end

	-- _DecodeResponse -> table
	-- Verifies and decodes one server RPC response packet.
	-- @param Packet, table -> Server response packet.
	-- @param Nonce, number -> Matching request nonce.
	-- @param Route, string -> Opaque route id.
	function ClientBridge:_DecodeResponse(Packet, Nonce, Route)
		if type(Packet) ~= 'table' then
			error('FORGE server returned an invalid response packet.')
		end

		if Packet.ok == false then
			error(Packet.error or 'FORGE endpoint rejected request.', 3)
		end

		if Packet.v ~= Protocol.Version then
			error('FORGE protocol version mismatch.')
		end

		local Timestamp = tonumber(Packet.time)
		local Payload = Packet.payload
		local Tag = Packet.tag

		if type(Payload) ~= 'string' or type(Timestamp) ~= 'number' then
			error('FORGE server returned malformed response data.')
		end

		local Expected = SecurityCodec.Tag(self._Token, Nonce, Timestamp, Route, Payload, Protocol.Directions.Response)

		if Config.Security.RequireIntegrityTag and not SecurityCodec.Equal(Expected, Tag) then
			error('FORGE response integrity validation failed.')
		end

		local Plaintext = SecurityCodec.Decode(Payload, self._Token, Nonce, Protocol.Directions.Response)

		return Serializer.DecodePacked(Plaintext);
	end

	-- _HandleEvent -> nil
	-- Verifies, decodes and dispatches one server-to-client Service signal packet.
	-- @param Packet, table -> Event packet.
	function ClientBridge:_HandleEvent(Packet)
		if type(Packet) ~= 'table' or Packet.v ~= Protocol.Version then
			return
		end

		local Nonce = tonumber(Packet.nonce)
		local Timestamp = tonumber(Packet.time)
		local Route = Packet.route
		local Payload = Packet.payload

		if not Nonce or not Timestamp or type(Route) ~= 'string' or type(Payload) ~= 'string' then
			return
		end

		if Config.Security.RejectReplay and Nonce <= self._LastServerNonce then
			return
		end

		if math.abs(Workspace:GetServerTimeNow() - Timestamp) > Config.Network.ClockSkew then
			return
		end

		local Expected = SecurityCodec.Tag(self._Token, Nonce, Timestamp, Route, Payload, Protocol.Directions.Event)

		if Config.Security.RequireIntegrityTag and not SecurityCodec.Equal(Expected, Packet.tag) then
			return
		end

		local SignalObject = self._SignalRoutes[Route]

		if not SignalObject then
			return
		end

		-- decodeEvent -> table
		-- Decodes the authenticated signal payload inside a protected call.
		local function decodeEvent()
			local Plaintext = SecurityCodec.Decode(Payload, self._Token, Nonce, Protocol.Directions.Event)

			return Serializer.DecodePacked(Plaintext);
		end

		local Success, Packed = pcall(decodeEvent)

		if not Success then
			return
		end

		self._LastServerNonce = Nonce
		SignalObject:Fire(table.unpack(Packed, 1, Packed.n))
	end

	-- _Arguments -> table
	-- Removes optional colon-call self from one generated Service endpoint argument list.
	-- @param Proxy, table -> Generated Service proxy.
	-- @param ..., any -> Raw method arguments.
	local function endpointArguments(Proxy, ...)
		local Arguments = table.pack(...)

		if Arguments[1] == Proxy then
			for Index = 1, Arguments.n - 1 do
				Arguments[Index] = Arguments[Index + 1]
			end

			Arguments[Arguments.n] = nil
			Arguments.n -= 1
		end

		return Arguments;
	end

	-- _BuildServices -> nil
	-- Rebuilds client Service proxies from the latest server manifest.
	function ClientBridge:_BuildServices()
		self._SignalRoutes = {}

		for ServiceName, Definition in pairs(self._Manifest) do
			local Proxy = self._Services[ServiceName]

			if not Proxy then
				Proxy = {}

				-- resolveMissing -> any
				-- Refreshes the route manifest when a missing service member is requested.
				-- @param _, table -> Service proxy.
				-- @param Key, any -> Requested member key.
				local function resolveMissing(_, Key)
					self:Refresh()

					return rawget(Proxy, Key);
				end

				setmetatable(Proxy, {
					__index = resolveMissing;
				})

				self._Services[ServiceName] = Proxy
			end

			for MethodName, Route in pairs(Definition.Methods or {}) do
				Proxy[MethodName] = function(...)
					local Arguments = endpointArguments(Proxy, ...)

					return self:Invoke(Route, table.unpack(Arguments, 1, Arguments.n))
				end
			end

			for EventName, Route in pairs(Definition.Events or {}) do
				Proxy[EventName] = function(...)
					local Arguments = endpointArguments(Proxy, ...)

					self:Fire(Route, table.unpack(Arguments, 1, Arguments.n))
				end
			end

			for SignalName, Route in pairs(Definition.Signals or {}) do
				local SignalObject = rawget(Proxy, SignalName)

				if type(SignalObject) ~= 'table' or SignalObject.ClassName ~= 'Signal' then
					SignalObject = Signal.new()
					Proxy[SignalName] = SignalObject
				end

				self._SignalRoutes[Route] = SignalObject
			end
		end
	end

	-- Refresh -> boolean
	-- Re-handshakes with the server and updates routes without changing the current player token unnecessarily.
	function ClientBridge:Refresh()
		if not self._Bootstrap then
			return false
		end

		local Success, Handshake = pcall(function()
			return self._Bootstrap:InvokeServer({
				v = Protocol.Version;
			})
		end)

		if not Success or type(Handshake) ~= 'table' or Handshake.ok ~= true then
			return false
		end

		if Handshake.v ~= Protocol.Version then
			error('FORGE protocol version mismatch.')
		end

		if Handshake.bootError then
			self._BootError = tostring(Handshake.bootError)
		else
			self._BootError = nil
		end

		self._Token = Handshake.token
		self._Manifest = Handshake.manifest or {}
		self._ServerReady = Handshake.ready == true
		self._ManifestReady = Handshake.manifestReady == true

		local RPC = self._Folder:FindFirstChild(Handshake.rpc)
		local Event = self._Folder:FindFirstChild(Handshake.event)

		if not RPC or not RPC:IsA('RemoteFunction') then
			error('FORGE RPC transport missing.')
		end

		if not Event or not Event:IsA('RemoteEvent') then
			error('FORGE event transport missing.')
		end

		self._RPC = RPC
		self._Event = Event

		if self._EventConnection then
			self._EventConnection:Disconnect()
		end

		self._EventConnection = self._Event.OnClientEvent:Connect(function(Packet)
			self:_HandleEvent(Packet)
		end)

		self:_BuildServices()

		return true;
	end

	-- Start -> ClientBridge
	-- Locates the network bootstrap with bounded waits and establishes the current player session.
	function ClientBridge:Start()
		self._Folder = ReplicatedStorage:WaitForChild(Config.Network.FolderName, 15)

		if not self._Folder then
			error('FORGE network folder was not created by the server within 15 seconds.')
		end

		self._Bootstrap = self._Folder:WaitForChild(Config.Network.BootstrapName, 5)

		if not self._Bootstrap or not self._Bootstrap:IsA('RemoteFunction') then
			error('FORGE bootstrap transport is missing or invalid.')
		end

		local Deadline = os.clock() + 15

		repeat
			if self:Refresh() then
				return self
			end

			task.wait(.15)
		until os.clock() >= Deadline

		error('FORGE handshake timed out.')
	end

	-- _Packet -> table
	-- Encodes one authenticated client-to-server endpoint packet.
	-- @param Route, string -> Opaque endpoint route.
	-- @param ..., any -> Endpoint arguments.
	function ClientBridge:_Packet(Route: string, ...)
		self._Nonce += 1

		local Nonce = self._Nonce
		local Timestamp = Workspace:GetServerTimeNow()
		local Plaintext = Serializer.EncodePacked(table.pack(...))
		local Payload = SecurityCodec.Encode(Plaintext, self._Token, Nonce, Protocol.Directions.Request)
		local Tag = SecurityCodec.Tag(self._Token, Nonce, Timestamp, Route, Payload, Protocol.Directions.Request)

		return {
			v = Protocol.Version;
			route = Route;
			nonce = Nonce;
			time = Timestamp;
			payload = Payload;
			tag = Tag;
		}, Nonce;
	end

	-- Invoke -> ...any
	-- Invokes one request/response Service endpoint through the authenticated RPC transport.
	-- @param Route, string -> Opaque route id.
	-- @param ..., any -> Endpoint arguments.
	function ClientBridge:Invoke(Route, ...)
		assert(self._RPC and self._Token, 'FORGE client bridge is not started.')

		local Packet, Nonce = self:_Packet(Route, ...)
		local Response = self._RPC:InvokeServer(Packet)
		local Packed = self:_DecodeResponse(Response, Nonce, Route)

		return table.unpack(Packed, 1, Packed.n);
	end

	-- Fire -> nil
	-- Sends one fire-and-forget Service endpoint through the authenticated RemoteEvent transport.
	-- @param Route, string -> Opaque route id.
	-- @param ..., any -> Endpoint arguments.
	function ClientBridge:Fire(Route, ...)
		assert(self._Event and self._Token, 'FORGE client bridge is not started.')

		local Packet = self:_Packet(Route, ...)

		self._Event:FireServer(Packet)
	end

	-- GetService -> table?
	-- Returns a generated remote Service proxy and refreshes the manifest once when missing.
	-- @param Name, string -> Service name.
	function ClientBridge:GetService(Name)
		local Service = self._Services[Name]
		if Service then return Service end

		local Deadline = os.clock() + 30

		repeat
			local Success, Result = pcall(ClientBridge.Refresh, self)

			if not Success then
				error(Result, 2)
			end

			Service = self._Services[Name]
			if Service then return Service end

			if self._BootError then
				error('FORGE server startup failed: ' .. self._BootError, 2)
			end

			task.wait(.1)
		until os.clock() >= Deadline

		error('FORGE service ' .. tostring(Name) .. ' was not published by the server within 30 seconds.', 2)
	end

	-- Destroy -> nil
	-- Disconnects the transport and destroys generated local Signals.
	function ClientBridge:Destroy()
		if self._EventConnection then
			self._EventConnection:Disconnect()
			self._EventConnection = nil
		end

		for _, Service in pairs(self._Services) do
			for _, Value in pairs(Service) do
				if type(Value) == 'table' and Value.ClassName == 'Signal' then
					Value:Destroy()
				end
			end
		end

		self._Services = {}
		self._SignalRoutes = {}
		self._Manifest = {}
		self._RPC = nil
		self._Event = nil
		self._Bootstrap = nil
		self._Folder = nil
		self._Token = nil
	end
end

return ClientBridge;
