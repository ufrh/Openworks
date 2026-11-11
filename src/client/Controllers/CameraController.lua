--!strict
-- OPENWORKS permanent construction free camera.
-- Scriptable and immediate-response (no camera inertia). Native Roblox
-- Tools, Backpack and UI remain fully active. Character is immobile on server.
-- RMB: look, MMB: pan, WASD: fly, Space/Ctrl: elevate, Z/Shift+Z: FOV.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UIS=game:GetService("UserInputService")
local GuiService=game:GetService("GuiService")

local player=Players.LocalPlayer
local RENDER_BINDING="OPENWORKS_PermanentFreeCamera"
local DEFAULT_FOV=70
local MIN_FOV=40
local MAX_FOV=85
local FOV_STEP=5
local MOVE_SPEED=22
local FAST_SPEED=44
local LOOK_SENSITIVITY=0.0036
local PAN_SENSITIVITY=0.022

local Camera={}
Camera.__index=Camera

local function uiCapturesPointer()
    return GuiService.MenuIsOpen
        or UIS:GetFocusedTextBox()~=nil
        or player:GetAttribute("OPENWORKS_PlotMenuOpen")==true
        or player:GetAttribute("OPENWORKS_AssemblyNaming")==true
        or player:GetAttribute("OPENWORKS_PropertiesOpen")==true
        or player:GetAttribute("OPENWORKS_PropertiesLooking")==true
        or player:GetAttribute("OPENWORKS_CrankActive")==true
end

local function clampToPlot(position)
    local origin=player:GetAttribute("OPENWORKS_PlotOrigin")
    local half=player:GetAttribute("OPENWORKS_PlotHalfSize")
    if typeof(origin)~="Vector3" or type(half)~="number" then
        return position
    end
    local range=math.max(8,half-2)
    return Vector3.new(
        math.clamp(position.X,origin.X-range,origin.X+range),
        math.clamp(position.Y,origin.Y+2,origin.Y+88),
        math.clamp(position.Z,origin.Z-range,origin.Z+range))
end

function Camera.new()
    return setmetatable({
        Position=nil,Pitch=math.rad(-35),Yaw=math.rad(45),
        TargetFov=DEFAULT_FOV,Rotating=false,Panning=false,
        Connections={},Started=false,
    },Camera)
end

function Camera:ResetPosition()
    local origin=player:GetAttribute("OPENWORKS_PlotOrigin")
    if typeof(origin)~="Vector3" then
        local character=player.Character
        local root=character and character:FindFirstChild("HumanoidRootPart")
        origin=if root then root.Position-Vector3.new(0,5,0)
            else Vector3.zero
    end
    -- Start with a practical elevated, angled view of the work area.
    local target=origin+Vector3.new(0,3,0)
    self.Position=clampToPlot(origin+Vector3.new(13,17,19))
    local dir=(target-self.Position).Unit
    self.Yaw=math.atan2(-dir.X,-dir.Z)
    self.Pitch=math.asin(math.clamp(dir.Y,-0.98,0.98))
end

function Camera:Start()
    if self.Started then return end
    self.Started=true
    player.CameraMode=Enum.CameraMode.Classic
    self:ResetPosition()
    local function cameraChanged()
        local cam=workspace.CurrentCamera
        if cam then
            cam.CameraType=Enum.CameraType.Scriptable
            cam.FieldOfView=self.TargetFov
        end
    end
    cameraChanged()
    table.insert(self.Connections,workspace:GetPropertyChangedSignal(
        "CurrentCamera"):Connect(cameraChanged))
    table.insert(self.Connections,player.CharacterAdded:Connect(function()
        -- No first-person lock ever returns on respawn.
        player.CameraMode=Enum.CameraMode.Classic
        cameraChanged()
    end))
    table.insert(self.Connections,player:GetAttributeChangedSignal(
        "OPENWORKS_PlotOrigin"):Connect(function()
            self:ResetPosition()
        end))

    table.insert(self.Connections,UIS.InputBegan:Connect(function(input,processed)
        if processed or uiCapturesPointer() then return end
        if input.UserInputType==Enum.UserInputType.MouseButton2 then
            self.Rotating=true
        elseif input.UserInputType==Enum.UserInputType.MouseButton3 then
            self.Panning=true
        elseif input.KeyCode==Enum.KeyCode.Z then
            if UIS:IsKeyDown(Enum.KeyCode.LeftControl)
                or UIS:IsKeyDown(Enum.KeyCode.RightControl)
                or UIS:IsKeyDown(Enum.KeyCode.LeftAlt)
                or UIS:IsKeyDown(Enum.KeyCode.RightAlt) then return end
            local outward=UIS:IsKeyDown(Enum.KeyCode.LeftShift)
                or UIS:IsKeyDown(Enum.KeyCode.RightShift)
            self.TargetFov=math.clamp(self.TargetFov
                +(if outward then FOV_STEP else -FOV_STEP),
                MIN_FOV,MAX_FOV)
        end
    end))
    table.insert(self.Connections,UIS.InputEnded:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton2 then
            self.Rotating=false
        elseif input.UserInputType==Enum.UserInputType.MouseButton3 then
            self.Panning=false
        end
    end))

    RunService:BindToRenderStep(RENDER_BINDING,
        Enum.RenderPriority.Camera.Value+1,function(dt)
        local camera=workspace.CurrentCamera
        if not camera then return end
        if camera.CameraType~=Enum.CameraType.Scriptable then
            camera.CameraType=Enum.CameraType.Scriptable
        end
        if not self.Position then self:ResetPosition() end
        local inputBlocked=uiCapturesPointer()
        local delta=UIS:GetMouseDelta()
        if not inputBlocked and self.Rotating then
            self.Yaw-=delta.X*LOOK_SENSITIVITY
            self.Pitch=math.clamp(self.Pitch-delta.Y*LOOK_SENSITIVITY,
                math.rad(-88),math.rad(88))
        end
        local rotation=CFrame.fromEulerAnglesYXZ(self.Pitch,self.Yaw,0)
        local forward=rotation.LookVector
        local right=rotation.RightVector
        local up=Vector3.yAxis
        if not inputBlocked then
            if self.Panning then
                self.Position-=right*delta.X*PAN_SENSITIVITY
                self.Position+=rotation.UpVector*delta.Y*PAN_SENSITIVITY
            end
            local horizontal=Vector3.zero
            if UIS:IsKeyDown(Enum.KeyCode.W) then horizontal+=forward end
            if UIS:IsKeyDown(Enum.KeyCode.S) then horizontal-=forward end
            if UIS:IsKeyDown(Enum.KeyCode.D) then horizontal+=right end
            if UIS:IsKeyDown(Enum.KeyCode.A) then horizontal-=right end
            if UIS:IsKeyDown(Enum.KeyCode.Space) then horizontal+=up end
            -- Ctrl is a height modifier only without the Z/Y/D
            -- edit/history shortcuts. A held Ctrl can lower the camera.
            if UIS:IsKeyDown(Enum.KeyCode.LeftControl)
                or UIS:IsKeyDown(Enum.KeyCode.RightControl) then
                horizontal-=up
            end
            if horizontal.Magnitude>0 then
                local speed=if UIS:IsKeyDown(Enum.KeyCode.LeftShift)
                    or UIS:IsKeyDown(Enum.KeyCode.RightShift)
                    then FAST_SPEED else MOVE_SPEED
                self.Position+=horizontal.Unit*speed*math.min(dt,0.1)
            end
        else
            self.Rotating=false
            self.Panning=false
        end
        self.Position=clampToPlot(self.Position)
        camera.CFrame=CFrame.new(self.Position)*rotation
        camera.Focus=CFrame.new(self.Position+forward*24)
        camera.FieldOfView=self.TargetFov
    end)
end

function Camera:Destroy()
    if not self.Started then return end
    self.Started=false
    RunService:UnbindFromRenderStep(RENDER_BINDING)
    for _,connection in ipairs(self.Connections) do
        connection:Disconnect()
    end
    table.clear(self.Connections)
    local camera=workspace.CurrentCamera
    if camera then camera.CameraType=Enum.CameraType.Custom end
end

return Camera
