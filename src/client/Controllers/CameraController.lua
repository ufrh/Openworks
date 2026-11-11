--!strict
-- Preserve Roblox's native first-person camera and mouse look.
-- Camera FieldOfView uses Z / Shift+Z; wheel belongs to construction tools.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer

local DEFAULT_FOV = 70
local MIN_FOV = 40
local MAX_FOV = 85
local ZOOM_KEY_STEP = 5
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

    -- Z = zoom IN, Shift+Z = zoom OUT. Ctrl+Z remains Undo.
    -- Never capture the scroll wheel; editor mechanics own its adjustments.
    table.insert(self.Connections, UserInputService.InputBegan:Connect(function(input, processed)
        if processed or input.KeyCode~=Enum.KeyCode.Z
            or UserInputService:GetFocusedTextBox() or GuiService.MenuIsOpen
            or player:GetAttribute("OPENWORKS_PlotMenuOpen")==true
            or player:GetAttribute("OPENWORKS_PropertiesOpen")==true then return end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
            or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
            or UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
            or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt) then return end
        local outward=UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
            or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
        self.TargetFov=math.clamp(self.TargetFov
            + (if outward then ZOOM_KEY_STEP else -ZOOM_KEY_STEP),
            MIN_FOV,MAX_FOV)
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
