--!strict
-- OPENWORKS: compact, watertight brushed-DC motor mesh generator.
-- Studio authoring only. Runtime uses published mesh assets, never EditableMesh.
-- 24 circumferential segments; separate material sections and face-corner normals.
local AssetService = game:GetService("AssetService")
local Generator = {}
local N = 24
local TAU = math.pi * 2
local KEYS = {"RearCan", "Housing", "Endbell"}
local OFFSETS = {
    RearCan = Vector3.new(-1.10, 0, 0),
    Housing = Vector3.new(0.29, 0, 0),
    Endbell = Vector3.new(1.1775, 0, 0),
}
Generator.Keys = table.freeze(KEYS)
Generator.Offsets = table.freeze(OFFSETS)
Generator.Version = 3

local function make(key: string)
    local mesh = assert(AssetService:CreateEditableMesh(),
        "Cannot allocate EditableMesh. Enable Mesh / Image APIs.")
    local offset = assert(OFFSETS[key], "Unknown motor mesh key")
    local ids, normals, positions = {}, {}, {}
    local triangles = 0
    local function V(x: number, r: number, a: number): number
        local p = Vector3.new(x, r * math.cos(a), r * math.sin(a)) - offset
        local hash = string.format("%.6f/%.6f/%.6f", p.X, p.Y, p.Z)
        local id = ids[hash]
        if not id then
            id = mesh:AddVertex(p)
            ids[hash] = id
            positions[id] = p
        end
        return id
    end
    local function normId(n: Vector3): number
        local v = n.Unit
        local hash = string.format("%.5f/%.5f/%.5f", v.X, v.Y, v.Z)
        local id = normals[hash]
        if not id then
            id = mesh:AddNormal(v)
            normals[hash] = id
        end
        return id
    end
    local function T(a: number, b: number, c: number, na: Vector3, nb: Vector3?, nc: Vector3?)
        local cross = (positions[b] - positions[a]):Cross(positions[c] - positions[a])
        assert(cross.Magnitude > 0.0000001, "Degenerate motor triangle")
        local face = mesh:AddTriangle(a, b, c)
        mesh:SetFaceNormals(face, {
            normId(na),
            normId(nb or na),
            normId(nc or na),
        })
        triangles += 1
    end
    local function Q(v1: number, v2: number, v3: number, v4: number,
            n1: Vector3, n2: Vector3?, n3: Vector3?, n4: Vector3?)
        T(v1, v2, v3, n1, n2 or n1, n3 or n1)
        T(v1, v3, v4, n1, n3 or n1, n4 or n1)
    end
    local PX, NX = Vector3.xAxis, -Vector3.xAxis
    local function rad(t: number): Vector3
        return Vector3.new(0, math.cos(t), math.sin(t))
    end
    local function tangent(t: number): Vector3
        return Vector3.new(0, -math.sin(t), math.cos(t))
    end
    local function outer(x0: number, x1: number, r0: number, r1: number, a: number, b: number)
        local slope = (r1-r0)/(x1-x0)
        local na = (rad(a) - PX*slope).Unit
        local nb = (rad(b) - PX*slope).Unit
        Q(V(x0,r0,a), V(x0,r0,b), V(x1,r1,b), V(x1,r1,a), na,nb,nb,na)
    end
    local function inner(x0: number, x1: number, r0: number, r1: number, a: number, b: number)
        local slope = (r1-r0)/(x1-x0)
        local na = (-rad(a) + PX*slope).Unit
        local nb = (-rad(b) + PX*slope).Unit
        Q(V(x0,r0,a), V(x1,r1,a), V(x1,r1,b), V(x0,r0,b), na,na,nb,nb)
    end
    local function radialCap(x: number, r0: number, r1: number, a: number, b: number, positive: boolean)
        if positive then
            Q(V(x,r0,a), V(x,r1,a), V(x,r1,b), V(x,r0,b), PX)
        else
            Q(V(x,r0,a), V(x,r0,b), V(x,r1,b), V(x,r1,a), NX)
        end
    end
    local function side(x0: number, x1: number, r0: number, r1: number, t: number, upper: boolean)
        if upper then
            Q(V(x0,r0,t), V(x1,r0,t), V(x1,r1,t), V(x0,r1,t), tangent(t))
        else
            Q(V(x0,r0,t), V(x0,r1,t), V(x1,r1,t), V(x1,r0,t), -tangent(t))
        end
    end
    -- Full-thickness annular tube, capped at both ends.
    local function tube(x0: number, x1: number, ri: number, ro: number)
        for j = 0, N-1 do
            local a, b = TAU*j/N, TAU*(j+1)/N
            outer(x0,x1,ro,ro,a,b)
            inner(x0,x1,ri,ri,a,b)
            radialCap(x0,ri,ro,a,b,false)
            radialCap(x1,ri,ro,a,b,true)
        end
    end

    local function fullDisc(x: number, r: number, positive: boolean)
        -- A complete end face, not just an annular ring.
        -- Edge vertices reuse the cylinder ring, giving a sealed end.
        local center = V(x,0,0)
        for j=0,N-1 do
            local a,b=TAU*j/N,TAU*(j+1)/N
            if positive then
                T(center,V(x,r,a),V(x,r,b),PX)
            else
                T(center,V(x,r,b),V(x,r,a),NX)
            end
        end
    end

    if key == "RearCan" then
        -- Occupancy mesh: three short, narrow ventilation slots,
        -- then seal every exposed interior, end, and side wall.
        local xs = {-1.80,-1.45,-0.91,-0.40}
        local function has(i: number, j: number): boolean
            if i < 1 or i >= #xs then return false end
            j = j % N
            if i ~= 2 then return true end
            local sector = j % 8
            return sector ~= 3 and sector ~= 4
        end
        for i = 1, #xs-1 do
            for j = 0, N-1 do
                if not has(i,j) then continue end
                local x0,x1 = xs[i], xs[i+1]
                local a,b = TAU*j/N,TAU*(j+1)/N
                outer(x0,x1,0.99,0.99,a,b)
                inner(x0,x1,0.87,0.87,a,b)
                -- For the two terminal rings, full disks replace annular caps.
                if i > 1 and not has(i-1,j) then
                    radialCap(x0,0.87,0.99,a,b,false)
                end
                if i < #xs-1 and not has(i+1,j) then
                    radialCap(x1,0.87,0.99,a,b,true)
                end
                if not has(i,j-1) then side(x0,x1,0.87,0.99,a,false) end
                if not has(i,j+1) then side(x0,x1,0.87,0.99,b,true) end
            end
        end
        -- Seal BOTH ends. The far rear is a full metal backplate and
        -- the other end is a closed internal divider behind the main housing.
        -- This prevents seeing into an empty pipe from either direction.
        fullDisc(xs[1],0.99,false)
        fullDisc(xs[#xs],0.99,true)
    elseif key == "Housing" then
        local xs = {-0.46,0.81,1.04}
        local radii = {1.09,1.09,0.99}
        local ri = 0.91
        for i=1,#xs-1 do
            for j=0,N-1 do
                local a,b = TAU*j/N,TAU*(j+1)/N
                outer(xs[i],xs[i+1],radii[i],radii[i+1],a,b)
                inner(xs[i],xs[i+1],ri,ri,a,b)
            end
        end
        for j=0,N-1 do
            local a,b = TAU*j/N,TAU*(j+1)/N
            radialCap(xs[1],ri,radii[1],a,b,false)
            radialCap(xs[#xs],ri,radii[#xs],a,b,true)
        end
        -- Thin cast seams are real radial solids, not single-sided strips.
        for k=0,3 do
            local a = TAU*(k+0.5)/4 - 0.018
            local b = TAU*(k+0.5)/4 + 0.018
            local x0,x1,r0,r1 = -0.43,0.80,1.092,1.111
            outer(x0,x1,r1,r1,a,b)
            inner(x0,x1,r0,r0,a,b)
            radialCap(x0,r0,r1,a,b,false)
            radialCap(x1,r0,r1,a,b,true)
            side(x0,x1,r0,r1,a,false)
            side(x0,x1,r0,r1,b,true)
        end
    else -- Endbell
        local xs = {0.96,1.13}
        local rs = {0.195,0.51,0.82,1.02}
        local function has(i: number,j: number): boolean
            if i < 1 or i >= #rs then return false end
            if i ~= 2 then return true end
            local sector = j % 6
            return sector == 0 or sector == 1 or sector == 4 or sector == 5
        end
        for i=1,#rs-1 do
            for j=0,N-1 do
                if not has(i,j) then continue end
                local a,b = TAU*j/N,TAU*(j+1)/N
                radialCap(xs[1],rs[i],rs[i+1],a,b,false)
                radialCap(xs[2],rs[i],rs[i+1],a,b,true)
                if not has(i-1,j) then inner(xs[1],xs[2],rs[i],rs[i],a,b) end
                if not has(i+1,j) then outer(xs[1],xs[2],rs[i+1],rs[i+1],a,b) end
                if not has(i,j-1) then side(xs[1],xs[2],rs[i],rs[i+1],a,false) end
                if not has(i,j+1) then side(xs[1],xs[2],rs[i],rs[i+1],b,true) end
            end
        end
        -- One stepped watertight bearing wall. In particular, do NOT
        -- stack two capped tubes: their coincident interior caps create
        -- four-face edges and z-fighting at the shoulder.
        for j=0,N-1 do
            local a,b = TAU*j/N,TAU*(j+1)/N
            outer(1.13,1.24,0.47,0.47,a,b)
            outer(1.24,1.42,0.37,0.37,a,b)
            inner(1.13,1.24,0.177,0.177,a,b)
            inner(1.24,1.42,0.177,0.177,a,b)
            radialCap(1.13,0.177,0.47,a,b,false)
            radialCap(1.24,0.37,0.47,a,b,true)
            radialCap(1.42,0.177,0.37,a,b,true)
        end
        -- Annular formed edge lip, sharply separated from the plate surface.
        tube(0.935,1.14,0.998,1.028)
    end
    assert(triangles < 2500, "Motor mesh exceeds prototype triangle budget")
    return mesh, triangles
end

function Generator.Build(key: string)
    return make(key)
end
return table.freeze(Generator)
