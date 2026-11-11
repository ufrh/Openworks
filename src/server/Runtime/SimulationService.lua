--!strict
-- SimulationService: compile ONLY explicitly registered named assemblies.
-- Each primitive is an independent body; component grouping never welds.
-- Authored models remain unchanged; temporary clones receive passive native
-- physics constraints and separately powered, input-limited actuator parts.
-- Stop destroys clones and restores all original visibility/collision.
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
local GearKinematics = require(script.Parent:WaitForChild("GearKinematics"))
local GearMath = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("GearMath"))

local Simulation = {}
Simulation.__index = Simulation

local MAX_PARTS = 128
local MAX_JOINTS = 64
local MAX_COLLISION_PAIRS = 1200
-- If the client disappears or drops its held-input stream, never leave a
-- running motor behind. The client pulses every 0.1s during LMB hold.
local CRANK_HOLD_TIMEOUT = 0.5
local RACK_HOLD_TIMEOUT = 0.5
local RACK_MANUAL_SPEED = 1.5 -- studs/s; server chooses direction and power

-- Gears and all rigidly welded members rotate kinematically.
-- Native physics is reserved for mechanisms OUTSIDE gear rigid bodies.
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

-- Named Assembly membership remains explicit. Do NOT pull unrelated
-- constructions into simulation just because their gears are nearby.
-- Instead tell the builder when a newly added gear was never registered.
local function countNearbyUnregisteredGears(player,graph,folder)
    local selected={}
    local included={}
    for _,model in ipairs(graph.models) do
        included[model]=true
        if type(model:GetAttribute("GearTeeth"))=="number" then
            table.insert(selected,model)
        end
    end
    if #selected==0 then return 0 end
    local count=0
    for _,candidate in ipairs(folder:GetChildren()) do
        if not candidate:IsA("Model") or included[candidate]
            or candidate:GetAttribute("OwnerUserId")~=player.UserId
            or type(candidate:GetAttribute("GearTeeth"))~="number"
            or not candidate.PrimaryPart then continue end
        local cf=candidate:GetPivot()
        for _,registered in ipairs(selected) do
            local module=candidate:GetAttribute("GearModuleStuds")
            if type(module)~="number"
                or math.abs(module-(registered:GetAttribute(
                    "GearModuleStuds") or 0))>0.0001 then continue end
            local fixed=registered:GetPivot()
            local axis=fixed.RightVector
            if math.abs(axis:Dot(cf.RightVector))<0.995 then continue end
            local distance=cf.Position-fixed.Position
            local axial=math.abs(distance:Dot(axis))
            local radial=(distance-axis*distance:Dot(axis)).Magnitude
            local pitch=(registered:GetAttribute("GearTeeth")
                +candidate:GetAttribute("GearTeeth"))*module/(2*math.pi)
            if math.abs(radial-pitch)<0.45 and axial<0.75 then
                count+=1
                break
            end
        end
    end
    return count
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

-- Gear groups receive purely deterministic CFrame rotation; other
-- crank-driven shafts can retain their bounded native AngularVelocity.
-- Held LMB authorizes movement; packets are liveness only.
function Simulation:StopCrank(session,id)
    local crank=session.Cranks and session.Cranks[id]
    if not crank then return end
    crank.Running=false
    crank.LastInput=0
    crank.NativeSpeed=0
    -- Ordinary non-geared shafts keep their bounded native drive.
    -- Kinematic geared shafts have NO native motor to stop.
    if crank.Drive then crank.Drive.Enabled=false end
    if crank.Model and crank.Model.Parent then
        crank.Model:SetAttribute("OPENWORKS_CrankRunning",false)
    end
    if session.ActiveCrankId==id then session.ActiveCrankId=nil end
end

function Simulation:StopRack(session)
    session.ActiveRackId=nil
    session.RackLastInput=0
    session.RackDirection=0
end

function Simulation:StepCranks(dt)
    for owner,session in pairs(self.Sessions) do
        local character=owner.Character
        local playerRoot=character and character:FindFirstChild("HumanoidRootPart")
        for id,crank in pairs(session.Cranks or {}) do
            local root=crank.Root
            local drive=crank.Drive
            if not root.Parent or (drive and not drive.Parent) then
                if crank.Running then self:StopCrank(session,id) end
                continue
            end
            if session.Paused or session.ActiveCrankId~=id
                or not crank.Running or not playerRoot
                or not self.D.nearPlayer(owner,root.Position)
                or os.clock()-(crank.LastInput or 0)>CRANK_HOLD_TIMEOUT then
                if crank.Running then self:StopCrank(session,id) end
            elseif drive then
                -- The standalone native-motor crank also eases into
                -- speed instead of snapping to 2 rad/s on first press.
                crank.NativeSpeed+=(HandCrankMath.FixedAngularSpeed
                    -crank.NativeSpeed)*(1-math.exp(-8*math.clamp(dt,0,0.07)))
                drive.AngularVelocity=crank.Axis*crank.NativeSpeed
            end
        end
        -- Kinematic solver owns rotational gear/bevel groups AND
        -- translating rack groups. Either a crank can drive a pinion
        -- or a manually pushed rack can BACKDRIVE the same graph.
        if session.Gears and not session.Paused then
            local active=session.ActiveCrankId
            local crank=active and session.Cranks[active] or nil
            local powered=crank and crank.Running
            local rackId=session.ActiveRackId
            local rackModel=rackId and session.Gears:RackModel(rackId) or nil
            if rackId and (not session.Gears:CanDriveRack(rackId)
                or not rackModel or not rackModel.Parent
                or not playerRoot
                or not self.D.nearPlayer(owner,rackModel:GetPivot().Position)
                or os.clock()-(session.RackLastInput or 0)>RACK_HOLD_TIMEOUT) then
                self:StopRack(session)
                rackId=nil
            end
            local rackDriven=not powered and rackId~=nil
            session.Gears:Step(dt,
                if powered then crank.DrivenId
                    elseif rackDriven then rackId else nil,
                if powered then crank.Axis
                    elseif rackDriven then session.Gears:RackAxis(rackId)
                    else nil,
                if powered then HandCrankMath.FixedAngularSpeed
                    elseif rackDriven then session.RackDirection*RACK_MANUAL_SPEED
                    else 0)
        end
    end
end

-- Begin is one hold-start request. For kinematic geared assemblies no
-- Roblox force or torque is applied; a server-owned speed input is used.
function Simulation:BeginCrank(player,request)
    local session=self.Sessions[player]
    if not session then return false,"Start simulation (P) before turning a crank" end
    if session.Paused then return false,"Resume simulation (O) first" end
    local id=type(request)=="table" and request.crankId or nil
    local crank=type(id)=="string" and session.Cranks[id] or nil
    if not crank then return false,"Choose a HandCrank in this running assembly" end
    if session.ActiveCrankId==id and crank.Running then
        -- Duplicate Tool.Activated/InputBegan presses are idempotent.
        crank.LastInput=os.clock()
        return true,"Hand crank held"
    end
    if not crank.Coupled then
        return false,"Couple the crank output to a cylindrical shaft in Edit"
    end
    if session.GroundKeys and
        (session.GroundKeys[crank.BodyKey]
            or session.GroundKeys[crank.DrivenBodyKey]
            or (session.Gears
                and session.Gears:IsGrounded(crank.DrivenId))) then
        return false,"Ground the bearing housing, not the crank or driven shaft"
    end
    local character=player.Character
    local root=character and character:FindFirstChild("HumanoidRootPart")
    if not root or not self.D.nearPlayer(player,crank.Root.Position) then
        return false,"Crank must remain on your own plot"
    end
    -- If a different crank now backdrives this gear graph, reset the
    -- previous input's coast to avoid a sudden gearbox direction jump.
    if session.Gears and session.Gears.LastDrivenId
        and session.Gears.LastDrivenId~=crank.DrivenId then
        session.Gears:StopMotion()
    end
    self:StopRack(session)
    for previousId in pairs(session.Cranks) do
        self:StopCrank(session,previousId)
    end
    session.ActiveCrankId=id
    crank.Running=true
    crank.LastInput=os.clock()
    -- A geared output is intentionally MOTOR-FREE; the kinematic
    -- gearbox advances this same shaft and its connected gears during
    -- StepCranks. Ungeared shafts retain their native torque-limited
    -- AngularVelocity drive.
    if crank.Drive then
        crank.NativeSpeed=0
        crank.Drive.AngularVelocity=Vector3.zero
        crank.Drive.Enabled=true
    end
    crank.Model:SetAttribute("OPENWORKS_CrankRunning",true)
    return true,"Hand crank running • release LMB to stop"
end

-- Backdrive rack-and-pinion trains by holding an explicit linear
-- control on a physically guided rack. No arbitrary client force, speed
-- or WorldCFrame may reach the kinematic mechanism.
function Simulation:BeginRack(player,request)
    local session=self.Sessions[player]
    if not session then return false,"Start an assembly simulation first" end
    if session.Paused or not session.Gears then
        return false,"Resume simulation before moving a rack"
    end
    local id=type(request)=="table" and request.rackId or nil
    local direction=type(request)=="table" and request.direction or nil
    if type(id)~="string" or #id>64
        or (direction~=-1 and direction~=1) then
        return false,"Select a rack and choose a push direction"
    end
    if not session.Gears:CanDriveRack(id) then
        return false,"Rack must be inside a grounded guide to slide"
    end
    local rack=session.Gears:RackModel(id)
    local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not rack or not rack.Parent or not root
        or not self.D.nearPlayer(player,rack:GetPivot().Position) then
        return false,"Guided rack must remain on your own plot"
    end
    if session.ActiveRackId~=id
        or session.RackDirection~=direction then
        session.Gears:StopMotion()
    end
    for crankId in pairs(session.Cranks) do
        self:StopCrank(session,crankId)
    end
    session.ActiveRackId=id
    session.RackDirection=direction
    session.RackLastInput=os.clock()
    return true,"Rack push active • release Q/E to stop"
end

function Simulation:InputRack(player,id,direction,holding,release)
    local session=self.Sessions[player]
    if not session or session.ActiveRackId~=id then return end
    if release==true or holding~=true then
        self:StopRack(session)
        return
    end
    if direction~=session.RackDirection
        or not session.Gears or not session.Gears:CanDriveRack(id)
        or session.Paused then
        self:StopRack(session)
        return
    end
    session.RackLastInput=os.clock()
end

-- The remote is a held-input watchdog, never a speed command. Client
-- values other than release or held state have no effect on crank power.
function Simulation:InputCrank(player,id,_desired,holding,release)
    local session=self.Sessions[player]
    if not session or session.ActiveCrankId~=id then return end
    local crank=session.Cranks and session.Cranks[id]
    if not crank then return end
    if release==true or holding~=true then
        self:StopCrank(session,id)
        return
    end
    if session.Paused or not crank.Running then return end
    local now=os.clock()
    -- The authenticated session and proximity are also rechecked on
    -- StepCranks, so a remote cannot keep an abandoned motor turning.
    if now-(crank.LastPacket or 0)<0.04 then return end
    crank.LastPacket=now
    crank.LastInput=now
end

function Simulation:SetStatus(player,running,grounded)
    player:SetAttribute("OPENWORKS_Simulating",running)
    player:SetAttribute("OPENWORKS_Grounded",grounded~=false)
    -- Native motion joints remain passive. Geared rigid bodies are
    -- scripted/anchored; ordinary free shafts may use native crank torque.
end

function Simulation:Graph(player, seed)
    local d = self.D
    -- Simulation is NEVER allowed to compile an arbitrary graph. Every
    -- participant must first belong to a deliberately registered Assembly.
    local assemblyId=seed:GetAttribute("AssemblyId")
    if type(assemblyId)~="string" or assemblyId=="" then
        return nil,"Equip Assembly, press N, name it, select parts and press Enter before simulating"
    end
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
                    or kind == "Cylindrical" or kind == "Fixed"
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

    -- A registered assembly is the ONLY scope. Disconnected mechanisms
    -- deliberately added to the registration also simulate together;
    -- registering one mechanism never silently includes other plots.
    local visited={}
    local queue={}
    for _,model in pairs(owned) do
        if model:GetAttribute("AssemblyId")==assemblyId then
            local memberKey=bodyKey(model)
            if not visited[memberKey] then
                visited[memberKey]=true
                table.insert(queue,memberKey)
            end
        end
    end
    if not visited[seedKey] or #queue==0 then
        return nil,"Selected component is not registered to that assembly"
    end

    -- Do not compile HALF of an assembled mechanism. If the player adds
    -- a shaft, crank or gear later, it must explicitly be selected into
    -- the registered assembly using the dedicated Assembly tool.
    for _,edge in ipairs(edges) do
        local left=visited[edge.a]==true
        local right=visited[edge.b]==true
        if left~=right then
            return nil,"A physically connected part is outside this assembly. Equip Assembly, select it and add the missing part"
        end
    end
    -- A single primitive may be deliberately included from an editor
    -- component. ComponentId is a selection group, NEVER a mechanical weld,
    -- so partial editor grouping alone is not a physics error. Crossing
    -- an actual mechanical relationship still requires both sides above.

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
    local assemblyId=seed:GetAttribute("AssemblyId")
    if type(assemblyId)~="string" or assemblyId=="" then
        return false,"Simulation requires an assembly. Equip Assembly, press N, select members and press Enter"
    end
    if not d.nearPlayer(player, seed:GetPivot().Position) then
        return false, "Mechanism is out of construction range"
    end

    local graph, reason = self:Graph(player, seed)
    if not graph then return false, reason end
    local unregisteredGears=countNearbyUnregisteredGears(
        player,graph,d.folder)

    local session = {
        Originals = {},
        Grounded = payload.grounded == true, -- ungrounded unless explicitly requested
        World = nil,
        Paused = false,
        PausedParts = nil,
        Constraints = {},
        SeedId = payload.seedId,
        AssemblyName = graph.assemblyName,
        ActiveRelations={},
        Cranks={},
        ActiveCrankId=nil,
        ActiveRackId=nil,
        RackDirection=0,RackLastInput=0,
        Gears=nil,
        UnregisteredGears=unregisteredGears,
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

        -- Identify all fully kinematic gear/shaft/crank bodies BEFORE
        -- constructing any native prefab joints. A kinematic gear has
        -- ZERO Roblox physical constraints, including internal welds.
        session.Gears=GearKinematics.new(graph,copies)

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
                    if part~=anchor and not session.Gears:IsKinematic(id) then
                        local weld=Instance.new("WeldConstraint")
                        weld.Name="PrefabInternalPart"
                        weld.Part0=anchor
                        weld.Part1=part
                        weld.Parent=runtime
                    end
                end
            end
        end

        -- Engagement is automatically determined by tooth geometry at
        -- runtime; saved legacy K pairs are only construction metadata.

        -- 3. Rebuild authored relationships against the CLONED bodies.
        local collisionExclusions = 0
        for _, edge in ipairs(graph.edges) do
            local target = copies[edge.target:GetAttribute("InstanceId")]
            local source = copies[edge.source:GetAttribute("InstanceId")]
            if not target or not source then error("Missing joint endpoint") end
            local p0, p1 = target.PrimaryPart, source.PrimaryPart
            if edge.kind == "Gear" then
                -- Legacy K relationships are OPTIONAL metadata.
                -- Meshing and transmission use geometry every frame.
                continue
            elseif session.Gears:IsKinematic(edge.source:GetAttribute("InstanceId"))
                or session.Gears:IsKinematic(edge.target:GetAttribute("InstanceId")) then
                -- No native hinge/bearing/spring/rigid constraint may
                -- exert ANY physical influence on geared rigid bodies.
                -- Rigid members move cohesively under GearKinematics.
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

        -- Only standalone, ungeared crank shafts receive a native
        -- AngularVelocity drive. Geared shafts have no motor, bearing
        -- forces, collisions or physical joints; GearKinematics owns them.
        for _,original in ipairs(graph.models) do
            if not HandCrankMath.IsCrank(original) then continue end
            local id=original:GetAttribute("InstanceId")
            local model=copies[id]
            if not model or not model.PrimaryPart then
                error("HandCrank has no simulation primary shaft")
            end
            local coupledShaft=nil
            for _,edge in ipairs(graph.edges) do
                if edge.kind=="Weld" or edge.kind=="Fixed" then
                    local other=if edge.source==original then edge.target
                        elseif edge.target==original then edge.source else nil
                    if other and HandCrankMath.IsOutputShaft(other) then
                        local fitted=HandCrankMath.Fits(original,other)
                        local sized=math.abs(original.PrimaryPart.Size.Y
                            -other.PrimaryPart.Size.Y)<0.001
                        if fitted and sized then
                            coupledShaft=other
                            break
                        end
                    end
                end
            end
            local shaftCopy=if coupledShaft then
                copies[coupledShaft:GetAttribute("InstanceId")] else nil
            local root=if shaftCopy then shaftCopy.PrimaryPart
                else model.PrimaryPart
            local drivenId=if coupledShaft then
                coupledShaft:GetAttribute("InstanceId") else id
            local kinematic=session.Gears:IsKinematic(drivenId)
            local drive=nil
            if not kinematic then
                local attachment=Instance.new("Attachment")
                attachment.Name="ControlledCrankShaftAxis"
                attachment.Parent=root
                drive=Instance.new("AngularVelocity")
                drive.Name="HandCrank_ControlledRotation"
                drive.Attachment0=attachment
                drive.RelativeTo=Enum.ActuatorRelativeTo.World
                drive.MaxTorque=HandCrankMath.MaxTorque
                drive.AngularVelocity=Vector3.zero
                drive.Enabled=false
                drive.Parent=runtime
            end

            local axis=root.CFrame.RightVector.Unit
            model:SetAttribute("OPENWORKS_CrankRunning",false)
            session.Cranks[id]={
                Root=root,Model=model,Drive=drive,Axis=axis,
                Coupled=coupledShaft~=nil,DrivenId=drivenId,
                BodyKey=bodyKey(original),
                DrivenBodyKey=if coupledShaft then bodyKey(coupledShaft)
                    else bodyKey(original),
                Running=false,NativeSpeed=0,LastInput=0,LastPacket=0,
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
                        and not HandCrankMath.IsCrank(edge.target)
                        and type(edge.target:GetAttribute("GearTeeth"))~="number" then
                        groundedKey=edge.b
                        break
                    end
                end
            end
            -- Without a real bearing housing and without explicit ground,
            -- a crank mechanism is FREE rather than freezing the crank.
            if groundedKey then session.GroundKeys[groundedKey]=true end
        end

        -- Bearing housings support geared axles translationally without
        -- applying any native Roblox hinge force to gear rotation. Loose
        -- geared shafts instead fall as one scripted rigid body; a free
        -- bearing-mounted gear follows the shaft's movement.
        session.Gears:ConfigureSupport(graph,copies,session.GroundKeys,
            created,player.Character,d.folder)

        -- Ground/movable colors are drawn by client WorldVisuals as
        -- fill-only Highlights. Do not create overlapping simulation
        -- Highlights or outlines here; authored physics stays authoritative.
        for key, originals in pairs(graph.bodies) do
            if graph.included[key] then
                local rootAnchor = bodyAnchors[key]
                for _, original in ipairs(originals) do
                    for _, part in ipairs(copyParts[original:GetAttribute("InstanceId")] or {}) do
                        if session.Gears:IsKinematic(
                            original:GetAttribute("InstanceId")) then
                            -- These parts have no Roblox physics influence:
                            -- bearing constraints were skipped above and
                            -- collisions cannot push or jam a gear train.
                            part.Anchored=true
                            part.CanCollide=false
                            part.CanTouch=false
                            part.CanQuery=part:GetAttribute("GearPivotOnly")~=true
                        else
                            part.Anchored=session.GroundKeys[key]==true
                                and part==rootAnchor
                        end
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
        .. (if session.Gears
            and (#session.Gears.Gears>0 or #session.Gears.Racks>0) then
            string.format(" • %d gears / %d racks / %d automatic contact(s)",
                #session.Gears.Gears,#session.Gears.Racks,
                session.Gears.Contacts) else "")
        .. (if unregisteredGears>0 then
            string.format(" • WARNING: %d nearby gear(s) NOT in assembly",
                unregisteredGears) elseif session.Gears
                and #session.Gears.Unmeshed>0 then
                    " • "..session.Gears.Unmeshed[1].Gear..": "
                        ..session.Gears.Unmeshed[1].Reason else "")
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

    for crankId in pairs(session.Cranks) do
        self:StopCrank(session,crankId)
    end
    self:StopRack(session)
    if session.Gears then session.Gears:StopMotion() end
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
        table.insert(lines,if session.Paused then "PAUSED"
            elseif session.Gears and session.Gears:IsKinematic(id)
                then "KINEMATIC TRANSMISSION" else "LIVE PHYSICS")
        if session.Gears
            and (#session.Gears.Gears>0 or #session.Gears.Racks>0) then
            table.insert(lines,string.format(
                "%d transmission contact(s) • %d gears • %d racks",
                session.Gears.Contacts,#session.Gears.Gears,
                #session.Gears.Racks))
        end
        if session.Gears and session.Gears:IsKinematic(id) then
            table.insert(lines,session.Gears:Explain(id))
        end
        if session.UnregisteredGears and session.UnregisteredGears>0 then
            table.insert(lines,string.format(
                "%d nearby gear(s) excluded from assembly",
                session.UnregisteredGears))
        end
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
