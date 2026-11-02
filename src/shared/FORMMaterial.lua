local CollectionService = game:GetService('CollectionService')

local FORMMaterial = {}

FORMMaterial.TAG = 'FORMMaterial'
FORMMaterial.ATTRIBUTE = 'isMaterial'

function FORMMaterial.mark(instance)
    assert(instance and (instance:IsA('Model') or instance:IsA('BasePart')),
        'Material must be a Model or BasePart')

    instance:SetAttribute(FORMMaterial.ATTRIBUTE, true)
    if not CollectionService:HasTag(instance, FORMMaterial.TAG) then
        CollectionService:AddTag(instance, FORMMaterial.TAG)
    end

    return instance
end

function FORMMaterial.isMarked(instance)
    return instance:GetAttribute(FORMMaterial.ATTRIBUTE) == true
        or CollectionService:HasTag(instance, FORMMaterial.TAG)
end

return FORMMaterial
