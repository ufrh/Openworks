--!strict
-- Phase 06: temporary native-physics simulation of a connected mechanism.
-- Authored geometry remains anchored/unchanged; simulation uses server-owned
-- clones with welded rigid components and live Hinge/Prismatic/Weld joints.
-- Stop destroys every simulation object and restores original visibility.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Alignment = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("AlignmentMath"))

local Simulation = {}
Simulation.__index = Simulation

local MAX_PARTS = 128
local MAX_JOINTS = 64
local MAX_COLLISION_PAIRS = 1200

local function bodyKey(model)
    local component = model:GetAttribute("ComponentId")
    if type(component) == "string" and component ~= "" then
        return "c:" .. component
    end
    return "p:" .. tostring(model:GetAttribute("InstanceId"))
end

local function axisFrame(position, axis)
    local x = axis.Unit
    local ref = if math.abs(x:Dot(Vector3.yAxis)) > 0.9
        then Vector3.zAxis else Vector3.yAxis
    local y = (ref - x * ref:Dot(x)).Unit
    return CFrame.fromMatrix(position, x, y, x:Cross(y))
end

local function allParts(model)
    local parts = {}
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then table.insert(parts, part) end
    end
    return parts
end

local function setMotor(constraint, on)
    if constraint:IsA("HingeConstraint") then
        constraint.ActuatorType = if on then Enum.ActuatorType.Motor
            else Enum.ActuatorType.None
        constraint.AngularVelocity = 1.5
        constraint.MotorMaxTorque = 50000
    elseif constraint:IsA("PrismaticConstraint") then
        constraint.ActuatorType = if on then Enum.ActuatorType.Motor
            else Enum.ActuatorType.None
        constraint.Speed = 0.75
        constraint.MotorMaxForce = 50000
    end
end

function Simulation.new(deps)
    local world = workspace:FindFirstChild("OPENWORKS_Simulated")
    if not world then
        world = Instance.new("Folder")
        world.Name = "OPENWORKS_Simulated"
        world.Parent = workspace
    end
    return setmetatable({ D = deps, World = world, Sessions = {} }, Simulation)
end

function Simulation:IsRunning(player)
    return self.Sessions[player] ~= nil
end

function Simulation:SetStatus(player, running, motorsOn)
    player:SetAttribute("OPENWORKS_Simulating", running)
    player:SetAttribute("OPENWORKS_MotorOn", motorsOn)
end

function Simulation:Graph(player, seed)
    local d = self.D
    local owned = {}
    local bodies = {}
    for _, model in ipairs(d.folder:GetChildren()) do
        if model:IsA("Model") and model:GetAttribute("OwnerUserId") == player.UserId then
            local id = model:GetAttribute("InstanceId")
            if type(id) == "string" then
                owned[id] = model
                local key = bodyKey(model)
                if not bodies[key] then bodies[key] = {} end
                table.insert(bodies[key], model)
            end
        end
    end

    local seedKey = bodyKey(seed)
    if not bodies[seedKey] then return nil, "Selected body is missing" end
    local edges = {}
    local adjacent = {}
    for _, relation in ipairs(d.mechanical.Folder:GetChildren()) do
        if relation:IsA("Folder")
            and relation:GetAttribute("OwnerUserId") == player.UserId then
            local source = owned[relation:GetAttribute("SourceId")]
            local target = owned[relation:GetAttribute("TargetId")]
            local kind = relation:GetAttribute("Kind")
            if source and target
                and (kind == "Bearing" or kind == "Slider" or kind == "Fixed") then
                local a, b = bodyKey(source), bodyKey(target)
                if a ~= b then
                    local edge = {source = source, target = target, kind = kind,
                        a = a, b = b}
                    table.insert(edges, edge)
                    adjacent[a] = adjacent[a] or {}
                    adjacent[b] = adjacent[b] or {}
                    table.insert(adjacent[a], edge)
                    table.insert(adjacent[b], edge)
                end
            end
        end
    end

    local visited = { [seedKey] = true }
    local queue = { seedKey }
    local index = 1
    while index <= #queue do
        local key = queue[index]
        index += 1
        for _, edge in ipairs(adjacent[key] or {}) do
            local nextKey = if edge.a == key then edge.b else edge.a
            if not visited[nextKey] then
                visited[nextKey] = true
                table.insert(queue, nextKey)
            end
        end
    end

    local models = {}
    for _, key in ipairs(queue) do
        for _, model in ipairs(bodies[key] or {}) do
            table.insert(models, model)
        end
    end
    local connected = {}
    for _, edge in ipairs(edges) do
        if visited[edge.a] and visited[edge.b] then
            table.insert(connected, edge)
        end
    end
    if #connected == 0 then
        return nil, "Add a Bearing, Slider, or Fixed relationship first"
    end
    if #models > MAX_PARTS or #connected > MAX_JOINTS then
        return nil, "Mechanism exceeds simulation limits (128 parts / 64 joints)"
    end

    return { models = models, edges = connected,
        bodies = bodies, included = visited, rootKey = seedKey }
end

function Simulation:Stop(player)
    local session = self.Sessions[player]
    if not session then
        self:SetStatus(player, false, false)
        return false, "No simulation running"
    end

    self.Sessions[player] = nil
    -- Remove live physics first, THEN bring edit geometry back.
    if session.World then session.World:Destroy() end
    for _, saved in ipairs(session.Originals) do
        if saved.Part and saved.Part.Parent then
            saved.Part.Transparency = saved.Transparency
            saved.Part.CanCollide = saved.CanCollide
            saved.Part.CanQuery = saved.CanQuery
            saved.Part.CanTouch = saved.CanTouch
            saved.Part.Anchored = saved.Anchored
        end
    end
    self:SetStatus(player, false, false)
    return true, "Simulation stopped — editable construction restored"
end

function Simulation:Start(player, payload)
    if self:IsRunning(player) then return false, "Stop simulation before starting another" end
    if type(payload.seedId) ~= "string" then
        return false, "Aim at the housing or another constructed body"
    end

    local d = self.D
    local seed = d.findOwned(player, payload.seedId)
    if not seed then return false, "Aim at a constructed part you own" end
    if not d.nearPlayer(player, seed:GetPivot().Position) then
        return false, "Mechanism is out of construction range"
    end

    local graph, reason = self:Graph(player, seed)
    if not graph then return false, reason end

    local session = {
        Originals = {},
        Motors = {},
        MotorOn = false,
        World = nil,
    }
    local created = Instance.new("Folder")
    created.Name = "Simulation_" .. tostring(player.UserId)
    session.World = created
    self.Sessions[player] = session

    local success, failure = pcall(function()
        local copies = {}
        local copyParts = {}
        local bodyAnchors = {}
        local runtime = Instance.new("Folder")
        runtime.Name = "PhysicsJoints"
        runtime.Parent = created

        -- 1. Clone only the selected connected graph, never all player parts.
        for _, original in ipairs(graph.models) do
            local id = original:GetAttribute("InstanceId")
            local clone = original:Clone()
            clone.Name = "Sim_" .. original.Name
            clone.Parent = created
            if not clone.PrimaryPart then
                error("Source component has no PrimaryPart: " .. original.Name)
            end
            for _, part in ipairs(allParts(clone)) do
                part.Anchored = true
                part.CanCollide = true
                part.CanQuery = false
                part.CanTouch = false
            end
            copies[id] = clone
            copyParts[id] = allParts(clone)
        end

        -- 2. Compile each authored component into one physical rigid body.
        for key, originals in pairs(graph.bodies) do
            if graph.included[key] then
                local first = originals[1]
                local root = copies[first:GetAttribute("InstanceId")]
                local anchor = root and root.PrimaryPart
                if not anchor then error("A rigid component has no anchor") end
                bodyAnchors[key] = anchor

                for _, original in ipairs(originals) do
                    local copy = copies[original:GetAttribute("InstanceId")]
                    if not copy then error("Missing cloned component member") end
                    for _, part in ipairs(copyParts[original:GetAttribute("InstanceId")]) do
                        if part ~= anchor then
                            local weld = Instance.new("WeldConstraint")
                            weld.Name = "CompiledRigidMember"
                            weld.Part0 = anchor
                            weld.Part1 = part
                            weld.Parent = runtime
                        end
                    end
                end
            end
        end

        -- 3. Rebuild authored relationships against the CLONED bodies.
        local collisionExclusions = 0
        for _, edge in ipairs(graph.edges) do
            local target = copies[edge.target:GetAttribute("InstanceId")]
            local source = copies[edge.source:GetAttribute("InstanceId")]
            if not target or not source then error("Missing joint endpoint") end
            local p0, p1 = target.PrimaryPart, source.PrimaryPart
            if edge.kind == "Fixed" then
                local weld = Instance.new("WeldConstraint")
                weld.Name = "FixedRelationship"
                weld.Part0 = p0
                weld.Part1 = p1
                weld.Parent = runtime
            else
                local targetAxis = Alignment.TargetAxis(edge.target)
                if not targetAxis then error("Joint opening axis is unavailable") end
                local axis = edge.target:GetPivot():VectorToWorldSpace(targetAxis)
                local worldFrame = axisFrame(edge.target:GetPivot().Position, axis)
                local a0 = Instance.new("Attachment")
                a0.Name = "SimHousing"
                a0.CFrame = p0.CFrame:ToObjectSpace(worldFrame)
                a0.Parent = p0
                local a1 = Instance.new("Attachment")
                a1.Name = "SimShaft"
                a1.CFrame = p1.CFrame:ToObjectSpace(worldFrame)
                a1.Parent = p1
                local constraint = if edge.kind == "Bearing"
                    then Instance.new("HingeConstraint")
                    else Instance.new("PrismaticConstraint")
                constraint.Name = edge.kind
                constraint.Attachment0 = a0
                constraint.Attachment1 = a1
                constraint.Enabled = true
                if constraint:IsA("PrismaticConstraint") then
                    local travel = math.clamp(source.PrimaryPart.Size.X, 0.25, 2)
                    constraint.LimitsEnabled = true
                    constraint.LowerLimit = -travel
                    constraint.UpperLimit = travel
                end
                setMotor(constraint, false)
                constraint.Parent = runtime
                table.insert(session.Motors, constraint)
            end

            -- Avoid numerical instability from deliberately intersecting
            -- shaft and housing collision surfaces.
            local targetBody = graph.bodies[edge.b]
            local sourceBody = graph.bodies[edge.a]
            for _, left in ipairs(targetBody) do
                for _, right in ipairs(sourceBody) do
                    for _, lp in ipairs(copyParts[left:GetAttribute("InstanceId")] or {}) do
                        for _, rp in ipairs(copyParts[right:GetAttribute("InstanceId")] or {}) do
                            collisionExclusions += 1
                            if collisionExclusions > MAX_COLLISION_PAIRS then
                                error("Connected bodies are too complex for collision exclusions")
                            end
                            local no = Instance.new("NoCollisionConstraint")
                            no.Name = "JointCollisionExclusion"
                            no.Part0 = lp
                            no.Part1 = rp
                            no.Parent = runtime
                        end
                    end
                end
            end
        end

        -- 4. Hide originals but preserve every authored transform/material.
        for _, original in ipairs(graph.models) do
            for _, part in ipairs(allParts(original)) do
                table.insert(session.Originals, {
                    Part = part,
                    Transparency = part.Transparency,
                    CanCollide = part.CanCollide,
                    CanQuery = part.CanQuery,
                    CanTouch = part.CanTouch,
                    Anchored = part.Anchored,
                })
                part.Transparency = 1
                part.CanCollide = false
                part.CanQuery = false
                part.CanTouch = false
            end
        end

        -- 5. Ground only the selected body. Welds keep its other members
        -- fixed while connected bodies can rotate or slide.
        for key, originals in pairs(graph.bodies) do
            if graph.included[key] then
                local rootAnchor = bodyAnchors[key]
                for _, original in ipairs(originals) do
                    for _, part in ipairs(copyParts[original:GetAttribute("InstanceId")] or {}) do
                        part.Anchored = key == graph.rootKey and part == rootAnchor
                    end
                end
            end
        end
        created.Parent = self.World
        -- Network ownership can only be assigned after Parts are in
        -- Workspace and unanchored. Keep authoritative mechanism physics
        -- on the server so clients cannot steer other players' assemblies.
        for _, original in ipairs(graph.models) do
            for _, part in ipairs(copyParts[original:GetAttribute("InstanceId")] or {}) do
                if not part.Anchored then
                    pcall(function() part:SetNetworkOwner(nil) end)
                end
            end
        end
    end)

    if not success then
        warn("[OPENWORKS] Simulation compile failed: " .. tostring(failure))
        self:Stop(player)
        return false, "Could not compile simulation (see Studio Output)"
    end

    self:SetStatus(player, true, false)
    return true, "Simulation running — housing anchored. M: motor; P: stop"
end

function Simulation:Motor(player)
    local session = self.Sessions[player]
    if not session then return false, "Start simulation first (P)" end
    if #session.Motors == 0 then
        return false, "No Bearing or Slider motors in this mechanism"
    end
    session.MotorOn = not session.MotorOn
    for _, constraint in ipairs(session.Motors) do
        if constraint.Parent then setMotor(constraint, session.MotorOn) end
    end
    self:SetStatus(player, true, session.MotorOn)
    return true, if session.MotorOn then "Motor drive enabled"
        else "Motor drive disabled"
end

function Simulation:ClearPlayer(player)
    if self:IsRunning(player) then self:Stop(player) end
    self:SetStatus(player, false, false)
end

return Simulation
