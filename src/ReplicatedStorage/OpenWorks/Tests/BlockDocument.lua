-- Run from the Studio server command bar during Play:
-- require(game.ReplicatedStorage.OpenWorks.Tests.BlockDocument)()
local Document = require(script.Parent.Parent.Shared.BlockDocument)

local function block(id)
    return { id = id, x = 0, y = 2000, z = 0, sx = 4000, sy = 4000, sz = 4000 }
end

return function()
    local fresh, ok = Document.Sanitize(nil)
    assert(ok and fresh.revision == 0 and #fresh.blocks == 0)

    local valid = { version = 1, revision = 4, blocks = { block("one") } }
    local copy, accepted = Document.Sanitize(valid)
    assert(accepted and copy.revision == 4 and copy.blocks[1].id == "one")
    assert(copy.blocks[1] ~= valid.blocks[1])

    local invalid = {
        { version = 2, revision = 0, blocks = {} },
        { version = 1, revision = -1, blocks = {} },
        { version = 1, revision = 0, blocks = { block("same"), block("same") } },
        { version = 1, revision = 0, blocks = { [2] = block("gap") } },
        { version = 1, revision = 0, blocks = { block("") } },
        { version = 1, revision = 0, blocks = { { id = "bad", x = 0, y = 0, z = 0, sx = 0, sy = 1, sz = 1 } } },
    }
    local tooMany = { version = 1, revision = 0, blocks = {} }
    for i = 1, Document.MaxBlocks + 1 do
        tooMany.blocks[i] = block(tostring(i))
    end
    table.insert(invalid, tooMany)
    for _, saved in ipairs(invalid) do
        local _, validSaved = Document.Sanitize(saved)
        assert(not validSaved, "invalid save must not be accepted")
    end
    print("[OpenWorks] BlockDocument regression checks passed")
end
