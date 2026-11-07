local Registry = require(script.Parent.Parent.Kernel.Core.Registry)
local State = require(script.Parent.Parent.Kernel.Core.State)
local DependencyGraph = require(script.Parent.Parent.Kernel.Core.DependencyGraph)

local Diagnostics = {} do
	Diagnostics.__index = Diagnostics
	Diagnostics.ClassName = 'Diagnostics'

	local function count(Value)
		local Total = 0
		for _ in pairs(Value or {}) do Total += 1 end
		return Total
	end

	local function copy(Value)
		if type(Value) ~= 'table' then return Value end
		local Result = {}
		for Key, Entry in pairs(Value) do Result[Key] = copy(Entry) end
		return Result
	end

	local function component(Component)
		return {
			Name = Component.Name,
			Kind = Component.Kind,
			Initialized = Component._Initialized == true,
			Started = Component._Started == true,
			Failed = Component._Failed == true,
			Destroyed = Component._Destroyed == true,
			Dependencies = table.clone(Component._Dependencies or {}),
			OptionalDependencies = table.clone(Component._OptionalDependencies or {})
		}
	end

	function Diagnostics.new(Version, Context, Tooling)
		local self = setmetatable({}, Diagnostics)
		self.Version = Version
		self.Context = Context
		self.Tooling = Tooling
		return self
	end

	function Diagnostics:Get(Name)
		local Component = Registry.Get(Name)
		return Component and component(Component) or nil
	end

	function Diagnostics:Graph()
		return DependencyGraph.Snapshot(Registry.List())
	end

	function Diagnostics:Health()
		local Issues = {}

		for _, Component in ipairs(Registry.List()) do
			if Component._Failed then
				table.insert(Issues, {
					Severity = 'Error',
					Code = 'COMPONENT_FAILED',
					Component = Component.Name,
					Message = Component.Name .. ' failed during lifecycle.'
				})
			elseif State.Started and not Component._Started then
				table.insert(Issues, {
					Severity = 'Warning',
					Code = 'COMPONENT_NOT_STARTED',
					Component = Component.Name,
					Message = Component.Name .. ' is registered but not started.'
				})
			end
		end

		for _, Entry in ipairs(State.BootReport.Errors or {}) do
			table.insert(Issues, {
				Severity = 'Error',
				Code = 'BOOT_ERROR',
				Component = Entry.Component,
				Message = tostring(Entry.Error)
			})
		end

		for _, Entry in ipairs(State.BootReport.Skipped or {}) do
			table.insert(Issues, {
				Severity = 'Warning',
				Code = 'BOOT_SKIPPED',
				Component = Entry.Component,
				Message = tostring(Entry.Reason)
			})
		end

		return {
			Healthy = #Issues == 0,
			Issues = Issues
		}
	end

	function Diagnostics:Snapshot()
		local Components = {}
		for _, Component in ipairs(Registry.List()) do table.insert(Components, component(Component)) end
		table.sort(Components, function(A, B) return A.Name < B.Name end)

		local Bridge = State.Bridge
		local ServiceNames = {}
		if Bridge and Bridge._Manifest then
			for Name in pairs(Bridge._Manifest) do table.insert(ServiceNames, Name) end
			table.sort(ServiceNames)
		end
		local Network = {
			Active = Bridge ~= nil,
			Services = Bridge and count(Bridge._Manifest) or 0,
			ServiceNames = ServiceNames,
			Routes = Bridge and count(Bridge._Routes) or 0,
			SignalRoutes = Bridge and count(Bridge._SignalRoutes) or 0,
			Stats = Bridge and copy(Bridge._Stats or {}) or {}
		}

		return {
			Version = self.Version,
			Context = self.Context:Snapshot(),
			Started = State.Started,
			Starting = State.Starting,
			Components = Components,
			Graph = self:Graph(),
			Health = self:Health(),
			Network = Network,
			Tooling = self.Tooling and self.Tooling:Snapshot() or {},
			Boot = copy(State.BootReport)
		}
	end

	function Diagnostics:Print()
		local Snapshot = self:Snapshot()
		local Tooling = Snapshot.Tooling or {}
		local TestCount, FailedTests = 0, 0

		for _, Definition in pairs(Tooling.Tests or {}) do
			TestCount += 1
			if Definition.Last and Definition.Last.Passed == false then FailedTests += 1 end
		end

		print(string.format(
			'[FORGE %s] %s/%s • %d components • %d dependencies • network %s • %d tests/%d failed',
			tostring(Snapshot.Version),
			Snapshot.Context.Environment,
			Snapshot.Context.Side,
			#Snapshot.Components,
			#Snapshot.Graph,
			Snapshot.Network.Active and 'online' or 'offline',
			TestCount,
			FailedTests
		))

		for _, Component in ipairs(Snapshot.Components) do
			local Status = Component.Failed and 'FAILED'
				or Component.Started and 'STARTED'
				or Component.Initialized and 'INITIALIZED'
				or 'REGISTERED'
			print(string.format('  %s • %s • %s', Component.Kind, Component.Name, Status))
		end

		for _, Issue in ipairs(Snapshot.Health.Issues) do
			warn(string.format('  %s • %s • %s', Issue.Severity, Issue.Code, Issue.Message))
		end

		return Snapshot
	end
end

return Diagnostics
