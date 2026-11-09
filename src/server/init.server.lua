--!strict
-- OPENWORKS phase 01: preserve FORGE 4.4.1 and supply native Tools.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local FORGE = require(ReplicatedStorage:WaitForChild("FORGE"))
local ServerBridge = require(ServerScriptService:WaitForChild("FORGE")
    :WaitForChild("Kernel"):WaitForChild("Networking"):WaitForChild("ServerBridge"))

local provisioner = require(script:WaitForChild("Runtime"):WaitForChild("NativeToolProvisioner"))

local bridge = ServerBridge.new()
FORGE.Start({ Bridge = bridge, Roots = {} })
provisioner.Start()

print(string.format("[OPENWORKS] FORGE %s | Phase 01 server ready", tostring(FORGE.Version)))

game:BindToClose(function()
    FORGE.Shutdown()
end)
