--!strict
-- OPENWORKS reset baseline. Keep FORGE 4.4.1 and its networking bridge.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local FORGE = require(ReplicatedStorage:WaitForChild("FORGE"))
local ServerBridge = require(ServerScriptService:WaitForChild("FORGE")
    :WaitForChild("Kernel"):WaitForChild("Networking"):WaitForChild("ServerBridge"))
local bridge = ServerBridge.new()
FORGE.Start({ Bridge = bridge, Roots = {} })
print(string.format("[OPENWORKS] FORGE %s | Server baseline ready", tostring(FORGE.Version)))
game:BindToClose(function()
    FORGE.Shutdown()
end)
