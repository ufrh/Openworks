-- Author -> lolokdev.
-- Last Edit -> September 15, 2026 1:55 PM CDT

local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Workspace = game:GetService('Workspace')

local Config = require(script.Parent.Parent.Core.Config)
local Signal = require(script.Parent.Parent.Core.Signal)
local Serializer = require(script.Parent.Serializer)
local SecurityCodec = require(script.Parent.SecurityCodec)
local Protocol = require(script.Parent.Protocol)

local ClientBridge = {} do
	ClientBridge.__index = ClientBridge
	ClientBridge.ClassName = 'ClientBridge'

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
		this._ActivityHook = nil
		this._Stats = {
			Refreshes = 0,
			RPC = 0,
			Events = 0,
			Inbound = 0
		}
		return this;
	end

	function ClientBridge:SetActivityHook(Callback)
		self._ActivityHook = type(Callback) == 'function' and Callback or nil
		return self
	end

	function ClientBridge:_Pulse(Kind, Target, Fields)
		if self._ActivityHook then
			self._ActivityHook(Kind, Target, Fields)
		end
	end

	function ClientBridge:_DecodeResponse(Packet, Nonce, Route)
		if type(Packet) ~= 'table' then error('FORGE server returned an invalid response packet.') end
		if Packet.ok == false then error(Packet.error or 'FORGE endpoint rejected request.', 3) end
		if Packet.v ~= Protocol.Version then error('FORGE protocol version mismatch.') end

		local Timestamp = tonumber(Packet.time)
		local Payload = Packet.payload
		local Tag = Packet.tag
		if type(Payload) ~= 'string' or type(Timestamp) ~= 'number' then error('FORGE server returned malformed response data.') end
		if math.abs(Workspace:GetServerTimeNow() - Timestamp) > Config.Network.ClockSkew then error('FORGE response timestamp outside accepted window.') end

		local Expected = SecurityCodec.Tag(self._Token, Nonce, Timestamp, Route, Payload, Protocol.Directions.Response)
		if Config.Security.RequireIntegrityTag and not SecurityCodec.Equal(Expected, Tag) then error('FORGE response integrity validation failed.') end

		local Plaintext = SecurityCodec.Decode(Payload, self._Token, Nonce, Protocol.Directions.Response)
		return Serializer.DecodePacked(Plaintext);
	end

	function ClientBridge:_HandleEvent(Packet)
		self._Stats.Inbound += 1
		if type(Packet) ~= 'table' or Packet.v ~= Protocol.Version then return end

		local Nonce = tonumber(Packet.nonce)
		local Timestamp = tonumber(Packet.time)
		local Route = Packet.route
		local Payload = Packet.payload
		if not Nonce or not Timestamp or type(Route) ~= 'string' or type(Payload) ~= 'string' then return end
		if Config.Security.RejectReplay and Nonce <= self._LastServerNonce then return end
		if math.abs(Workspace:GetServerTimeNow() - Timestamp) > Config.Network.ClockSkew then return end

		local Expected = SecurityCodec.Tag(self._Token, Nonce, Timestamp, Route, Payload, Protocol.Directions.Event)
		if Config.Security.RequireIntegrityTag and not SecurityCodec.Equal(Expected, Packet.tag) then return end

		local SignalObject = self._SignalRoutes[Route]
		if not SignalObject then return end
		self:_Pulse('InboundEvent', Route)

		local function decodeEvent()
			local Plaintext = SecurityCodec.Decode(Payload, self._Token, Nonce, Protocol.Directions.Event)
			return Serializer.DecodePacked(Plaintext);
		end

		local Success, Packed = pcall(decodeEvent)
		if not Success then return end
		self._LastServerNonce = Nonce
		SignalObject:Fire(table.unpack(Packed, 1, Packed.n))
	end

	local function endpointArguments(Proxy, ...)
		local Arguments = table.pack(...)
		if Arguments[1] == Proxy then
			for Index = 1, Arguments.n - 1 do Arguments[Index] = Arguments[Index + 1] end
			Arguments[Arguments.n] = nil
			Arguments.n -= 1
		end
		return Arguments;
	end

	local function networkState(Bridge, GetRoute, ChangedRoute)
		local Changed = Signal.new()
		local Transport = Signal.new()
		local State = {
			ClassName = 'State',
			ReadOnly = true,
			Visible = false,
			Value = nil,
			_Version = 0,
			Changed = Changed,
			_Transport = Transport
		}

		function State:Get()
			return self.Value
		end

		function State:Subscribe(Callback, Immediate)
			assert(type(Callback) == 'function', 'State subscription requires a function.')
			local Connection = Changed:Connect(Callback)
			if Immediate ~= false then Callback(self.Value, nil) end
			return Connection
		end

		function State:Set()
			error('Cannot set a replicated read-only FORGE State on the client.', 2)
		end

		function State:Update()
			error('Cannot update a replicated read-only FORGE State on the client.', 2)
		end

		function State:_Apply(Visible, Value, Version)
			Version = tonumber(Version) or 0
			if Version < self._Version then return end

			local Previous = self.Value
			local PreviousVisible = self.Visible
			self._Version = Version
			self.Visible = Visible == true
			self.Value = self.Visible and Value or nil

			if PreviousVisible ~= self.Visible or Previous ~= self.Value then
				Changed:Fire(self.Value, Previous)
			end
		end

		function State:Destroy()
			Changed:Destroy()
			Transport:Destroy()
			self.Value = nil
			self.Visible = false
		end

		Transport:Connect(function(Visible, Value, Version)
			State:_Apply(Visible, Value, Version)
		end)

		local Success, Visible, Value, Version = pcall(function()
			return Bridge:Invoke(GetRoute)
		end)
		if Success then State:_Apply(Visible, Value, Version) end

		return State, ChangedRoute
	end

	local function networkEvent(Bridge, Route)
		local Local = Signal.new()
		local Event = {
			ClassName = 'Event',
			_Route = Route,
			_Signal = Local
		}

		function Event:Connect(Callback)
			return Local:Connect(Callback)
		end

		function Event:Once(Callback)
			return Local:Once(Callback)
		end

		function Event:Wait()
			return Local:Wait()
		end

		function Event:Fire(...)
			Bridge:Fire(self._Route, ...)
		end

		function Event:Destroy()
			Local:Destroy()
			self._Route = nil
		end

		return Event
	end

	local function destroyProxySignals(Proxy)
		for Key, Value in pairs(Proxy) do
			if type(Value) == 'table' and (Value.ClassName == 'Signal' or Value.ClassName == 'Event' or Value.ClassName == 'State') then Value:Destroy() end
			Proxy[Key] = nil
		end
	end

	function ClientBridge:_BuildServices()
		self._SignalRoutes = {}
		local ActiveServices = {}

		for ServiceName, Definition in pairs(self._Manifest) do
			ActiveServices[ServiceName] = true
			local Proxy = self._Services[ServiceName]

			if not Proxy then
				Proxy = {}
				local function resolveMissing(_, Key)
					self:Refresh()
					return rawget(Proxy, Key);
				end
				setmetatable(Proxy, {__index = resolveMissing;})
				self._Services[ServiceName] = Proxy
			end

			for Key, Value in pairs(Proxy) do
				local IsSignal = type(Value) == 'table' and Value.ClassName == 'Signal'
				local IsEvent = type(Value) == 'table' and Value.ClassName == 'Event'
				local IsState = type(Value) == 'table' and Value.ClassName == 'State'
				local KeepSignal = Definition.Signals and Definition.Signals[Key] ~= nil
				local KeepEvent = Definition.Events and Definition.Events[Key] ~= nil
				local KeepMethod = Definition.Methods and Definition.Methods[Key] ~= nil
				local KeepState = Definition.States and Definition.States[Key] ~= nil

				if IsEvent and not (KeepSignal and KeepEvent) then Value:Destroy(); Proxy[Key] = nil
				elseif IsSignal and not KeepSignal then Value:Destroy(); Proxy[Key] = nil
				elseif IsState and not KeepState then Value:Destroy(); Proxy[Key] = nil
				elseif not IsSignal and not IsEvent and not IsState and not KeepEvent and not KeepMethod and not KeepState then Proxy[Key] = nil end
			end

			for MethodName, Route in pairs(Definition.Methods or {}) do
				Proxy[MethodName] = function(...)
					local Arguments = endpointArguments(Proxy, ...)
					return self:Invoke(Route, table.unpack(Arguments, 1, Arguments.n))
				end
			end

			for EventName, Route in pairs(Definition.Events or {}) do
				local SignalRoute = Definition.Signals and Definition.Signals[EventName]
				if SignalRoute then
					local EventObject = rawget(Proxy, EventName)
					if type(EventObject) ~= 'table' or EventObject.ClassName ~= 'Event' then
						if type(EventObject) == 'table' and EventObject.Destroy then EventObject:Destroy() end
						EventObject = networkEvent(self, Route)
						Proxy[EventName] = EventObject
					else
						EventObject._Route = Route
					end
					self._SignalRoutes[SignalRoute] = EventObject._Signal
				else
					Proxy[EventName] = function(...)
						local Arguments = endpointArguments(Proxy, ...)
						self:Fire(Route, table.unpack(Arguments, 1, Arguments.n))
					end
				end
			end

			for SignalName, Route in pairs(Definition.Signals or {}) do
				if Definition.Events and Definition.Events[SignalName] then continue end
				local SignalObject = rawget(Proxy, SignalName)
				if type(SignalObject) ~= 'table' or SignalObject.ClassName ~= 'Signal' then
					if type(SignalObject) == 'table' and SignalObject.Destroy then SignalObject:Destroy() end
					SignalObject = Signal.new()
					Proxy[SignalName] = SignalObject
				end
				self._SignalRoutes[Route] = SignalObject
			end

			for StateName, StateDefinition in pairs(Definition.States or {}) do
				local StateObject = rawget(Proxy, StateName)
				if type(StateObject) ~= 'table' or StateObject.ClassName ~= 'State' then
					if type(StateObject) == 'table' and StateObject.Destroy then StateObject:Destroy() end
					local Route
					StateObject, Route = networkState(self, StateDefinition.Get, StateDefinition.Changed)
					Proxy[StateName] = StateObject
					self._SignalRoutes[Route] = StateObject._Transport
				else
					self._SignalRoutes[StateDefinition.Changed] = StateObject._Transport

					if self._ServerReady then
						local Success, Visible, Value, Version = pcall(function()
							return self:Invoke(StateDefinition.Get)
						end)
						if Success then StateObject:_Apply(Visible, Value, Version) end
					end
				end
			end
		end

		for ServiceName, Proxy in pairs(self._Services) do
			if ActiveServices[ServiceName] then continue end
			destroyProxySignals(Proxy)
			self._Services[ServiceName] = nil
		end
	end

	function ClientBridge:Refresh()
		self._Stats.Refreshes += 1
		self:_Pulse('Handshake', 'Refresh')
		if not self._Bootstrap then return false, 'bootstrap transport unavailable' end

		local Success, Handshake = pcall(function()
			return self._Bootstrap:InvokeServer({v = Protocol.Version;})
		end)

		if not Success then
			return false, 'bootstrap invoke failed: ' .. tostring(Handshake)
		end

		if type(Handshake) ~= 'table' then
			return false, 'bootstrap returned ' .. typeof(Handshake) .. ' instead of table'
		end

		if Handshake.ok ~= true then
			return false, tostring(Handshake.error or 'bootstrap rejected request')
		end

		if Handshake.v ~= Protocol.Version then error('FORGE protocol version mismatch.') end

		self._BootError = Handshake.bootError and tostring(Handshake.bootError) or nil
		if self._Token and self._Token ~= Handshake.token then self._Nonce = 0; self._LastServerNonce = 0 end
		self._Token = Handshake.token
		self._Manifest = Handshake.manifest or {}
		self._ServerReady = Handshake.ready == true
		self._ManifestReady = Handshake.manifestReady == true

		local RPC = self._Folder:FindFirstChild(Handshake.rpc)
		local Event = self._Folder:FindFirstChild(Handshake.event)
		if not RPC or not RPC:IsA('RemoteFunction') then error('FORGE RPC transport missing.') end
		if not Event or not Event:IsA('RemoteEvent') then error('FORGE event transport missing.') end

		self._RPC = RPC
		self._Event = Event
		if self._EventConnection then self._EventConnection:Disconnect() end
		self._EventConnection = self._Event.OnClientEvent:Connect(function(Packet) self:_HandleEvent(Packet) end)
		self:_BuildServices()
		return true, {
			Ready = self._ServerReady,
			ManifestReady = self._ManifestReady,
			Services = self._Manifest and #self._Manifest or 0
		};
	end

	function ClientBridge:Start()
		local Timeout = tonumber(Config.Network.HandshakeTimeout) or 60
		local Interval = tonumber(Config.Network.HandshakeInterval) or .35

		self._Folder = ReplicatedStorage:WaitForChild(Config.Network.FolderName, Timeout)
		if not self._Folder then
			error(string.format('FORGE network folder was not created by the server within %.1f seconds.', Timeout))
		end

		self._Bootstrap = self._Folder:WaitForChild(Config.Network.BootstrapName, math.min(Timeout, 15))
		if not self._Bootstrap or not self._Bootstrap:IsA('RemoteFunction') then
			error('FORGE bootstrap transport is missing or invalid.')
		end

		local Deadline = time() + Timeout
		local LastState = 'no handshake response'
		local SuccessfulHandshakes = 0

		repeat
			local Refreshed, Detail = self:Refresh()

			if Refreshed then
				SuccessfulHandshakes += 1

				if self._BootError then
					error('FORGE server startup failed: ' .. tostring(self._BootError))
				end

				LastState = string.format(
					'ready=%s manifestReady=%s successfulHandshakes=%d',
					tostring(self._ServerReady),
					tostring(self._ManifestReady),
					SuccessfulHandshakes
				)

				if self._ManifestReady and self._ServerReady then return self end
			else
				LastState = tostring(Detail or 'unknown bootstrap failure')
			end

			task.wait(Interval)
		until time() >= Deadline

		error(string.format(
			'FORGE handshake timed out after %.1f seconds. Last state: %s',
			Timeout,
			LastState
		))
	end

	function ClientBridge:_Packet(Route: string, ...)
		self._Nonce += 1
		local Nonce = self._Nonce
		local Timestamp = Workspace:GetServerTimeNow()
		local Plaintext = Serializer.EncodePacked(table.pack(...))
		local Payload = SecurityCodec.Encode(Plaintext, self._Token, Nonce, Protocol.Directions.Request)
		local Tag = SecurityCodec.Tag(self._Token, Nonce, Timestamp, Route, Payload, Protocol.Directions.Request)
		return {v = Protocol.Version; route = Route; nonce = Nonce; time = Timestamp; payload = Payload; tag = Tag;}, Nonce;
	end

	function ClientBridge:Invoke(Route, ...)
		self._Stats.RPC += 1
		self:_Pulse('RPC', Route, {Direction = 'Outbound'})
		assert(self._RPC and self._Token, 'FORGE client bridge is not started.')
		local Packet, Nonce = self:_Packet(Route, ...)
		local Response = self._RPC:InvokeServer(Packet)
		local Packed = self:_DecodeResponse(Response, Nonce, Route)
		return table.unpack(Packed, 1, Packed.n);
	end

	function ClientBridge:Fire(Route, ...)
		self._Stats.Events += 1
		self:_Pulse('Event', Route, {Direction = 'Outbound'})
		assert(self._Event and self._Token, 'FORGE client bridge is not started.')
		local Packet = self:_Packet(Route, ...)
		self._Event:FireServer(Packet)
	end

	function ClientBridge:FindService(Name)
		return self._Services[Name]
	end

	function ClientBridge:GetService(Name)
		local Service = self._Services[Name]
		if Service then return Service end
		local Deadline = os.clock() + 30

		repeat
			local Success, Result = pcall(ClientBridge.Refresh, self)
			if not Success then error(Result, 2) end
			Service = self._Services[Name]
			if Service then return Service end
			if self._BootError then error('FORGE server startup failed: ' .. self._BootError, 2) end
			task.wait(.1)
		until os.clock() >= Deadline

		error('FORGE service ' .. tostring(Name) .. ' was not published by the server within 30 seconds.', 2)
	end

	function ClientBridge:Destroy()
		if self._EventConnection then self._EventConnection:Disconnect(); self._EventConnection = nil end
		for _, Service in pairs(self._Services) do destroyProxySignals(Service) end
		self._Services = {}
		self._SignalRoutes = {}
		self._Manifest = {}
		self._RPC = nil
		self._Event = nil
		self._Bootstrap = nil
		self._Folder = nil
		self._Token = nil
		self._ServerReady = false
		self._ManifestReady = false
		self._BootError = nil
	end
end

return ClientBridge;
