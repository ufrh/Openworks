local ReplicatedStorage = game:GetService('ReplicatedStorage')
local FORM = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'))
local Machine = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'):WaitForChild('Machine'))
local Cut = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'):WaitForChild('Cut'))

local function assertUnified(machine, label, expectedEuler)
    local mesh, reason, stats = machine:mesh()
    if not mesh and stats and stats.weld then
        local weld = stats.weld
        warn(string.format('[FORM:Machine] %s rejected: %s, %d triangles, %d components, Euler=%d',
            label, tostring(reason), weld.trianglesAfter, weld.connectedComponents, weld.eulerCharacteristic))
        for code, count in weld.issueCounts do
            warn(string.format('[FORM:Machine] %s: %s x%d', label, code, count))
        end
    end
    assert(mesh, label .. ' unified mesh failed: ' .. tostring(reason))
    assert(FORM.validate(mesh).ok, label .. ' unified mesh is not watertight')
    assert(FORM.volumeClose(FORM.signedVolume(mesh), machine:volume()), label .. ' changed volume')
    assert(stats.weld.connectedComponents == 1, label .. ' has disconnected surfaces')
    assert(stats.weld.eulerCharacteristic == expectedEuler,
        string.format('%s Euler mismatch: expected %d, got %d', label, expectedEuler,
            stats.weld.eulerCharacteristic))
    print(string.format('[FORM:Machine] %s: %d triangles, %.4f mm^3, Euler=%d',
        label, #mesh.triangles, FORM.signedVolume(mesh), stats.weld.eulerCharacteristic))
end

local function apply(machine, spec, label)
    local before = machine:volume()
    local ok, removed = machine:apply(spec)
    assert(ok, label .. ' failed: ' .. tostring(removed))
    assert(removed > 0, label .. ' removed no material')
    assert(FORM.volumeClose(machine:volume() + removed, before), label .. ' lost material')
    print(string.format('[FORM:Machine] %s: -%.4f mm^3', label, removed))
end

local function run()
    local box = FORM.box(Vector3.new(100, 50, 40))
    local stock = FORM.signedVolume(box)
    assert(FORM.volumeClose(stock, 200000), 'Incorrect stock volume')
    local machine = Machine.new(box)

    apply(machine, {kind = 'drill', center = Vector3.zero, radius = 7,
        height = 70, segments = 12}, 'Drill')
    local drilledVolume = machine:volume()
    assertUnified(machine, 'Drilled through-hole', 0)
    local drilledMesh = machine:mesh()
    local nonconvexResult, nonconvexReason = Cut.split(drilledMesh, Vector3.zero, Vector3.xAxis)
    assert(not nonconvexResult and string.find(tostring(nonconvexReason), 'NON_CONVEX_INPUT', 1, true),
        'General non-convex input bypassed strict convexity validation')


    assert(machine:undo(), 'Undo failed')
    assert(FORM.volumeClose(machine:volume(), stock), 'Undo failed to restore volume')
    assert(machine:redo(), 'Redo failed')
    assert(FORM.volumeClose(machine:volume(), drilledVolume), 'Redo failed to restore volume')

    local beforeFailure = machine:status()
    local invalid, reason = machine:apply({kind = 'drill', center = Vector3.zero,
        radius = -1, height = 70})
    assert(not invalid and reason, 'Invalid cutter was accepted')
    assert(machine:status().operations == beforeFailure.operations, 'Invalid cutter mutated history')
    assert(FORM.volumeClose(machine:volume(), beforeFailure.volume), 'Invalid cutter mutated workpiece')
    local untouched, untouchedReason = machine:apply({kind = 'drill',
        center = Vector3.new(1000, 0, 0), radius = 3, height = 70, segments = 12})
    assert(not untouched and untouchedReason == 'NO_MATERIAL_REMOVED', 'No-op machining was committed')
    assert(machine:status().operations == beforeFailure.operations, 'No-op changed operation history')

    apply(machine, {kind = 'pocket', center = Vector3.new(22, 23, -7),
        size = Vector3.new(16, 16, 16)}, 'Blind pocket')
    apply(machine, {kind = 'slot', from = Vector3.new(-32, 0, -10),
        to = Vector3.new(-17, 0, -10), radius = 3, height = 70, segments = 12}, 'Machined slot')
    assertUnified(machine, 'Repeated drilling and milling', 2 - 2 * 2)
    print('[FORM:Machine] Sequential drill + pocket + slot passed convex-lineage validation')

    local status = machine:status()
    assert(status.operations == 3 and status.redo == 0, 'Incorrect operation state')
    assert(FORM.volumeClose(status.removedTotal + status.volume, stock), 'Machining volume accounting failed')

    assert(machine:undo(), 'Undo slot failed')
    apply(machine, {kind = 'saw', point = Vector3.new(45, 0, 0),
        normal = Vector3.xAxis}, 'Saw cut after undo')
    assert(machine:status().redo == 0, 'New operation did not clear redo history')

    local chamfer = Machine.new(box)
    apply(chamfer, {kind = 'chamfer', axisA = 'X', signA = 1,
        axisB = 'Z', signB = 1, distance = 4}, '45-degree chamfer')
    assertUnified(chamfer, 'Chamfered box', 2)

    local fillet = Machine.new(box)
    apply(fillet, {kind = 'fillet', axisA = 'X', signA = -1,
        axisB = 'Z', signB = 1, radius = 4, segments = 6}, 'Faceted edge fillet')
    assertUnified(fillet, 'Filleted box', 2)

    local profile = Machine.new(box)
    apply(profile, {kind = 'profile',
        points = {
            Vector3.new(-29, 0, 12),
            Vector3.new(-13, 0, 12),
            Vector3.new(-13, 0, 1),
        },
        radius = 2.5, height = 70, segments = 12}, 'Swept milling profile')
    assertUnified(profile, 'Polyline through-cut', 0)

    local saw = Machine.new(box)
    apply(saw, {kind = 'saw', point = Vector3.new(45, 0, 0), normal = Vector3.xAxis},
        'Plane trim')
    assertUnified(saw, 'Planar trimmed box', 2)

    machine:reset()
    assert(machine:status().operations == 0, 'Reset left operations in history')
    assert(FORM.volumeClose(machine:volume(), stock), 'Reset failed to restore workpiece')
    print('[FORM:Machine] All machining, history and topology tests passed')
end

run()
