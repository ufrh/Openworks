--!strict
-- OpenWorks approved DC motor v4 geometry. Studio EditableMesh authoring ONLY.
-- All sections are actual solids; published static MeshParts are used at runtime.
local AS=game:GetService("AssetService")
local G={}
local N=32
local TAU=2*math.pi
local KEYS={"RearCan","Armature","Housing","Endbell","Bearing","Bushing"}
local OFFSETS={
    RearCan=Vector3.new(-1.135,0,0),
    Armature=Vector3.new(-1.215,0,0),
    Housing=Vector3.new(0.285,0,0),
    Endbell=Vector3.new(1.1175,0,0),
    Bearing=Vector3.new(1.335,0,0),
    Bushing=Vector3.new(1.485,0,0),
}
G.Version=4
G.Keys=table.freeze(KEYS)
G.Offsets=table.freeze(OFFSETS)
local function build(key:string)
    local offset=assert(OFFSETS[key],"Unknown motor mesh key")
    local em=assert(AS:CreateEditableMesh(),"EditableMesh unavailable; enable Mesh/Image APIs")
    local vert, positions, normalIds={}, {}, {}
    local count=0
    local function V(x:number,r:number,t:number):number
        local p=Vector3.new(x,r*math.cos(t),r*math.sin(t))-offset
        local hash=string.format("%.6f|%.6f|%.6f",p.X,p.Y,p.Z)
        local id=vert[hash]
        if not id then
            id=em:AddVertex(p)
            vert[hash]=id
            positions[id]=p
        end
        return id
    end
    local function normal(n:Vector3):number
        n=n.Unit
        local hash=string.format("%.5f|%.5f|%.5f",n.X,n.Y,n.Z)
        local id=normalIds[hash]
        if not id then
            id=em:AddNormal(n)
            normalIds[hash]=id
        end
        return id
    end
    local function T(a:number,b:number,c:number,na:Vector3,nb:Vector3?,nc:Vector3?)
        local area=(positions[b]-positions[a]):Cross(positions[c]-positions[a])
        assert(area.Magnitude>1e-7,"Degenerate motor triangle "..key)
        local face=em:AddTriangle(a,b,c)
        em:SetFaceNormals(face,{normal(na),normal(nb or na),normal(nc or na)})
        count+=1
    end
    local function Q(a:number,b:number,c:number,d:number,na:Vector3,nb:Vector3?,nc:Vector3?,nd:Vector3?)
        T(a,b,c,na,nb,nc)
        T(a,c,d,na,nc,nd)
    end
    local XP=Vector3.xAxis
    local XN=-XP
    local function rad(t:number):Vector3 return Vector3.new(0,math.cos(t),math.sin(t)) end
    local function tangent(t:number):Vector3 return Vector3.new(0,-math.sin(t),math.cos(t)) end
    local function outer(x0:number,x1:number,r0:number,r1:number,a:number,b:number)
        local slope=(r1-r0)/(x1-x0)
        local na=(rad(a)-XP*slope).Unit
        local nb=(rad(b)-XP*slope).Unit
        Q(V(x0,r0,a),V(x0,r0,b),V(x1,r1,b),V(x1,r1,a),na,nb,nb,na)
    end
    local function inner(x0:number,x1:number,r0:number,r1:number,a:number,b:number)
        local slope=(r1-r0)/(x1-x0)
        local na=(-rad(a)+XP*slope).Unit
        local nb=(-rad(b)+XP*slope).Unit
        Q(V(x0,r0,a),V(x1,r1,a),V(x1,r1,b),V(x0,r0,b),na,na,nb,nb)
    end
    local function cap(x:number,ri:number,ro:number,a:number,b:number,positive:boolean)
        if positive then
            Q(V(x,ri,a),V(x,ro,a),V(x,ro,b),V(x,ri,b),XP)
        else
            Q(V(x,ri,a),V(x,ri,b),V(x,ro,b),V(x,ro,a),XN)
        end
    end
    local function disc(x:number,r:number,positive:boolean)
        local center=V(x,0,0)
        for j=0,N-1 do
            local a,b=TAU*j/N,TAU*(j+1)/N
            if positive then T(center,V(x,r,a),V(x,r,b),XP)
            else T(center,V(x,r,b),V(x,r,a),XN) end
        end
    end
    local function side(x0:number,x1:number,ri:number,ro:number,a:number,positive:boolean)
        local n=tangent(a)
        if positive then
            Q(V(x0,ri,a),V(x1,ri,a),V(x1,ro,a),V(x0,ro,a),n)
        else
            Q(V(x0,ri,a),V(x0,ro,a),V(x1,ro,a),V(x1,ri,a),-n)
        end
    end
    local function tube(x0:number,x1:number,ri:number,ro:number)
        for j=0,N-1 do
            local a,b=TAU*j/N,TAU*(j+1)/N
            outer(x0,x1,ro,ro,a,b)
            inner(x0,x1,ri,ri,a,b)
            cap(x0,ri,ro,a,b,false)
            cap(x1,ri,ro,a,b,true)
        end
    end
    if key=="RearCan" then
        local xs={-1.85,-1.52,-0.91,-0.42}
        local ri,ro=0.88,1.00
        local function occupied(i:number,j:number):boolean
            if i<1 or i>=#xs then return false end
            j%=N
            if i~=2 then return true end
            for _,center in ipairs({4,14,24}) do
                local d=math.abs(j-center)
                d=math.min(d,N-d)
                if d<=1 then return false end
            end
            return true
        end
        for i=1,#xs-1 do
            for j=0,N-1 do
                if not occupied(i,j) then continue end
                local x0,x1=xs[i],xs[i+1]
                local a,b=TAU*j/N,TAU*(j+1)/N
                outer(x0,x1,ro,ro,a,b)
                inner(x0,x1,ri,ri,a,b)
                if not occupied(i-1,j) then cap(x0,ri,ro,a,b,false) end
                if not occupied(i+1,j) then cap(x1,ri,ro,a,b,true) end
                if not occupied(i,j-1) then side(x0,x1,ri,ro,a,false) end
                if not occupied(i,j+1) then side(x0,x1,ri,ro,b,true) end
            end
        end
        -- Annular ends (0.88..1.00) + center discs (0..0.88):
        -- fully sealed, *shared* boundary; no overlapping cap polygons.
        disc(xs[1],ri,false)
        disc(xs[#xs],ri,true)
    elseif key=="Armature" then
        local x0,x1,r=-1.48,-0.95,0.74
        for j=0,N-1 do
            local a,b=TAU*j/N,TAU*(j+1)/N
            outer(x0,x1,r,r,a,b)
        end
        disc(x0,r,false)
        disc(x1,r,true)
    elseif key=="Housing" then
        local xs={-0.47,0.82,1.04}
        local rs={1.095,1.095,0.99}
        local ri=0.89
        for i=1,#xs-1 do
            for j=0,N-1 do
                local a,b=TAU*j/N,TAU*(j+1)/N
                outer(xs[i],xs[i+1],rs[i],rs[i+1],a,b)
                inner(xs[i],xs[i+1],ri,ri,a,b)
            end
        end
        for j=0,N-1 do
            local a,b=TAU*j/N,TAU*(j+1)/N
            cap(xs[1],ri,rs[1],a,b,false)
            cap(xs[#xs],ri,rs[#xs],a,b,true)
        end
    elseif key=="Endbell" then
        local x0,x1=1.035,1.20
        local rings={0.18,0.52,0.80,1.00}
        local function occupied(i:number,j:number):boolean
            if i<1 or i>=#rings then return false end
            if i~=2 then return true end
            local q=j%8
            return q<=1 or q>=6
        end
        for i=1,#rings-1 do
            for j=0,N-1 do
                if not occupied(i,j) then continue end
                local a,b=TAU*j/N,TAU*(j+1)/N
                local r0,r1=rings[i],rings[i+1]
                cap(x0,r0,r1,a,b,false)
                cap(x1,r0,r1,a,b,true)
                if not occupied(i-1,j) then inner(x0,x1,r0,r0,a,b) end
                if not occupied(i+1,j) then outer(x0,x1,r1,r1,a,b) end
                if not occupied(i,j-1) then side(x0,x1,r0,r1,a,false) end
                if not occupied(i,j+1) then side(x0,x1,r0,r1,b,true) end
            end
        end
    elseif key=="Bearing" then
        -- A SINGLE continuous stepped bore, not two overlapping capped tubes.
        for j=0,N-1 do
            local a,b=TAU*j/N,TAU*(j+1)/N
            outer(1.20,1.33,0.47,0.47,a,b)
            outer(1.33,1.47,0.35,0.35,a,b)
            inner(1.20,1.33,0.19,0.19,a,b)
            inner(1.33,1.47,0.19,0.19,a,b)
            cap(1.20,0.19,0.47,a,b,false)
            cap(1.33,0.35,0.47,a,b,true)
            cap(1.47,0.19,0.35,a,b,true)
        end
    elseif key=="Bushing" then
        tube(1.47,1.50,0.17,0.23)
    end
    assert(count>0 and count<3500,"Motor triangle budget exceeded: "..key)
    return em,count
end
function G.Build(key:string) return build(key) end
return table.freeze(G)
