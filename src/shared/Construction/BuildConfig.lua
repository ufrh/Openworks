--!strict
-- Player-owned construction and persistence limits. Autosave is dirty-only.
return table.freeze({
    MaxPartsPerPlayer = 500,
    UndoLimit = 50,
    MinActionInterval = 0.075,
    RequestName = "OPENWORKS_ConstructionRequest",
    FolderName = "OPENWORKS_Constructed",
    GalleryName = "OPENWORKS_PrimitiveGallery_DRAFT",
    PlotSize = 124,
    PlotSpacing = 168,
    MaxPlotsPerServer = 20,
    AutoSaveEnabled = true,
    AutoSaveIntervalSeconds = 120,
    AutoSaveDebounceSeconds = 10,
    AutoSaveCheckSeconds = 10,
    AutoSaveRetrySeconds = 45,
})
