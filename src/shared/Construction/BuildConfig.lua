--!strict
-- Initial Build/Edit rules. Construction is limited per player until persistence.
return table.freeze({
    MaxPartsPerPlayer = 500,
    UndoLimit = 50,
    MinActionInterval = 0.075,
    RequestName = "OPENWORKS_ConstructionRequest",
    FolderName = "OPENWORKS_Constructed",
    GalleryName = "OPENWORKS_PrimitiveGallery_DRAFT",
})
