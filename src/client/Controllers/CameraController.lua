--!strict
-- Preserve Roblox's native first-person camera and mouse look.
-- Mouse wheel affects only FieldOfView, never camera position.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer

local DEFAULT_FOV = 70
local MIN_FOV = 40
local MAX_FOV = 85
local WHEEL_STEP = 5
local SMOOTHING = 15
local RENDER_BINDING = "OPENWORKS_FOV_Zoom"

local CameraController = {}
CameraController.__index = CameraController

function CameraController.new()
    return setmetatable({
        TargetFov = DEFAULT_FOV,
        Connections = {},
        Started = false,
    }, CameraController)
end

function CameraController:Start()
    if self.Started then
        return
    end
    self.Started = true

    player.CameraMode = Enum.CameraMode.LockFirstPerson

    table.insert(self.Connections, player.CharacterAdded:Connect(function()
        player.CameraMode = Enum.CameraMode.LockFirstPerson
    end))

    table.insert(self.Connections, UserInputService.InputChanged:Connect(function(input, processed)
        if input.UserInputType ~= Enum.UserInputType.MouseWheel then
            return
        end
        if UserInputService:GetFocusedTextBox() or GuiService.MenuIsOpen then
            return
        end
        -- Do not zoom behind a UI that has captured the cursor.
        -- In first person, Roblox's camera scripts may mark scroll as processed.
        if UserInputService.MouseBehavior == Enum.MouseBehavior.Default then
            return
        end

        self.TargetFov = math.clamp(
            self.TargetFov - input.Position.Z * WHEEL_STEP,
            MIN_FOV,
            MAX_FOV
        )
    end))

    RunService:BindToRenderStep(
        RENDER_BINDING,
        Enum.RenderPriority.Camera.Value + 1,
        function(dt)
            local camera = workspace.CurrentCamera
            if not camera then
                return
            end

            local alpha = 1 - math.exp(-SMOOTHING * math.min(dt, 0.1))
            camera.FieldOfView += (self.TargetFov - camera.FieldOfView) * alpha
        end
    )
end

function CameraController:Destroy()
    if not self.Started then
        return
    end

    self.Started = false
    RunService:UnbindFromRenderStep(RENDER_BINDING)

    for _, connection in ipairs(self.Connections) do
        connection:Disconnect()
    end
    table.clear(self.Connections)
end

return CameraController
