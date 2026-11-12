--!strict
-- OPENWORKS permanent construction free camera.
-- Scriptable locked-mouse freecam. Native Roblox
-- Tools, Backpack and UI remain fully active. Character is immobile on server.
-- Mouse: always look, WASD: fly, Space/Ctrl: elevate, Z/Shift+Z: FOV.
-- Frame-rate independent response curves smooth motion without softening
-- precise construction aim or dragging the view after a UI opens.
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
-- Smooth acceleration, firm braking, responsive aiming and soft zoom.
-- The coefficients are inverse-seconds (higher = faster settling).
local ACCEL_RESPONSE=15
local BRAKE_RESPONSE=27
local LOOK_RESPONSE=26
local ZOOM_RESPONSE=17
local MAX_CAMERA_DT=0.06

local function response(rate,dt)
    return 1-math.exp(-rate*dt)
end

local function shortestAngle(from,to)
    return math.atan2(math.sin(to-from),math.cos(to-from))
end

local Camera={}
Camera.__index=Camera

local function uiCapturesPointer()
    return GuiService.MenuIsOpen
        or UIS:GetFocusedTextBox()~=nil
        or player:GetAttribute("OPENWORKS_PlotMenuOpen")==true
        or player:GetAttribute("OPENWORKS_AssemblyNaming")==true
        or player:GetAttribute("OPENWORKS_PropertiesOpen")==true
        or player:GetAttribute("OPENWORKS_ExplorerOpen")==true
        or player:GetAttribute("OPENWORKS_CursorUIOpen")==true
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
        Position=nil,Velocity=Vector3.zero,
        Pitch=math.rad(-35),Yaw=math.rad(45),
        TargetPitch=math.rad(-35),TargetYaw=math.rad(45),
        TargetFov=DEFAULT_FOV,CurrentFov=DEFAULT_FOV,
        InputBlocked=false,
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
    -- Restore the default elevated freecam start, without the previous
    -- head-position spawn handshake.
    local target=origin+Vector3.new(0,3,0)
    self.Position=clampToPlot(origin+Vector3.new(13,17,19))
    local dir=(target-self.Position).Unit
    self.Yaw=math.atan2(-dir.X,-dir.Z)
    self.Pitch=math.asin(math.clamp(dir.Y,-0.98,0.98))
    -- Teleports / plot assignment must not spring from the prior plot.
    self.TargetYaw=self.Yaw
    self.TargetPitch=self.Pitch
    self.Velocity=Vector3.zero
    self.CurrentFov=self.TargetFov
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
            cam.FieldOfView=self.CurrentFov
        end
    end
    cameraChanged()
    table.insert(self.Connections,workspace:GetPropertyChangedSignal(
        "CurrentCamera"):Connect(cameraChanged))
    table.insert(self.Connections,player.CharacterAdded:Connect(function()
        player.CameraMode=Enum.CameraMode.Classic
        cameraChanged()
    end))
    table.insert(self.Connections,player:GetAttributeChangedSignal(
        "OPENWORKS_PlotOrigin"):Connect(function()
            self:ResetPosition()
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
        local step=math.clamp(dt,0,MAX_CAMERA_DT)
        local inputBlocked=uiCapturesPointer()
        local delta=UIS:GetMouseDelta()
        if inputBlocked then
            -- Opening a modal must NEVER keep coasting, turning or moving
            -- the camera behind the user's unlocked pointer.
            self.Velocity=Vector3.zero
            self.TargetYaw=self.Yaw
            self.TargetPitch=self.Pitch
        else
            -- Accumulate RAW pixels; smooth the view rather than the mouse
            -- delta itself. This avoids frame-rate-dependent aim overshoot.
            self.TargetYaw-=delta.X*LOOK_SENSITIVITY
            self.TargetPitch=math.clamp(
                self.TargetPitch-delta.Y*LOOK_SENSITIVITY,
                math.rad(-88),math.rad(88))
            local turn=response(LOOK_RESPONSE,step)
            self.Yaw+=shortestAngle(self.Yaw,self.TargetYaw)*turn
            self.Pitch+=(self.TargetPitch-self.Pitch)*turn
            -- Keep unbounded turns numerically stable after long sessions.
            self.TargetYaw=self.Yaw+shortestAngle(self.Yaw,self.TargetYaw)
        end
        self.InputBlocked=inputBlocked

        local rotation=CFrame.fromEulerAnglesYXZ(self.Pitch,self.Yaw,0)
        local forward=rotation.LookVector
        local right=rotation.RightVector
        local up=Vector3.yAxis
        if not inputBlocked then
            local desired=Vector3.zero
            if UIS:IsKeyDown(Enum.KeyCode.W) then desired+=forward end
            if UIS:IsKeyDown(Enum.KeyCode.S) then desired-=forward end
            if UIS:IsKeyDown(Enum.KeyCode.D) then desired+=right end
            if UIS:IsKeyDown(Enum.KeyCode.A) then desired-=right end
            if UIS:IsKeyDown(Enum.KeyCode.Space) then desired+=up end
            -- Ctrl descends; leave all editing shortcuts and bindings intact.
            if UIS:IsKeyDown(Enum.KeyCode.LeftControl)
                or UIS:IsKeyDown(Enum.KeyCode.RightControl) then
                desired-=up
            end
            if desired.Magnitude>0 then
                local speed=if UIS:IsKeyDown(Enum.KeyCode.LeftShift)
                    or UIS:IsKeyDown(Enum.KeyCode.RightShift)
                    then FAST_SPEED else MOVE_SPEED
                desired=desired.Unit*speed
            end
            local rate=if desired.Magnitude>0
                then ACCEL_RESPONSE else BRAKE_RESPONSE
            self.Velocity=self.Velocity:Lerp(desired,response(rate,step))
            -- Finish stopping cleanly; avoid subpixel drift after release.
            if desired.Magnitude==0 and self.Velocity.Magnitude<0.04 then
                self.Velocity=Vector3.zero
            end
            local proposed=self.Position+self.Velocity*step
            local clamped=clampToPlot(proposed)
            -- Do not store outward velocity against plot boundaries.
            self.Velocity=Vector3.new(
                if math.abs(clamped.X-proposed.X)>0.00001
                    then 0 else self.Velocity.X,
                if math.abs(clamped.Y-proposed.Y)>0.00001
                    then 0 else self.Velocity.Y,
                if math.abs(clamped.Z-proposed.Z)>0.00001
                    then 0 else self.Velocity.Z)
            self.Position=clamped
        end
        self.CurrentFov+=(self.TargetFov-self.CurrentFov)
            *response(ZOOM_RESPONSE,step)
        if math.abs(self.TargetFov-self.CurrentFov)<0.005 then
            self.CurrentFov=self.TargetFov
        end

        camera.CFrame=CFrame.new(self.Position)*rotation
        camera.Focus=CFrame.new(self.Position+rotation.LookVector*24)
        camera.FieldOfView=self.CurrentFov
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
    UIS.MouseBehavior=Enum.MouseBehavior.Default
    UIS.MouseIconEnabled=true
    local camera=workspace.CurrentCamera
    if camera then camera.CameraType=Enum.CameraType.Custom end
end

return Camera
