-- Author -> lolokdev.
-- Last Edit -> September 13, 2026 8:44 AM CDT

local Config = require(script.Parent.Parent.Config)
local State = require(script.Parent.State)
local Logger = require(script.Parent.Logger)

local Lifecycle = {} do
	-- dependencyFailed -> string?
	-- Finds the first failed hard dependency for a component.
	-- @param Component, table -> Component being checked.
	local function dependencyFailed(Component)
		for _, Name in ipairs(Component._Dependencies) do
			local Dependency = Component.Dependencies[Name]
			if Dependency and Dependency._Failed then return Name end
		end
		return nil;
	end

	-- callLifecycle -> boolean
	-- Executes one lifecycle method with traceback-based error isolation.
	-- @param Component, table -> Component receiving the call.
	-- @param MethodName, string -> Init, Start, Stop or Destroy.
	local function callLifecycle(Component, MethodName)
		local Method = Component[MethodName]
		if type(Method) ~= 'function' then return true end

		local Success, Result = xpcall(function() return Method(Component) end, debug.traceback)
		if Success then return true end

		Component._Failed = true
		table.insert(State.BootReport.Errors, {Component = Component.Name; Method = MethodName; Error = Result;})
		Logger.Warn(Component.Name, Result)
		if Config.Runtime.FailFast then error(Result) end
		return false;
	end

	-- Init -> nil
	-- Initializes ordered components after dependencies have been injected.
	-- @param Ordered, {table} -> Topologically sorted components.
	function Lifecycle.Init(Ordered)
		for _, Component in ipairs(Ordered) do
			if Component._Initialized or Component._Failed then continue end
			local FailedDependency = dependencyFailed(Component)

			if FailedDependency then
				Component._Failed = true
				table.insert(State.BootReport.Skipped, {Component = Component.Name; Reason = 'dependency failed: ' .. FailedDependency;})
				continue
			end

			if callLifecycle(Component, 'Init') then
				Component._Initialized = true
				table.insert(State.BootReport.Initialized, Component.Name)
			end
		end
	end

	-- Start -> nil
	-- Starts initialized components in dependency order.
	-- @param Ordered, {table} -> Topologically sorted components.
	function Lifecycle.Start(Ordered)
		for _, Component in ipairs(Ordered) do
			if Component._Started or Component._Failed or not Component._Initialized then continue end
			local FailedDependency = dependencyFailed(Component)

			if FailedDependency then
				Component._Failed = true
				table.insert(State.BootReport.Skipped, {Component = Component.Name; Reason = 'dependency failed: ' .. FailedDependency;})
				continue
			end

			if callLifecycle(Component, 'Start') then
				Component._Started = true
				table.insert(State.BootReport.Started, Component.Name)
			end
		end
	end

	-- Stop -> nil
	-- Stops started components in reverse dependency order.
	-- @param Ordered, {table} -> Current component order.
	function Lifecycle.Stop(Ordered)
		for Index = #Ordered, 1, -1 do
			local Component = Ordered[Index]
			if not Component._Started then continue end
			callLifecycle(Component, 'Stop')
			Component._Started = false
		end
	end

	-- Destroy -> nil
	-- Destroys components in reverse dependency order.
	-- @param Ordered, {table} -> Current component order.
	function Lifecycle.Destroy(Ordered)
		for Index = #Ordered, 1, -1 do
			local Component = Ordered[Index]
			if type(Component.Destroy) == 'function' then callLifecycle(Component, 'Destroy') end
			Component._Initialized = false
			Component._Started = false
		end
	end
end

return Lifecycle;
