-- Source-of-truth construction document; no Roblox Instance references.
-- All authored translations and dimensions are integer ticks (1000 ticks/u).
local Units = require(script.Parent.Units)

local Document = {}
Document.Version = 1
Document.MaxBlocks = 32

function Document.New()
    return { version = Document.Version, revision = 0, blocks = {} }
end

function Document.CopyBlocks(blocks)
    local copied = {}
    for _, block in ipairs(blocks) do
        table.insert(copied, table.clone(block))
    end
    return copied
end

function Document.Snapshot(source)
    return {
        version = Document.Version,
        revision = source.revision,
        blocks = Document.CopyBlocks(source.blocks),
    }
end

local function validTick(value, magnitude, allowZero)
    return Units.IsFinite(value)
        and value % 1 == 0
        and math.abs(value) <= magnitude
        and (allowZero or value > 0)
end

function Document.Sanitize(saved)
    if saved == nil then
        return Document.New(), true
    end
    if type(saved) ~= "table" or saved.version ~= Document.Version
        or not validTick(saved.revision, 1000000000, true) or saved.revision < 0
        or type(saved.blocks) ~= "table" then
        return Document.New(), false
    end

    local count = 0
    for key in pairs(saved.blocks) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1
            or key > Document.MaxBlocks then
            return Document.New(), false
        end
        count += 1
    end
    local result = Document.New()
    local seen = {}
    for index = 1, count do
        local block = saved.blocks[index]
        if type(block) ~= "table"
            or type(block.id) ~= "string"
            or #block.id == 0 or #block.id > 80
            or seen[block.id]
            or not validTick(block.x, 2048000, true)
            or not validTick(block.y, 2048000, true)
            or not validTick(block.z, 2048000, true)
            or not validTick(block.sx, 32000, false)
            or not validTick(block.sy, 32000, false)
            or not validTick(block.sz, 32000, false) then
            return Document.New(), false
        end
        seen[block.id] = true
        table.insert(result.blocks, {
            id = block.id,
            x = block.x, y = block.y, z = block.z,
            sx = block.sx, sy = block.sy, sz = block.sz,
        })
    end
    result.revision = saved.revision
    return result, true
end

function Document.Find(document, id)
    for i, block in ipairs(document.blocks) do
        if block.id == id then
            return i, block
        end
    end
    return nil, nil
end

return Document
