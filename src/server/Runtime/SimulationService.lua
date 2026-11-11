--!strict
-- Phase 06: temporary native-physics simulation of a connected mechanism.
-- Authored geometry remains anchored/unchanged; simulation uses server-owned
-- clones with welded rigid components and live Hinge/Prismatic/Weld joints.
-- Stop destroys every simulation object and restores original visibility.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Alignment = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("AlignmentMath"))
local JointFrames = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("JointFrames"))
local SpringMath = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("SpringMath"))
local Grid = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("GridMath"))
local HandCrankMath = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("HandCrankMath"))

local Simulation = {}
Simulation.__index = Simulation

local MAX_PARTS = 128
local MAX_JOINTS = 64
local MAX_COLLISION_PAIRS = 1200
local INPUT_EXPIRES = 0.35

local function bodyKey(model)
    -- ComponentId is only an editor grouping; NEVER a physical joint.
    return "p:" .. tostring(model:GetAttribute("InstanceId"))
end

local function allParts(model)
    local parts = {}
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then table.insert(parts, part) end
    end
    return parts
end

function Simulation.new(deps)
    local world = workspace:FindFirstChild("OPENWORKS_Simulated")
    if not world then
        world = Instance.new("Folder")
        world.Name = "OPENWORKS_Simulated"
        world.Parent = workspace
    end
    local self=setmetatable({ D=deps,World=world,Sessions={} },Simulation)
    self.ActuatorHeartbeat=RunService.Heartbeat:Connect(function(dt)
        self:StepCranks(dt)
    end)
    return self
end

function Simulation:IsRunning(player)
    return self.Sessions[player] ~= nil
end

-- The ONLY powered source is a distinct physical HandCrank prefab.
-- Mechanical relationships never receive an ActuatorType/Motor setting.
function Simulation:StepCranks(_dt)
    local now=os.clock()
    for _,session in pairs(self.Sessions) do
        for id,crank in pairs(session.Cranks or {}) do
            local torque=crank.Torque
            local root=crank.Root
            if not torque.Parent or not root.Parent then continue end
            if session.Paused or session.ActiveCrankId~=id
                or not crank.Dragging
                or now-(crank.LastInput or 0)>INPUT_EXPIRES then
                torque.Torque=Vector3.zero
                continue
            end
            local axis=root.CFrame.RightVector.Unit
            local actual=root.AssemblyAngularVelocity:Dot(axis)
            local demand=math.clamp(crank.Desired or 0,
                -HandCrankMath.MaxAngularSpeed,HandCrankMath.MaxAngularSpeed)
            local effort=math.clamp(
                (demand-actual)*HandCrankMath.VelocityGain,
                -HandCrankMath.MaxTorque,HandCrankMath.MaxTorque)
            torque.Torque=axis*effort
        end
    end
end

function Simulation:BeginCrank(player,request)
    local session=self.Sessions[player]
    if not session then return false,"Start simulation (P) before turning a crank" end
    if session.Paused then return false,"Resume simulation (O) first" end
    local id=type(request)=="table" and request.crankId or nil
    local crank=type(id)=="string" and session.Cranks[id] or nil
    if not crank then return false,"Choose a HandCrank in this running assembly" end
    if not crank.Coupled then
        return false,"Couple the crank output to a cylinder shaft end in Edit"
    end
    if session.GroundKeys and session.GroundKeys[crank.BodyKey] then
        return false,"The hand crank itself is grounded; ground its bearing housing instead"
    end
    local character=player.Character
    local root=character and character:FindFirstChild("HumanoidRootPart")
    if not root or (root.Position-crank.Root.Position).Magnitude>22 then
        return false,"Move closer to the hand crank to turn it"
    end
    for _,previous in pairs(session.Cranks) do
        previous.Torque.Torque=Vector3.zero
        previous.Dragging=false
        previous.Desired=0
    end
    session.ActiveCrankId=id
    crank.LastInput=os.clock()
    crank.Dragging=false
    crank.Desired=0
    return true,"Hand crank gripped • hold LMB and drag around the ring"
end

-- Unreliable-speed firehose runs through an Event, not the throttled build
-- request. All incoming values are validated and expire unless refreshed.
function Simulation:InputCrank(player,id,desired,dragging,release)
    local session=self.Sessions[player]
    if not session or session.ActiveCrankId~=id then return end
    local crank=session.Cranks and session.Cranks[id]
    if not crank or not crank.Torque.Parent then return end
    if release==true then
        crank.Torque.Torque=Vector3.zero
        crank.Dragging=false
        crank.Desired=0
        session.ActiveCrankId=nil
        return
    end
    if type(desired)~="number" or desired~=desired
        or desired==math.huge or desired==-math.huge
        or math.abs(desired)>HandCrankMath.MaxAngularSpeed*2
        or type(dragging)~="boolean" then return end
    local now=os.clock()
    if now-(crank.LastPacket or 0)<0.035 then return end
    crank.LastPacket=now
    crank.LastInput=now
    crank.Dragging=dragging
    crank.Desired=if dragging
        then math.clamp(desired,-HandCrankMath.MaxAngularSpeed,
            HandCrankMath.MaxAngularSpeed) else 0
end

function Simulation:SetStatus(player,running,grounded)
    player:SetAttribute("OPENWORKS_Simulating",running)
    player:SetAttribute("OPENWORKS_Grounded",grounded~=false)
    -- Motion relationships stay passive. Manual HandCrank torque is
    -- installed only on the distinct physical actuator prefab.
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

    local editorGroups={}
    for _,model in pairs(owned) do
        local group=model:GetAttribute("ComponentId")
        if type(group)=="string" and group~="" then
            editorGroups[group]=editorGroups[group] or {}
            table.insert(editorGroups[group],bodyKey(model))
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
                and (kind == "Bearing" or kind == "Slider"
                    or kind == "Cylindrical" or kind == "Fixed" or kind == "Gear"
                    or kind == "Spring" or kind == "Weld" or kind == "Bolt") then
                local a, b = bodyKey(source), bodyKey(target)
                if a ~= b then
                    local edge = {source = source, target = target, kind = kind,
                        relation = relation, a = a, b = b}
                    table.insert(edges, edge)
                    adjacent[a] = adjacent[a] or {}
                    adjacent[b] = adjacent[b] or {}
                    table.insert(adjacent[a], edge)
                    table.insert(adjacent[b], edge)
                    -- A bolt can fasten a second drilled body without creating
                    -- another bolt or duplicating its authored history entry.
                    if kind=="Bolt" then
                        local other=owned[relation:GetAttribute("SecondTargetId")]
                        if other and other~=source and other~=target then
                            local key=bodyKey(other)
                            local extra={source=source,target=other,kind=kind,
                                relation=relation,a=a,b=key}
                            table.insert(edges,extra)
                            adjacent[a]=adjacent[a] or {}
                            adjacent[key]=adjacent[key] or {}
                            table.insert(adjacent[a],extra)
                            table.insert(adjacent[key],extra)
                        end
                    end
                end
            end
        end
    end

    local visited = { [seedKey] = true }
    local queue = { seedKey }
    -- Registered assemblies include disconnected member components;
    -- unrelated mechanisms outside the registered assembly are excluded.
    local assemblyId=seed:GetAttribute("AssemblyId")
    local assemblyKeys={}
    if type(assemblyId)=="string" and assemblyId~="" then
        for _,model in pairs(owned) do
            if model:GetAttribute("AssemblyId")==assemblyId then
                local k=bodyKey(model)
                assemblyKeys[k]=true
                if not visited[k] then
                    visited[k]=true
                    table.insert(queue,k)
                end
            end
        end
    end
    local index = 1
    while index <= #queue do
        local key = queue[index]
        index += 1
        -- Group members enter the same simulation SCOPE, not a welded body.
        local current=bodies[key] and bodies[key][1]
        local component=current and current:GetAttribute("ComponentId")
        if component then
            for _,peer in ipairs(editorGroups[component] or {}) do
                if not visited[peer] then
                    visited[peer]=true
                    table.insert(queue,peer)
                end
            end
        end
        for _, edge in ipairs(adjacent[key] or {}) do
            local nextKey = if edge.a == key then edge.b else edge.a
            if type(assemblyId)=="string" and assemblyId~=""
                and not assemblyKeys[nextKey] then
                -- Adding a real crank coupling after assembly registration
                -- still makes the crank part of the physical mechanism.
                -- This exception is ONLY for an explicit rigid link to
                -- a HandCrank, never for editor ComponentId grouping.
                local crankEdge=HandCrankMath.IsCrank(edge.source)
                    or HandCrankMath.IsCrank(edge.target)
                local rigid=edge.kind=="Weld" or edge.kind=="Fixed"
                    or edge.kind=="Bolt"
                if not (crankEdge and rigid) then continue end
            end
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
    if #models > MAX_PARTS or #connected > MAX_JOINTS then
        return nil, "Assembly exceeds simulation safety limits (128 parts / 64 joints)"
    end

    return { models = models, edges = connected,
        bodies = bodies, included = visited, rootKey = seedKey,
        assemblyId=assemblyId,assemblyName=seed:GetAttribute("AssemblyName") }
end

function Simulation:Stop(player)
    local session = self.Sessions[player]
    if not session then
        self:SetStatus(player,false)
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
    self:SetStatus(player,false)
    player:SetAttribute("OPENWORKS_SimulationPaused",false)
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
        Grounded = payload.grounded ~= false,
        World = nil,
        Paused = false,
        PausedParts = nil,
        Constraints = {},
        SeedId = payload.seedId,
        AssemblyName = graph.assemblyName,
        ActiveRelations={},
        Cranks={},
        ActiveCrankId=nil,
    }
    for _,edge in ipairs(graph.edges) do
        session.ActiveRelations[edge.relation:GetAttribute("RelationId")]=true
    end
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
                -- The GearLibrary root is only a transform/pivot, not metal.
                -- Keep the through-bore physically open in simulation.
                part.CanCollide = part:GetAttribute("GearPivotOnly") ~= true
                -- Needed for mouse selection of running physics clones.
                part.CanQuery = part:GetAttribute("GearPivotOnly") ~= true
                part.CanTouch = false
            end
            copies[id] = clone
            copyParts[id] = allParts(clone)
        end

        -- A prefab is a physical primitive even if it has several geometry
        -- Parts (bolt heads / gear teeth). Only those INTERNAL parts are welded.
        -- Separately authored primitives remain independent without explicit
        -- authored Weld/Bolt relationships, regardless of ComponentId.
        for key, originals in pairs(graph.bodies) do
            if graph.included[key] then
                local id=originals[1]:GetAttribute("InstanceId")
                local copy=copies[id]
                local anchor=copy and copy.PrimaryPart
                if not anchor then error("Primitive has no physics root") end
                bodyAnchors[key]=anchor
                for _,part in ipairs(copyParts[id]) do
                    if part~=anchor then
                        local weld=Instance.new("WeldConstraint")
                        weld.Name="PrefabInternalPart"
                        weld.Part0=anchor
                        weld.Part1=part
                        weld.Parent=runtime
                    end
                end
            end
        end

        -- Gear ratios remain authored metadata, not powered motion.
        -- Future actuator components will explicitly provide energy.

        -- 3. Rebuild authored relationships against the CLONED bodies.
        local collisionExclusions = 0
        for _, edge in ipairs(graph.edges) do
            local target = copies[edge.target:GetAttribute("InstanceId")]
            local source = copies[edge.source:GetAttribute("InstanceId")]
            if not target or not source then error("Missing joint endpoint") end
            local p0, p1 = target.PrimaryPart, source.PrimaryPart
            if edge.kind == "Gear" then
                -- Passive contact only; no invented gear motor drive.
                continue
            elseif edge.kind == "Fixed" or edge.kind=="Weld"
                or edge.kind=="Bolt" then
                local weld = Instance.new("WeldConstraint")
                weld.Name = "FixedRelationship"
                weld.Part0 = p0
                weld.Part1 = p1
                weld.Parent = runtime
            elseif edge.kind=="Spring" then
                local mode=edge.relation:GetAttribute("SpringMode")
                -- Old piston/plate labels are normalized to a free spring.
                mode="General"
                local world0,world1=SpringMath.Frames(
                    edge.source,edge.target,mode
                )
                local s0=Instance.new("Attachment")
                s0.Name="SimSpringFixed"
                s0.CFrame=p0.CFrame:ToObjectSpace(CFrame.new(world0))
                s0.Parent=p0
                local s1=Instance.new("Attachment")
                s1.Name="SimSpringMoving"
                s1.CFrame=p1.CFrame:ToObjectSpace(CFrame.new(world1))
                s1.Parent=p1
                local spring=Instance.new("SpringConstraint")
                spring.Name="Spring_"..mode
                spring.Attachment0=s0
                spring.Attachment1=s1
                spring.Stiffness=edge.relation:GetAttribute("Stiffness") or 120
                spring.Damping=edge.relation:GetAttribute("Damping") or 14
                spring.FreeLength=edge.relation:GetAttribute("FreeLength")
                    or (world1-world0).Magnitude
                spring.MaxForce=40000
                spring.LimitsEnabled=true
                spring.MinLength=0.01
                spring.MaxLength=math.max(spring.FreeLength*1.8,0.25)
                spring.Coils=8
                spring.Radius=SpringMath.Radius(edge.source,edge.target,mode)
                spring.Thickness=math.clamp(spring.Radius*0.085,0.012,0.065)
                spring.Color=BrickColor.new("Bright orange")
                -- Render the live, physically attached orange spring
                -- while simulation is running. The authored construction
                -- coil remains hidden locally, avoiding a stationary ghost.
                spring.Visible=true
                spring:SetAttribute("AuthoredRelationId",
                    edge.relation:GetAttribute("RelationId"))
                spring.Parent=runtime
                table.insert(session.Constraints,spring)
                -- Free spring: no hidden prismatic or other motion guide.
            else
                local worldFrame = JointFrames.ForOpening(edge.target)
                if not worldFrame then error("Joint opening axis is unavailable") end
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
                    elseif edge.kind == "Slider"
                    then Instance.new("PrismaticConstraint")
                    else Instance.new("CylindricalConstraint")
                constraint.Name = edge.kind
                constraint.Attachment0 = a0
                constraint.Attachment1 = a1
                constraint.Enabled = true
                constraint:SetAttribute("AuthoredRelationId",
                    edge.relation:GetAttribute("RelationId"))
                if constraint:IsA("PrismaticConstraint")
                    or constraint:IsA("CylindricalConstraint") then
                    local low,high=Alignment.OffsetBounds(edge.source,edge.target)
                    local normal=edge.target:GetPivot():VectorToWorldSpace(
                        Alignment.TargetAxis(edge.target)
                    ).Unit
                    local authored=(edge.source:GetPivot().Position
                        -edge.target:GetPivot().Position):Dot(normal)/Grid.Unit
                    local lower=(low-authored)
                    local upper=(high-authored)
                    local fittedTravel=edge.relation:GetAttribute("FitTravelU")
                    if type(fittedTravel)=="number" then
                        -- All guide posts must stay engaged. Never exceed
                        -- the shortest valid multi-point insertion.
                        lower=math.max(lower,-fittedTravel)
                        upper=math.min(upper,fittedTravel)
                    end
                    if lower>=upper then
                        error("Multi-point guides have no safe sliding travel")
                    end
                    local physicalLower=lower*Grid.Unit
                    local physicalUpper=upper*Grid.Unit
                    local authoredLow=edge.relation:GetAttribute("LowerLimit")
                    local authoredHigh=edge.relation:GetAttribute("UpperLimit")
                    -- User travel restrictions can ONLY narrow the physical
                    -- shaft bounds. Never permit the slider to disconnect.
                    if edge.relation:GetAttribute("LimitsEnabled")==true
                        and type(authoredLow)=="number"
                        and type(authoredHigh)=="number" then
                        local a=math.max(lower,authoredLow)
                        local b=math.min(upper,authoredHigh)
                        if a<b then lower,upper=a,b end
                    end
                    constraint.LimitsEnabled=true
                    constraint:SetAttribute("PhysicalLower",physicalLower)
                    constraint:SetAttribute("PhysicalUpper",physicalUpper)
                    constraint.LowerLimit=lower*Grid.Unit
                    constraint.UpperLimit=upper*Grid.Unit
                end
                if constraint:IsA("HingeConstraint") then
                    constraint.LimitsEnabled =
                        edge.relation:GetAttribute("LimitsEnabled") == true
                    constraint.LowerAngle =
                        edge.relation:GetAttribute("LowerLimit") or -180
                    constraint.UpperAngle =
                        edge.relation:GetAttribute("UpperLimit") or 180
                end
                -- Native relationships permit the selected degrees of
                -- freedom but never actuate them.
                if constraint:IsA("HingeConstraint")
                    or constraint:IsA("PrismaticConstraint")
                    or constraint:IsA("CylindricalConstraint") then
                    constraint.ActuatorType=Enum.ActuatorType.None
                end
                constraint.Parent = runtime
                table.insert(session.Constraints, constraint)
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

        -- Install input-torque devices on physical crank bodies only.
        -- Explicit Weld/Fixed/Bolt transmission to a shaft is required.
        for _,original in ipairs(graph.models) do
            if not HandCrankMath.IsCrank(original) then continue end
            local id=original:GetAttribute("InstanceId")
            local model=copies[id]
            if not model or not model.PrimaryPart then
                error("HandCrank has no simulation primary shaft")
            end
            local coupled=false
            for _,edge in ipairs(graph.edges) do
                if edge.kind=="Weld" or edge.kind=="Fixed" then
                    local other=if edge.source==original then edge.target
                        elseif edge.target==original then edge.source else nil
                    if other and HandCrankMath.IsOutputShaft(other) then
                        coupled=true
                        break
                    end
                end
            end
            local root=model.PrimaryPart
            local attachment=Instance.new("Attachment")
            attachment.Name="ManualCrankTorqueAxis"
            attachment.Parent=root
            local torque=Instance.new("Torque")
            torque.Name="HandCrank_PlayerTorque"
            torque.Attachment0=attachment
            torque.RelativeTo=Enum.ActuatorRelativeTo.World
            torque.Torque=Vector3.zero
            torque.Parent=runtime
            session.Cranks[id]={
                Root=root,Torque=torque,Coupled=coupled,
                BodyKey=bodyKey(original),LastInput=0,LastPacket=0,
                Desired=0,Dragging=false,
            }
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

        -- 5. Ground every explicitly grounded rigid body, if any.
        -- Otherwise retain the established aim-at-housing grounding fallback.
        local explicitGround = {}
        if session.Grounded then
            for key, originals in pairs(graph.bodies) do
                if graph.included[key] then
                    for _, member in ipairs(originals) do
                        if member:GetAttribute("Grounded") == true then
                            explicitGround[key] = true
                        end
                    end
                end
            end
        end
        local hasExplicitGround = next(explicitGround) ~= nil
        session.GroundKeys = explicitGround
        if not hasExplicitGround and session.Grounded then
            -- Aim-at-crank must not ground the actuator you're about to
            -- turn. Prefer the BEARING HOUSING of a crank mechanism.
            local hasCrank=false
            for _,model in ipairs(graph.models) do
                if HandCrankMath.IsCrank(model) then hasCrank=true break end
            end
            local groundedKey=if hasCrank then nil else graph.rootKey
            if hasCrank then
                for _,edge in ipairs(graph.edges) do
                    if (edge.kind=="Bearing" or edge.kind=="Slider"
                            or edge.kind=="Cylindrical")
                        and Alignment.TargetAxis(edge.target)
                        and not HandCrankMath.IsCrank(edge.target) then
                        groundedKey=edge.b
                        break
                    end
                end
            end
            -- Without a real bearing housing and without explicit ground,
            -- a crank mechanism is FREE rather than freezing the crank.
            if groundedKey then session.GroundKeys[groundedKey]=true end
        end

        -- Ground/movable colors are drawn by client WorldVisuals as
        -- fill-only Highlights. Do not create overlapping simulation
        -- Highlights or outlines here; authored physics stays authoritative.
        for key, originals in pairs(graph.bodies) do
            if graph.included[key] then
                local rootAnchor = bodyAnchors[key]
                for _, original in ipairs(originals) do
                    for _, part in ipairs(copyParts[original:GetAttribute("InstanceId")] or {}) do
                        part.Anchored = session.GroundKeys[key] == true
                            and part == rootAnchor
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

    self:SetStatus(player,true,next(session.GroundKeys)~=nil)
    player:SetAttribute("OPENWORKS_SimulationPaused",false)
    return true,(session.AssemblyName
        and (tostring(session.AssemblyName).." • ") or "")
        .. (if next(session.GroundKeys)
            then "green grounded / orange movable • P stop"
            else "free assembly • orange bodies • P stop")
end

-- Keep runtime native constraints synchronized with authored property edits.
-- Only the owning player's active simulation may receive live changes.
function Simulation:HasRelationship(player,id)
    local session=self.Sessions[player]
    return session~=nil and session.ActiveRelations[id]==true
end
function Simulation:SyncRelationship(player,relation)
    local session=self.Sessions[player]
    if not session then return true end
    local id=relation:GetAttribute("RelationId")
    if not self:HasRelationship(player,id) then
        return false,"Relationship is outside the active simulation"
    end
    local kind=relation:GetAttribute("Kind")
    for _,constraint in ipairs(session.Constraints) do
        if constraint.Parent
            and constraint:GetAttribute("AuthoredRelationId")==id then
            if kind=="Spring" and constraint:IsA("SpringConstraint") then
                constraint.Stiffness=relation:GetAttribute("Stiffness") or 120
                constraint.Damping=relation:GetAttribute("Damping") or 14
                constraint.FreeLength=relation:GetAttribute("FreeLength") or 0.5
                constraint.MaxLength=math.max(constraint.FreeLength*1.8,0.25)
            elseif kind=="Bearing" and constraint:IsA("HingeConstraint") then
                constraint.LimitsEnabled=relation:GetAttribute("LimitsEnabled")==true
                constraint.LowerAngle=relation:GetAttribute("LowerLimit") or -180
                constraint.UpperAngle=relation:GetAttribute("UpperLimit") or 180
            elseif (kind=="Slider" or kind=="Cylindrical")
                and (constraint:IsA("PrismaticConstraint")
                    or constraint:IsA("CylindricalConstraint")) then
                local low=math.max(constraint:GetAttribute("PhysicalLower")
                    or -math.huge,(relation:GetAttribute("LowerLimit") or -32)*Grid.Unit)
                local high=math.min(constraint:GetAttribute("PhysicalUpper")
                    or math.huge,(relation:GetAttribute("UpperLimit") or 32)*Grid.Unit)
                if low<high then
                    constraint.LimitsEnabled=true
                    constraint.LowerLimit=low
                    constraint.UpperLimit=high
                end
            end
        end
    end
    return true
end

function Simulation:Pause(player)
    local session = self.Sessions[player]
    if not session then return false, "Start simulation first" end
    if session.Paused then
        for part, state in pairs(session.PausedParts or {}) do
            if part.Parent then
                part.Anchored = state.anchored
                if not state.anchored then
                    part.AssemblyLinearVelocity = state.linear
                    part.AssemblyAngularVelocity = state.angular
                end
            end
        end
        session.PausedParts = nil
        session.Paused = false
        player:SetAttribute("OPENWORKS_SimulationPaused",false)
        return true,"Simulation resumed"
    end

    local state = {}
    for _, item in ipairs(session.World:GetDescendants()) do
        if item:IsA("BasePart") then
            state[item] = {
                anchored = item.Anchored,
                linear = item.AssemblyLinearVelocity,
                angular = item.AssemblyAngularVelocity,
            }
            item.Anchored = true
        end
    end
    session.PausedParts = state
    session.Paused = true
    player:SetAttribute("OPENWORKS_SimulationPaused",true)
    return true,"Simulation paused"
end

function Simulation:Reset(player)
    local session = self.Sessions[player]
    if not session then return false,"Start simulation first" end
    local seedId = session.SeedId
    local grounded = session.Grounded
    self:Stop(player)
    return self:Start(player,{seedId=seedId,grounded=grounded})
end

function Simulation:Info(player,payload)
    local id = payload.seedId
    if type(id) ~= "string" then return false,"Aim at a body to inspect" end
    local model = self.D.findOwned(player,id)
    if not model then return false,"Choose your own mechanism" end
    local session = self.Sessions[player]
    local grounded = model:GetAttribute("Grounded") == true
    local lines = {
        tostring(model:GetAttribute("AssemblyName") or model.Name)
            .. (if grounded then " • GROUNDED" else " • MOVABLE"),
    }
    local current = 0
    for _, relation in ipairs(self.D.mechanical.Folder:GetChildren()) do
        if relation:GetAttribute("OwnerUserId") == player.UserId
            and (relation:GetAttribute("SourceId") == id
                or relation:GetAttribute("TargetId") == id) then
            current += 1
            local kind = tostring(relation:GetAttribute("Kind") or "Joint")
            local limit = relation:GetAttribute("LimitsEnabled") == true
            table.insert(lines, kind .. (if limit then " • limited" else ""))
        end
    end
    table.insert(lines, tostring(current) .. " direct relationships")
    if session then
        table.insert(lines,if session.Paused then "PAUSED" else "LIVE PHYSICS")
        for _, constraint in ipairs(session.Constraints) do
            if constraint:IsA("HingeConstraint") then
                table.insert(lines,string.format("hinge %.1f°",constraint.CurrentAngle))
            elseif constraint:IsA("PrismaticConstraint") then
                table.insert(lines,string.format("slider %.3f studs",constraint.CurrentPosition))
            end
            if #lines > 12 then break end
        end
    end
    return true,table.concat(lines,"  /  ")
end

function Simulation:ClearPlayer(player)
    if self:IsRunning(player) then self:Stop(player) end
    self:SetStatus(player,false)
end

return Simulation
