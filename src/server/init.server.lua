--!strict
-- OPENWORKS server bootstrap: preserve FORGE, provision tools, start services.

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

print(string.format("[OPENWORKS] FORGE %s | architecture audit / metadata history / guarded plot saves ready", tostring(FORGE.Version)))

game:BindToClose(function()
    FORGE.Shutdown()
end)
