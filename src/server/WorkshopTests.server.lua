local ReplicatedStorage = game:GetService('ReplicatedStorage')
local FORM = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'))
local Workshop = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('Workshop'))

local function drill()
    return {kind = 'drill', center = {x = 0, y = 0, z = 0},
        radius = 7, height = 70, segments = 12}
end

local function pocket()
    return {kind = 'pocket', center = {x = 22, y = 23, z = -7},
        size = {x = 16, y = 16, z = 16}}
end

local function slot()
    return {kind = 'slot', from = {x = -32, y = 0, z = -10},
        to = {x = -17, y = 0, z = -10}, radius = 3, height = 70, segments = 12}
end

local function insert(job, spec, label)
    local ok, reason = job:insert(spec)
    assert(ok, label .. ': ' .. tostring(reason))
end

local function run()
    local job = Workshop.new({x = 100, y = 50, z = 40}, 'Precision Bracket')
    local originalVolume = job:summary().volume
    assert(FORM.volumeClose(originalVolume, 200000), 'Wrong initial stock volume')

    insert(job, drill(), 'Drill')
    insert(job, pocket(), 'Pocket')
    insert(job, slot(), 'Slot')
    local baseline = job:summary()
    assert(baseline.operations == 3 and baseline.totalOperations == 3, 'Wrong initial timeline count')
    assert(FORM.volumeClose(baseline.volume, 184240), 'Wrong baseline machining volume')

    local mesh, reason, stats = job.machine:mesh()
    assert(mesh, 'Timeline mesh failed: ' .. tostring(reason))
    assert(FORM.validate(mesh).ok and stats.weld.eulerCharacteristic == -2,
        'Timeline reconstructed invalid topology')

    local saved = job:serialize()
    assert(#saved < Workshop.MAX_JSON_BYTES, 'Project exceeds import size budget')
    local restored, restoreReason = Workshop.deserialize(saved)
    assert(restored, 'Project JSON replay failed: ' .. tostring(restoreReason))
    assert(restored.name == job.name and restored.cursor == job.cursor, 'Project name/cursor lost')
    assert(FORM.volumeClose(restored:summary().volume, baseline.volume), 'Project replay changed material')

    local invalid = saved:gsub('"version":1', '"version":999', 1)
    if invalid ~= saved then
        local rejected = Workshop.deserialize(invalid)
        assert(not rejected, 'Incorrect project format version was accepted')
    end

    local beforeInvalid = job:summary()
    local beforeLastKind = job.operations[3].kind
    local invalidEdit = table.clone(slot())
    invalidEdit.radius = 1000
    local changed = pcall(function() job:edit(3, invalidEdit) end)
    assert(not changed, 'Invalid operation edit should have failed validation')
    assert(job:summary().operations == beforeInvalid.operations
        and FORM.volumeClose(job:summary().volume, beforeInvalid.volume)
        and job.operations[3].kind == beforeLastKind, 'Rejected edit changed existing timeline')

    local invalidOperation = drill()
    invalidOperation.center = {x = 490, y = 0, z = 0}
    local added, addReason = job:insert(invalidOperation)
    assert(not added and addReason, 'Non-intersecting operation was committed')
    assert(job:summary().operations == beforeInvalid.operations
        and FORM.volumeClose(job:summary().volume, beforeInvalid.volume),
        'Rejected insertion changed the saved project')

    assert(job:undo(), 'Undo failed')
    local undoVolume = job:summary().volume
    assert(undoVolume > baseline.volume, 'Undo should restore removed material')
    local undoneJson = job:serialize()
    local undoneProject, undoneReason = Workshop.deserialize(undoneJson)
    assert(undoneProject, 'Undone project JSON invalid: ' .. tostring(undoneReason))
    assert(undoneProject.cursor == 2 and #undoneProject.operations == 3,
        'Undo/redo history was not serialized')
    assert(undoneProject:redo(), 'Imported history cannot redo')

    assert(job:redo(), 'Redo failed')
    assert(FORM.volumeClose(job:summary().volume, baseline.volume), 'Redo volume incorrect')

    local removeOk, removeReason = job:remove(3)
    assert(removeOk, 'Removing slot failed: ' .. tostring(removeReason))
    assert(job:summary().operations == 2, 'Deleting an operation did not rebuild')

    local up, upReason = job:move(2, -1)
    assert(up, 'Reordering independent tools failed: ' .. tostring(upReason))
    assert(job.operations[1].kind == 'pocket', 'Timeline order was not updated')
    local down, downReason = job:move(1, 1)
    assert(down, 'Restoring tool order failed: ' .. tostring(downReason))
    assert(job.operations[1].kind == 'drill', 'Timeline order was not restored')

    job:resetStock({x = 80, y = 50, z = 30})
    assert(job.cursor == 0 and #job.operations == 0, 'New stock did not clear timeline')
    assert(FORM.volumeClose(job:summary().volume, 120000), 'New stock volume incorrect')

    print('[WORKSHOP] Project replay, editing, reorder, atomic rejection, undo/redo and JSON tests passed')
end

run()
