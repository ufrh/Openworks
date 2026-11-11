--!strict
-- OPENWORKS permanent construction free camera.
-- Scriptable locked-mouse freecam. Native Roblox
-- Tools, Backpack and UI remain fully active. Character is immobile on server.
-- Mouse: always look, WASD: fly, Space/Ctrl: elevate, Z/Shift+Z: FOV.
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
local LOOK_RESPONSE=22
local POSITION_RESPONSE=18

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
        Position=nil,ViewPosition=nil,
        Pitch=math.rad(-15),Yaw=math.rad(0),
        ViewPitch=nil,ViewYaw=nil,
        TargetFov=DEFAULT_FOV,Rotating=false,Panning=false,
        Connections={},CharacterConnections={},Started=false,
    },Camera)
end

function Camera:ResetPosition(character)
    character=character or player.Character
    local head=character and character:FindFirstChild("Head")
    local root=character and character:FindFirstChild("HumanoidRootPart")
    local origin=player:GetAttribute("OPENWORKS_PlotOrigin")
    local spawn=if head and head:IsA("BasePart") then head.Position
        elseif root and root:IsA("BasePart") then
            root.Position+Vector3.new(0,1.5,0)
        elseif typeof(origin)=="Vector3" then
            origin+Vector3.new(0,6.5,0)
        else Vector3.new(0,6.5,0)
    -- Spawn at the actual character's head, not an elevated arbitrary
    -- 3/4-view offset. Start looking horizontally in the character's
    -- facing direction, but no character movement follows the camera.
    self.Position=clampToPlot(spawn)
    self.ViewPosition=self.Position
    if root and root:IsA("BasePart") then
        local dir=root.CFrame.LookVector
        self.Yaw=math.atan2(-dir.X,-dir.Z)
    else
        self.Yaw=0
    end
    self.Pitch=0
    self.ViewYaw=self.Yaw
    self.ViewPitch=self.Pitch
end

function Camera:BindCharacter(character)
    for _,connection in ipairs(self.CharacterConnections) do
        connection:Disconnect()
    end
    table.clear(self.CharacterConnections)
    local function resetWhenReady()
        -- PlotService signals only AFTER positioning the rooted avatar.
        -- Without this handshake, spawn may reset to the old pre-teleport
        -- character position and move again when replication catches up.
        if character:GetAttribute("OPENWORKS_CameraSpawnReady")~=true then
            return
        end
        if character~=player.Character then return end
        local head=character:FindFirstChild("Head")
        if head and head:IsA("BasePart") then
            self:ResetPosition(character)
        end
    end
    table.insert(self.CharacterConnections,
        character:GetAttributeChangedSignal(
            "OPENWORKS_CameraSpawnReady"):Connect(resetWhenReady))
    table.insert(self.CharacterConnections,
        character.ChildAdded:Connect(function(child)
            if child.Name=="Head" then resetWhenReady() end
        end))
    resetWhenReady()
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
    table.insert(self.Connections,player.CharacterAdded:Connect(function(character)
        player.CameraMode=Enum.CameraMode.Classic
        cameraChanged()
        self:BindCharacter(character)
    end))
    if player.Character then self:BindCharacter(player.Character) end
    table.insert(self.Connections,player:GetAttributeChangedSignal(
        "OPENWORKS_PlotOrigin"):Connect(function()
            if not player.Character
                or player.Character:GetAttribute(
                    "OPENWORKS_CameraSpawnReady")~=true then
                self:ResetPosition()
            end
        end))

    table.insert(self.Connections,UIS.InputBegan:Connect(function(input,processed)
        if processed or uiCapturesPointer() then return end
        if input.KeyCode==Enum.KeyCode.Z then
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
    RunService:BindToRenderStep(RENDER_BINDING,
        Enum.RenderPriority.Camera.Value+1,function(dt)
        local camera=workspace.CurrentCamera
        if not camera then return end
        if camera.CameraType~=Enum.CameraType.Scriptable then
            camera.CameraType=Enum.CameraType.Scriptable
        end
        if not self.Position then self:ResetPosition() end
        if not self.ViewPosition then self.ViewPosition=self.Position end
        local inputBlocked=uiCapturesPointer()
        local delta=UIS:GetMouseDelta()
        if not inputBlocked then
            self.Yaw-=delta.X*LOOK_SENSITIVITY
            self.Pitch=math.clamp(self.Pitch-delta.Y*LOOK_SENSITIVITY,
                math.rad(-88),math.rad(88))
        end
        local rotation=CFrame.fromEulerAnglesYXZ(self.Pitch,self.Yaw,0)
        local forward=rotation.LookVector
        local right=rotation.RightVector
        local up=Vector3.yAxis
        if not inputBlocked then
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
        end
        self.Position=clampToPlot(self.Position)
        -- Light exponential smoothing, with immediate pointer capture.
        -- No long tails or cinematic easing that would impede editing.
        local lookAlpha=1-math.exp(-LOOK_RESPONSE*math.min(dt,0.1))
        local moveAlpha=1-math.exp(-POSITION_RESPONSE*math.min(dt,0.1))
        self.ViewYaw=self.ViewYaw
            +math.atan2(math.sin(self.Yaw-self.ViewYaw),
                math.cos(self.Yaw-self.ViewYaw))*lookAlpha
        self.ViewPitch+=(self.Pitch-self.ViewPitch)*lookAlpha
        self.ViewPosition=self.ViewPosition:Lerp(self.Position,moveAlpha)
        local viewRotation=CFrame.fromEulerAnglesYXZ(
            self.ViewPitch,self.ViewYaw,0)
        camera.CFrame=CFrame.new(self.ViewPosition)*viewRotation
        camera.Focus=CFrame.new(self.ViewPosition+viewRotation.LookVector*24)
        camera.FieldOfView=self.TargetFov
    end)
    RunService:BindToRenderStep(RENDER_BINDING.."_Pointer",
        Enum.RenderPriority.Camera.Value+3,function()
        if uiCapturesPointer() then
            UIS.MouseBehavior=Enum.MouseBehavior.Default
            UIS.MouseIconEnabled=true
        else
            UIS.MouseBehavior=Enum.MouseBehavior.LockCenter
            UIS.MouseIconEnabled=false
        end
    end)
end

function Camera:Destroy()
    if not self.Started then return end
    self.Started=false
    RunService:UnbindFromRenderStep(RENDER_BINDING)
    RunService:UnbindFromRenderStep(RENDER_BINDING.."_Pointer")
    for _,connection in ipairs(self.Connections) do
        connection:Disconnect()
    end
    table.clear(self.Connections)
    for _,connection in ipairs(self.CharacterConnections) do
        connection:Disconnect()
    end
    table.clear(self.CharacterConnections)
    UIS.MouseBehavior=Enum.MouseBehavior.Default
    UIS.MouseIconEnabled=true
    local camera=workspace.CurrentCamera
    if camera then camera.CameraType=Enum.CameraType.Custom end
end

return Camera
