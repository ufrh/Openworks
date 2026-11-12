--!strict
-- Render a continuous closed belt using Beam segments (no collidable links).
-- A single anchored marker carries world-space path attachments; no physics
-- proxies, hitboxes, overhead TextLabels, or per-segment moving Parts.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local BeltMath=require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("BeltMath"))

local Visual={}
Visual.__index=Visual
local N=32

function Visual.new(parent)
    local marker=Instance.new("Part")
    marker.Name="OPENWORKS_BeltPathOnly"
    marker.Size=Vector3.new(0.05,0.05,0.05)
    marker.Position=Vector3.zero
    marker.Anchored=true
    marker.Transparency=1
    marker.CanCollide=false
    marker.CanTouch=false
    marker.CanQuery=false
    marker.CastShadow=false
    marker.Parent=parent
    local attachments,beams={},{}
    for i=1,N do
        local att=Instance.new("Attachment")
        att.Name="BeltPoint_"..i
        att.Parent=marker
        attachments[i]=att
    end
    for i=1,N do
        local beam=Instance.new("Beam")
        beam.Name="BeltSpan_"..i
        beam.Attachment0=attachments[i]
        beam.Attachment1=attachments[i%N+1]
        beam.Width0=0.105
        beam.Width1=0.105
        beam.LightEmission=0.1
        beam.Color=ColorSequence.new(Color3.fromRGB(192,157,104))
        beam.Transparency=NumberSequence.new(0.05)
        beam.FaceCamera=true
        beam.Segments=1
        beam.Parent=marker
        beams[i]=beam
    end
    return setmetatable({Marker=marker,Attachments=attachments,
        Beams=beams,Enabled=true},Visual)
end

function Visual:SetEnabled(enabled)
    self.Enabled=enabled
    for _,beam in ipairs(self.Beams) do beam.Enabled=enabled end
end

function Visual:Update(path)
    if not self.Marker.Parent then return end
    if not path then
        for _,beam in ipairs(self.Beams) do beam.Enabled=false end
        return
    end
    local points=BeltMath.Points(path)
    -- BeltMath emits N points exactly: two tangent spans plus both wraps.
    for index,att in ipairs(self.Attachments) do
        att.Position=points[index] or points[#points]
    end
    for _,beam in ipairs(self.Beams) do beam.Enabled=self.Enabled end
end

-- Update authored belt paths after a valid construction transform.
function Visual.Refresh(parent,path)
    local marker=parent:FindFirstChild("OPENWORKS_BeltPathOnly")
    if not marker or not path then return end
    for i,point in ipairs(BeltMath.Points(path)) do
        local att=marker:FindFirstChild("BeltPoint_"..i)
        if att then att.Position=point end
    end
end

return Visual
