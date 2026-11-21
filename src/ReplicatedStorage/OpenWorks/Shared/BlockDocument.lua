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
    if type(saved) ~= "table" or saved.version ~= Document.Version then
        return Document.New()
    end

    local result = Document.New()
    local seen = {}
    if type(saved.blocks) ~= "table" then
        return result
    end
    for _, block in ipairs(saved.blocks) do
        if #result.blocks >= Document.MaxBlocks then break end
        if type(block) == "table"
            and type(block.id) == "string"
            and #block.id > 0 and #block.id <= 80
            and not seen[block.id]
            and validTick(block.x, 2048000, true)
            and validTick(block.y, 2048000, true)
            and validTick(block.z, 2048000, true)
            and validTick(block.sx, 32000, false)
            and validTick(block.sy, 32000, false)
            and validTick(block.sz, 32000, false)
        then
            seen[block.id] = true
            table.insert(result.blocks, {
                id = block.id,
                x = block.x, y = block.y, z = block.z,
                sx = block.sx, sy = block.sy, sz = block.sz,
            })
        end
    end
    result.revision = if validTick(saved.revision, 1000000000, true) and saved.revision >= 0
        then saved.revision else 0
    return result
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
