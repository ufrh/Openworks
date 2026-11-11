--!strict
-- OPENWORKS phase 01: preserve FORGE 4.4.1 and supply native Tools.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local FORGE = require(ReplicatedStorage:WaitForChild("FORGE"))
local ServerBridge = require(ServerScriptService:WaitForChild("FORGE")
    :WaitForChild("Kernel"):WaitForChild("Networking"):WaitForChild("ServerBridge"))

local runtime = script:WaitForChild("Runtime")
local provisioner = require(runtime:WaitForChild("NativeToolProvisioner"))
local ConstructionService = require(runtime:WaitForChild("ConstructionService"))

local bridge = ServerBridge.new()
FORGE.Start({ Bridge = bridge, Roots = {} })
provisioner.Start()
ConstructionService.Start()

print(string.format("[OPENWORKS] FORGE %s | Phase 14 owned plots / explicit persistence ready", tostring(FORGE.Version)))

game:BindToClose(function()
    FORGE.Shutdown()
end)
