local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local UserInputService = game:GetService('UserInputService')
local ContextActionService = game:GetService('ContextActionService')
local RunService = game:GetService('RunService')

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local Openworks = ReplicatedStorage:WaitForChild('Openworks')
local Geometry = require(Openworks:WaitForChild('BlueprintGeometry'))
local remote = Openworks:WaitForChild('BlueprintEvent')

local Drafting = {}
Drafting.__index = Drafting

local function toolPose(tool, sheet, point)
    local world = sheet.CFrame:PointToWorldSpace(Vector3.new(
        point.X * Geometry.SCALE, sheet.Size.Y * 0.5 + 0.024,
        point.Y * Geometry.SCALE))
    local up = sheet.CFrame.UpVector
    if tool:GetAttribute('DraftingKind') == 'Eraser' then
        return sheet.CFrame * CFrame.new(
            point.X * Geometry.SCALE, sheet.Size.Y * 0.5 + tool.Size.Y * 0.5 + 0.03,
            point.Y * Geometry.SCALE)
    end
    local direction = (up + sheet.CFrame.RightVector * 0.29).Unit
    local center = world + direction * (tool.Size.Z * 0.5)
    return CFrame.lookAt(center, world, sheet.CFrame.LookVector)
end

function Drafting.new()
    local self = setmetatable({}, Drafting)
    self.sheet = nil
    self.pending = false
    self.tool = nil
    self.toolKind = nil
    self.toolFrame = nil
    self.stroke = nil
    self.rulerDrag = nil
    self.lastRulerMove = 0
    self.distance = 7
    self.focus = Vector3.zero
    self.right = false
    self.middle = false
    self.lastPose = 0

    self.selection = Instance.new('Highlight')
    self.selection.Name = 'OpenworksDraftingSelection'
    self.selection.FillTransparency = 1
    self.selection.OutlineColor = Color3.fromRGB(230, 177, 78)
    self.selection.OutlineTransparency = 0.1
    self.selection.Enabled = false
    self.selection.Parent = workspace

    self.preview = Instance.new('Part')
    self.preview.Name = 'OpenworksPencilPreview'
    self.preview.Anchored = true
    self.preview.CanCollide = false
    self.preview.CanTouch = false
    self.preview.CanQuery = false
    self.preview.CastShadow = false
    self.preview.Material = Enum.Material.SmoothPlastic
    self.preview.Color = Color3.fromRGB(44, 91, 142)

    remote.OnClientEvent:Connect(function(action, ...)
        local a, b, c, d = ...
        if action == 'Opened' then
            if not self.pending then
                remote:FireServer('Close')
                return
            end
            self.pending = false
            self.sheet = a
            self.distance = math.max(a.Size.X, a.Size.Z) * 1.55
            self.focus = Vector3.zero
            local camera = workspace.CurrentCamera
            self.cameraType = camera.CameraType
            self.cameraSubject = camera.CameraSubject
            self.cameraFov = camera.FieldOfView
            camera.CameraType = Enum.CameraType.Scriptable
            ContextActionService:BindActionAtPriority('OpenworksDraftMovement',
                function() return Enum.ContextActionResult.Sink end,
                false, 4000, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S,
                Enum.KeyCode.D, Enum.KeyCode.Space,
                Enum.KeyCode.Up, Enum.KeyCode.Down,
                Enum.KeyCode.Left, Enum.KeyCode.Right)
            self.selection.Adornee = a
            self.selection.Enabled = true
            print('[OPENWORKS:Blueprint] Drafting opened. Click the pencil, place the ruler, and trace its edge.')
        elseif action == 'ToolSelected' then
            if not self.sheet then return end
            if self.tool and self.tool.Parent and self.toolFrame then
                self.tool.CFrame = self.toolFrame
            end
            self.tool = a
            self.toolKind = b
            self.toolFrame = a.CFrame
            self.selection.Adornee = a
            self.selection.Enabled = true
            print('[OPENWORKS:Blueprint] Selected', b)
        elseif action == 'ToolPose' then
            if a and a:IsA('BasePart') and a.Parent
                and b and b:IsA('BasePart') and typeof(c) == 'Vector2'
                and d ~= player.UserId then
                a.CFrame = toolPose(a, b, c)
            end
        elseif action == 'Recorded' then
            print('[OPENWORKS:Blueprint] Saved lines:', a)
        elseif action == 'Status' then
            if self.pending then self.pending = false end
            warn('[OPENWORKS:Blueprint] ' .. tostring(a))
        elseif action == 'Closed' then
            self:close(false)
        end
    end)

    UserInputService.InputBegan:Connect(function(input, processed)
        if not self.sheet then return end
        if input.KeyCode == Enum.KeyCode.Escape then
            self:close(true)
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            self.right = true
            self.previousMouseBehavior = UserInputService.MouseBehavior
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
            return
        elseif input.UserInputType == Enum.UserInputType.MouseButton3 then
            self.middle = true
            return
        end
        if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

        local hit = mouse.Target
        if hit and hit:IsA('BasePart')
            and hit:GetAttribute('DraftingKind') == 'Ruler' then
            local localDirection = self.sheet.CFrame:VectorToObjectSpace(
                hit.CFrame.RightVector)
            self.rulerDrag = {
                ruler = hit,
                angle = math.atan2(-localDirection.Z, localDirection.X),
            }
            self.lastRulerMove = 0
            self.selection.Adornee = hit
            remote:FireServer('RulerStart', hit)
            return
        end
        if hit and hit:IsA('BasePart')
            and (hit:GetAttribute('DraftingKind') == 'Pencil'
                or hit:GetAttribute('DraftingKind') == 'Eraser') then
            remote:FireServer('SelectTool', hit)
            return
        end

        local point = self:pointUnderCursor()
        if not point or not self.tool then return end
        if self.toolKind == 'Eraser' then
            remote:FireServer('Erase', point)
            return
        end

        if self.toolKind == 'Pencil' then
            local bestRuler, bestGuide, error
            for _, node in workspace:GetDescendants() do
                if not node:IsA('BasePart')
                    or node:GetAttribute('DraftingKind') ~= 'Ruler' then continue end
                local guide = Geometry.rulerGuide(self.sheet, node, point)
                if guide then
                    local snap = Geometry.snap(guide, point)
                    local distance = (snap - point).Magnitude
                    if not error or distance < error then
                        bestRuler, bestGuide, error = node, guide, distance
                    end
                end
            end
            if not bestGuide then
                warn('[OPENWORKS:Blueprint] Position the physical ruler edge under the pencil first')
                return
            end
            self.stroke = {start = point, current = point,
                ruler = bestRuler, guide = bestGuide}
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if not self.sheet then return end
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            self.right = false
            UserInputService.MouseBehavior =
                self.previousMouseBehavior or Enum.MouseBehavior.Default
            self.previousMouseBehavior = nil
        elseif input.UserInputType == Enum.UserInputType.MouseButton3 then
            self.middle = false
        elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
            if self.rulerDrag then
                self.rulerDrag = nil
                remote:FireServer('RulerEnd')
                self.selection.Adornee = self.tool or self.sheet
                return
            end
            local stroke = self.stroke
            self.stroke = nil
            self.preview.Parent = nil
            if stroke then
                remote:FireServer('Draw', stroke.start, stroke.current, stroke.ruler)
            end
        end
    end)

    UserInputService.InputChanged:Connect(function(input, processed)
        if not self.sheet then return end
        if input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
            if self.rulerDrag then
                self.rulerDrag.angle = (self.rulerDrag.angle
                    + math.rad(5) * input.Position.Z) % (math.pi * 2)
                return
            end
            self.distance = math.clamp(self.distance
                * (if input.Position.Z > 0 then 0.87 else 1.15), 2.2, 23)
        elseif input.UserInputType == Enum.UserInputType.MouseMovement and self.middle then
            local camera = workspace.CurrentCamera
            local scale = self.distance / 650
            self.focus += (-camera.CFrame.RightVector * input.Delta.X
                + camera.CFrame.UpVector * input.Delta.Y) * scale
        end
    end)

    RunService:BindToRenderStep('OpenworksBlueprintCamera',
        Enum.RenderPriority.Camera.Value + 3, function(dt)
            local sheet = self.sheet
            if not sheet then return end
            if not sheet.Parent then self:close(true) return end
            local camera = workspace.CurrentCamera
            if not camera then return end
            camera.CameraType = Enum.CameraType.Scriptable
            local up = sheet.CFrame.UpVector
            local focus = sheet.Position + self.focus
            local target = CFrame.lookAt(focus + up * self.distance
                + sheet.CFrame.LookVector * self.distance * 0.12,
                focus, -sheet.CFrame.LookVector)
            local alpha = 1 - math.exp(-14 * math.min(dt, 0.08))
            camera.CFrame = camera.CFrame:Lerp(target, alpha)
            camera.Focus = CFrame.new(focus)
            camera.FieldOfView += (59 - camera.FieldOfView) * alpha

            local point = self:pointUnderCursor()
            if self.rulerDrag and point and os.clock() - self.lastRulerMove > 1 / 30 then
                self.lastRulerMove = os.clock()
                remote:FireServer('RulerMove', point, self.rulerDrag.angle)
            end
            if self.stroke and point then self.stroke.current = point end
            local activePoint = point
            if self.stroke then
                local stroke = self.stroke
                local a = Geometry.snap(stroke.guide, stroke.start)
                local b = Geometry.snap(stroke.guide, stroke.current)
                activePoint = b
                if (b - a).Magnitude > 0.4 then
                    local localA = Vector3.new(a.X * Geometry.SCALE,
                        sheet.Size.Y * 0.5 + 0.014, a.Y * Geometry.SCALE)
                    local localB = Vector3.new(b.X * Geometry.SCALE,
                        sheet.Size.Y * 0.5 + 0.014, b.Y * Geometry.SCALE)
                    local direction = localB - localA
                    local worldDirection = sheet.CFrame:VectorToWorldSpace(direction.Unit)
                    local center = sheet.CFrame:PointToWorldSpace((localA + localB) * 0.5)
                    self.preview.Size = Vector3.new(direction.Magnitude, 0.012, 0.017)
                    self.preview.CFrame = CFrame.fromMatrix(center, worldDirection,
                        up, worldDirection:Cross(up))
                    self.preview.Parent = workspace
                else
                    self.preview.Parent = nil
                end
            end

            if not self.rulerDrag and self.tool and self.tool.Parent and activePoint then
                self.tool.CFrame = toolPose(self.tool, sheet, activePoint)
                if os.clock() - self.lastPose >= 1 / 20 then
                    self.lastPose = os.clock()
                    remote:FireServer('Pose', activePoint)
                end
            end
        end)

    return self
end

function Drafting:pointUnderCursor()
    local sheet = self.sheet
    local camera = workspace.CurrentCamera
    if not sheet or not camera then return nil end
    local cursor = UserInputService:GetMouseLocation()
    local ray = camera:ViewportPointToRay(cursor.X, cursor.Y)
    local up = sheet.CFrame.UpVector
    local denominator = ray.Direction:Dot(up)
    if math.abs(denominator) < 0.01 then return nil end
    local plane = sheet.Position + up * sheet.Size.Y * 0.5
    local distance = (plane - ray.Origin):Dot(up) / denominator
    if distance < 0 or distance > 130 then return nil end
    local point = Geometry.project(sheet, ray.Origin + ray.Direction * distance)
    return if Geometry.inside(sheet, point) then point else nil
end

function Drafting:open(sheet)
    if self.sheet or self.pending or not sheet
        or sheet:GetAttribute('OnWorkbench') ~= true then return end
    self.pending = true
    remote:FireServer('Open', sheet)
end

function Drafting:isActive()
    return self.sheet ~= nil or self.pending
end

function Drafting:close(notify)
    if notify then remote:FireServer('Close') end
    self.pending = false
    self.stroke = nil
    self.rulerDrag = nil
    self.preview.Parent = nil
    self.selection.Enabled = false
    self.selection.Adornee = nil
    if self.tool and self.tool.Parent and self.toolFrame then
        self.tool.CFrame = self.toolFrame
    end
    self.tool = nil
    self.toolKind = nil
    self.toolFrame = nil
    self.right = false
    self.middle = false
    if self.previousMouseBehavior then
        UserInputService.MouseBehavior = self.previousMouseBehavior
        self.previousMouseBehavior = nil
    end
    if self.sheet then
        self.sheet = nil
        ContextActionService:UnbindAction('OpenworksDraftMovement')
        local camera = workspace.CurrentCamera
        if camera then
            camera.CameraType = self.cameraType or Enum.CameraType.Custom
            if self.cameraSubject then camera.CameraSubject = self.cameraSubject end
            camera.FieldOfView = self.cameraFov or 70
        end
    end
end

return Drafting
