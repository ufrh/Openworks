local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FORGE = require(ReplicatedStorage:WaitForChild("FORGE"))

local controllers = Players.LocalPlayer:WaitForChild("PlayerScripts")
    :WaitForChild(FORGE.Config.Paths.ClientControllers)
FORGE.Start({ Roots = { controllers } })
