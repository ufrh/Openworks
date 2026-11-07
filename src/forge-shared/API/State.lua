local UIState = require(script.Parent.Parent.Engine.UI.State)
local Replication = require(script.Parent.Parent.Engine.Replication)

local State = {}

local ReplicatedState = {} do
	ReplicatedState.__index = ReplicatedState
	ReplicatedState.ClassName = 'State'

	local function resolveAudience(Value)
		if Value == nil or Value == true or Value == 'All' then return Replication.To.All end
		return Value
	end

	function ReplicatedState.new(Value, Options)
		local self = setmetatable({}, ReplicatedState)
		self._FORGEReplicatedState = true
		self._Local = UIState.new(Value)
		self._Audience = resolveAudience(Options.Replicate)
		self._Service = nil
		self._Name = Options.Name
		self._SignalName = nil
		self._GetName = nil
		self._Version = 0
		self.ReadOnly = false
		self.Changed = self._Local.Changed
		return self
	end

	function ReplicatedState:_Attach(Service, Name)
		assert(not self._Service, 'FORGE replicated State is already attached.')
		assert(Service and Service.Kind == 'Service', 'Replicated State can only attach to a Service.')

		self._Service = Service
		self._Name = self._Name or Name
		self._GetName = '__FORGE_STATE_GET_' .. tostring(Name)
		self._SignalName = '__FORGE_STATE_CHANGED_' .. tostring(Name)

		Service:CreateSignal(self._SignalName)
		Service.Client[self._GetName] = function(Player)
			local Visible = Replication:CanSee(Player, self._Audience)
			return Visible, Visible and self:Get() or nil, self._Version
		end
		Service:ConfigureEndpoint(self._GetName, {Rate = false})

		Service._RemoteStates[Name] = {
			Get = self._GetName,
			Changed = self._SignalName
		}

		Replication:RegisterState(self)
		return self
	end

	function ReplicatedState:Get()
		return self._Local:Get()
	end

	function ReplicatedState:Set(Value)
		local Changed = self._Local:Set(Value)
		if not Changed then return false end
		self._Version += 1
		self:Refresh()
		return true
	end

	function ReplicatedState:Update(Callback)
		assert(type(Callback) == 'function', 'State update requires a function.')
		self:Set(Callback(self:Get()))
		return self:Get()
	end

	function ReplicatedState:Subscribe(Callback, Immediate)
		return self._Local:Subscribe(Callback, Immediate)
	end

	function ReplicatedState:SetAudience(Audience)
		self._Audience = resolveAudience(Audience)
		self:Refresh()
		return self
	end

	ReplicatedState.Audience = ReplicatedState.SetAudience

	function ReplicatedState:Refresh(Targets)
		if not self._Service or not self._SignalName then return self end

		local Players = Targets
		if typeof(Targets) == 'Instance' then Players = {Targets} end
		if type(Players) ~= 'table' then
			Players = game:GetService('Players'):GetPlayers()
		end

		for _, Player in ipairs(Players) do
			local Visible = Replication:CanSee(Player, self._Audience)
			self._Service:FireClient(
				Player,
				self._SignalName,
				Visible,
				Visible and self:Get() or nil,
				self._Version
			)
		end

		return self
	end

	function ReplicatedState:Destroy()
		Replication:UnregisterState(self)
		self._Local:Destroy()
		self._Service = nil
	end
end

function State.new(Value, Options)
	Options = type(Options) == 'table' and Options or {}
	if Options.Replicate == nil and Options.Name == nil then return UIState.new(Value) end
	return ReplicatedState.new(Value, Options)
end

return State
