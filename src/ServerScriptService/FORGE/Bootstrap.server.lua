local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local FORGE = require(ReplicatedStorage:WaitForChild("FORGE"))
local ServerBridge = require(script.Parent.Network.ServerBridge)
local bridge = ServerBridge.new()

local ok, err = xpcall(function()
    FORGE.Start({
        Roots = { ServerScriptService:WaitForChild(FORGE.Config.Paths.ServerServices) },
        Bridge = bridge,
    })
end, debug.traceback)
if not ok then
    warn("[OpenWorks] FORGE server startup failed: " .. tostring(err))
    error(err)
end

game:BindToClose(function()
    FORGE.Destroy()
end)
