local Config = require(script.Parent.Config)
local State = require(script.Parent.State)
local Logger = require(script.Parent.Logger)

local Lifecycle = {} do
	local function cleanupScope(Component, Destroy)
		local Scope = rawget(Component, '_Scope')
		if not Scope then return end
		if Destroy and type(Scope.Destroy) == 'function' then Scope:Destroy()
		elseif type(Scope.Cleanup) == 'function' then Scope:Cleanup() end
	end

	local function dependencyFailed(Component)
		for _, Name in ipairs(Component._Dependencies) do
			local Dependency = Component.Dependencies[Name]
			if Dependency and Dependency._Failed then return Name end
		end
		return nil;
	end

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

	function Lifecycle.Init(Ordered)
		for _, Component in ipairs(Ordered) do
			if Component._Initialized or Component._Failed then continue end
			local FailedDependency = dependencyFailed(Component)

			if FailedDependency then
				Component._Failed = true
				table.insert(State.BootReport.Skipped, {Component = Component.Name; Reason = 'dependency failed: ' .. FailedDependency;})
				continue
			end

			Component._Destroyed = false
			if callLifecycle(Component, 'Init') then
				Component._Initialized = true
				table.insert(State.BootReport.Initialized, Component.Name)
			end
		end
	end

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

	function Lifecycle.Stop(Ordered)
		for Index = #Ordered, 1, -1 do
			local Component = Ordered[Index]

			if Component._Started then
				if type(Component.Stop) == 'function' then
					callLifecycle(Component, 'Stop')
				elseif type(Component.Destroy) == 'function' then
					callLifecycle(Component, 'Destroy')
					Component._Destroyed = true
					Component._Initialized = false
				end
			end

			cleanupScope(Component, false)
			Component._Started = false
			Component._Failed = false
		end
	end

	function Lifecycle.Destroy(Ordered)
		for Index = #Ordered, 1, -1 do
			local Component = Ordered[Index]
			if not Component._Destroyed and type(Component.Destroy) == 'function' then
				callLifecycle(Component, 'Destroy')
			end
			cleanupScope(Component, true)
			Component._Initialized = false
			Component._Started = false
			Component._Failed = false
			Component._Destroyed = false
		end
	end
end

return Lifecycle;
