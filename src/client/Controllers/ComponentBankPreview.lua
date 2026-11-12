--!strict
-- Rebuild a presentation-only bank ghost from known primitive templates.
-- The server independently validates and places its authoritative blueprint.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local construction=ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("Construction")
local Codec=require(construction:WaitForChild("ComponentBankCodec"))
local Registry=require(construction:WaitForChild("PrimitiveRegistry"))
local HandCrankMath=require(construction:WaitForChild("HandCrankMath"))
local Preview={}
function Preview.Create(entry)
    if type(entry)~="table" or type(entry.parts)~="table"
        or type(entry.anchorId)~="string" then return nil,"Invalid blueprint" end
    local combined=Instance.new("Model")
    combined.Name="OPENWORKS_ComponentGhost"
    combined:SetAttribute("FitPivotScope","Component")
    combined.WorldPivot=CFrame.identity
    local anchor
    for _,part in ipairs(entry.parts) do
        local template=Registry.Get(part.template)
        local relative=Codec.ReadPose(part.relative)
        local size=Codec.ReadVec(part.size)
        if not template or not template.Model or not relative or not size then
            combined:Destroy()
            return nil,"Saved blueprint has a missing primitive"
        end
        local model=template.Model:Clone()
        model.Name=part.template
        model:SetAttribute("TemplateId",part.template)
        model:SetAttribute("InstanceId",part.id)
        model:SetAttribute("ComponentId",entry.id)
        model:SetAttribute("ComponentAnchorId",entry.anchorId)
        if part.fitPivot then
            model:SetAttribute("FitPivotLocal",Codec.ReadVec(part.fitPivot))
        end
        if part.componentPivot and part.id==entry.anchorId then
            model:SetAttribute("ComponentFitPivotLocal",Codec.ReadVec(part.componentPivot))
        end
        if HandCrankMath.IsCrank(model) then
            HandCrankMath.ApplySize(model,size)
        else
            model.PrimaryPart.Size=size
        end
        model:PivotTo(relative)
        model.Parent=combined
        if part.id==entry.anchorId then anchor=model end
    end
    if not anchor then
        combined:Destroy()
        return nil,"Component blueprint is missing its anchor"
    end
    combined.WorldPivot=CFrame.identity
    return combined,anchor
end
return table.freeze(Preview)
