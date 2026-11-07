-- Author -> lolokdev.
-- Last Edit -> September 14, 2026 4:25 PM CDT

local RunService = game:GetService('RunService')

local Config = require(script.Parent.Config)
local State = require(script.Parent.State)
local Logger = require(script.Parent.Logger)

local Loader = {} do
	local Required = setmetatable({}, {__mode = 'k'})

	-- loadModule -> any
	-- Raw require callback used by xpcall.
	-- @param Module, ModuleScript -> Module being required.
	local function loadModule(Module)
		return require(Module);
	end

	-- requireModule -> any
	-- Requires one application ModuleScript with isolated error reporting.
	-- @param Module, ModuleScript -> Module being loaded.
	local function requireModule(Module)
		if Required[Module] then return nil end
		Required[Module] = true

		local Success, Result = xpcall(loadModule, debug.traceback, Module)
		if Success then
			table.insert(State.BootReport.Loaded, Module:GetFullName())
			return Result
		end

		table.insert(State.BootReport.Errors, {Component = Module:GetFullName(); Method = 'Require'; Error = Result;})
		Logger.Warn('Loader', Result)
		if Config.Runtime.FailFast then error(Result) end
		return nil;
	end

	-- LoadRoot -> nil
	-- Recursively requires ModuleScripts under one application root.
	-- @param Root, Instance? -> Root folder or ModuleScript.
	function Loader.LoadRoot(Root)
		if not Root then
			if not Config.Runtime.AllowMissingRoots then error('FORGE loader received a missing root.') end
			return
		end

		if Root:IsA('ModuleScript') then requireModule(Root); return end
		local Modules = {}
		for _, Object in ipairs(Root:GetDescendants()) do if Object:IsA('ModuleScript') then table.insert(Modules, Object) end end
		table.sort(Modules, function(A, B) return A:GetFullName() < B:GetFullName() end)
		for _, Module in ipairs(Modules) do requireModule(Module) end
	end

	-- Load -> nil
	-- Loads every configured application root.
	-- @param Roots, {Instance} -> Roots to scan.
	function Loader.Load(Roots)
		for _, Root in ipairs(Roots or {}) do Loader.LoadRoot(Root) end
	end

	-- Watch -> RBXScriptConnection?
	-- Hot-registers newly inserted ModuleScripts in Studio development sessions.
	-- @param Root, Instance? -> Root to observe.
	-- @param Callback, function -> Called after a new module is required.
	function Loader.Watch(Root, Callback)
		if not Root or not RunService:IsStudio() or not Config.Runtime.HotRegistration then return nil end

		-- finishAdded -> nil
		-- Requires one newly-added module after Studio finishes parenting it.
		-- @param Object, ModuleScript -> New module.
		local function finishAdded(Object)
			requireModule(Object)
			if Callback then Callback(Object) end
		end

		-- onAdded -> nil
		-- Defers one new ModuleScript into the hot-registration pipeline.
		-- @param Object, Instance -> Newly-descended instance.
		local function onAdded(Object)
			if not Object:IsA('ModuleScript') then return end
			task.defer(finishAdded, Object)
		end

		return Root.DescendantAdded:Connect(onAdded);
	end
end

return Loader;
