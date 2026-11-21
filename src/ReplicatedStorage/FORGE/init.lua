-- FORGE 3.2.0 core for OpenWorks. Based on the Ruckus FORGE runtime.
-- Ruckus-specific matchmaking, avatars, progression and UI are omitted.
local RunService = game:GetService("RunService")
local Root = script

local Config = require(Root.Config)
local State = require(Root.Core.State)
local Class = require(Root.Core.Class)
local Registry = require(Root.Core.Registry)
local Loader = require(Root.Core.Loader)
local DependencyGraph = require(Root.Core.DependencyGraph)
local Lifecycle = require(Root.Core.Lifecycle)
local Logger = require(Root.Core.Logger)
local Signal = require(Root.Core.Signal)
local Janitor = require(Root.Core.Janitor)
local Types = require(Root.Shared.Types)
local ClientBridge = require(Root.Network.ClientBridge)

local FORGE = {
    Version = Config.Version,
    Config = Config,
    Types = Types,
    Signal = Signal,
    Janitor = Janitor,
}

function FORGE.Class(kind, definition)
    return Class.Create(kind, definition)
end

function FORGE.Get(name)
    return Registry.Get(name)
end

function FORGE.GetService(name)
    if RunService:IsServer() then
        return Registry.GetService(name)
    end
    assert(State.Bridge, "FORGE has not started")
    return State.Bridge:GetService(name)
end

function FORGE.GetController(name)
    return Registry.GetController(name)
end

local function rebuild()
    local kind = RunService:IsServer() and "Service" or "Controller"
    local ordered = DependencyGraph.Resolve(Registry.List(kind))
    Lifecycle.Init(ordered)
    if RunService:IsServer() and State.Bridge and State.Bridge.RebuildRoutes then
        State.Bridge:RebuildRoutes()
    end
    Lifecycle.Start(ordered)
    State.Ordered = ordered
end

function FORGE.Start(options)
    options = options or {}
    if State.Started then
        return State.BootReport
    end
    assert(not State.Starting, "FORGE is already starting")
    State.Starting = true
    State.Roots = options.Roots or {}

    local ok, result = xpcall(function()
        if RunService:IsClient() then
            State.Bridge = options.Bridge or ClientBridge.new()
        else
            assert(options.Bridge, "FORGE server requires ServerBridge")
            State.Bridge = options.Bridge
        end

        State.Bridge:Start()
        Loader.Load(State.Roots)

        local kind = RunService:IsServer() and "Service" or "Controller"
        local ordered = DependencyGraph.Resolve(Registry.List(kind))
        Lifecycle.Init(ordered)

        if RunService:IsServer() then
            State.Bridge:RebuildRoutes()
        end
        Lifecycle.Start(ordered)
        State.Ordered = ordered

        if RunService:IsServer() then
            State.Bridge:SetReady(true)
        end
        for _, root in ipairs(State.Roots) do
            local connection = Loader.Watch(root, rebuild)
            if connection then
                table.insert(State.Connections, connection)
            end
        end

        State.Started = true
        Logger.Info("Runtime", string.format("FORGE %s started (%s)", Config.Version, State.Environment))
        return State.BootReport
    end, debug.traceback)

    State.Starting = false
    if not ok then
        State.Started = false
        if RunService:IsServer() and State.Bridge and State.Bridge.SetBootError then
            State.Bridge:SetBootError(result)
        end
        error(result)
    end
    return result
end

function FORGE.RegisterMiddleware(name, callback)
    assert(RunService:IsServer(), "server only")
    assert(State.Bridge and State.Bridge.RegisterMiddleware, "FORGE not started")
    State.Bridge:RegisterMiddleware(name, callback)
end

function FORGE.Stop()
    if not State.Started then return end
    Lifecycle.Stop(State.Ordered or {})
    State.Started = false
end

function FORGE.Destroy()
    Lifecycle.Stop(State.Ordered or {})
    Lifecycle.Destroy(State.Ordered or {})
    for _, connection in ipairs(State.Connections) do
        connection:Disconnect()
    end
    State.Connections = {}
    if State.Bridge then State.Bridge:Destroy() end
    State.Bridge = nil
    State.Started = false
    State.Starting = false
end

function FORGE.GetBootReport()
    return State.BootReport
end

return FORGE
