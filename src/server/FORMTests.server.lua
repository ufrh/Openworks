local ReplicatedStorage = game:GetService('ReplicatedStorage')
local FORM = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'))

local Cut = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'):WaitForChild('Cut'))
local Boolean = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'):WaitForChild('Boolean'))
local Union = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'):WaitForChild('Union'))

local function close(a, b)
    return FORM.volumeClose(a, b)
end

local function run()
    local box = FORM.box(Vector3.new(100, 50, 20))
    local result = FORM.validate(box)
    assert(result.ok, 'Box topology failed: ' .. tostring(result.issues[1] and result.issues[1].code))
    assert(#box.vertices == 8 and #box.triangles == 12, 'Unexpected topology')
    assert(close(FORM.signedVolume(box), 100000), 'Incorrect volume')
    local shifted = FORM.box(Vector3.new(100, 50, 20))
    for i, vertex in shifted.vertices do
        shifted.vertices[i] = vertex + Vector3.new(10000, -12000, 18000)
    end
    assert(close(FORM.signedVolume(shifted), 100000),
        'Signed volume depends on workpiece translation')


    local lo, hi = FORM.bounds(box)
    assert(lo == Vector3.new(-50, -25, -10) and hi == Vector3.new(50, 25, 10), 'Incorrect bounds')

    local inverted = FORM.box(Vector3.new(10, 10, 10))
    inverted.triangles[1] = {1, 2, 3}
    assert(not FORM.validate(inverted).ok, 'Inverted face undetected')

    local open = FORM.box(Vector3.new(10, 10, 10))
    table.remove(open.triangles)
    assert(not FORM.validate(open).ok, 'Open mesh undetected')

    for _, normal in {
        Vector3.xAxis,
        Vector3.yAxis,
        Vector3.zAxis,
        Vector3.new(1, 0.4, 0.7).Unit,
    } do
        local positive, negative = Cut.split(box, Vector3.zero, normal)
        assert(positive and negative, 'Planar split failed: ' .. tostring(negative))
        assert(FORM.validate(positive).ok and FORM.validate(negative).ok, 'Open cut surfaces')
        local expected = FORM.signedVolume(box)
        local actual = FORM.signedVolume(positive) + FORM.signedVolume(negative)
        local difference = actual - expected
        local tolerance = FORM.volumeTolerance(expected)
        print(string.format('[FORM] Cut volume delta: %+.9f mm^3 (limit %.9f)', difference, tolerance))
        assert(math.abs(difference) <= tolerance,
            string.format('Split volume mismatch: expected %.9f, actual %.9f, delta %+.9f mm^3', expected, actual, difference))
    end

    local outside, reason = Cut.split(box, Vector3.new(200, 0, 0), Vector3.xAxis)
    assert(not outside and reason == 'PLANE_DOES_NOT_INTERSECT', 'Outside plane not rejected')

    local first, remainder = Cut.split(box, Vector3.zero, Vector3.xAxis)
    assert(first and remainder, 'First chained cut failed: ' .. tostring(remainder))

    local second, third = Cut.split(first, Vector3.new(0, 7, 0), Vector3.yAxis)
    assert(second and third, 'Second chained cut failed: ' .. tostring(third))

    local pieces = {remainder, second, third}
    local total = 0
    for i, piece in pieces do
        local checked = FORM.validate(piece)
        assert(checked.ok, 'Chained piece ' .. i .. ' has invalid topology')
        total += FORM.signedVolume(piece)
    end

    print(string.format('[FORM] Chained cuts: %d solids, total volume %.6f mm^3', #pieces, total))
    assert(close(total, FORM.signedVolume(box)), 'Chained cuts changed total material volume')

    local beforeVertices, beforeTriangles = #box.vertices, #box.triangles
    local touching, touchReason = Cut.split(box, Vector3.new(50, 0, 0), Vector3.xAxis)
    assert(not touching and touchReason == 'PLANE_DOES_NOT_INTERSECT', 'Tangent plane should not split material')

    local diagonal, diagonalReason = Cut.split(box, Vector3.zero, Vector3.new(1, 2, 0))
    assert(diagonal and diagonalReason, 'Vertex-intersecting cut failed: ' .. tostring(diagonalReason))
    assert(FORM.validate(diagonal).ok and FORM.validate(diagonalReason).ok, 'Coincident cut topology failed')
    assert(close(FORM.signedVolume(diagonal) + FORM.signedVolume(diagonalReason), 100000),
        'Coincident cut lost material')

    assert(#box.vertices == beforeVertices and #box.triangles == beforeTriangles, 'Failed cut mutated input')
    assert(FORM.validate(box).ok, 'Failed cut damaged original geometry')

    local tool = FORM.box(Vector3.new(40, 20, 30))
    local leftovers, removed = Boolean.subtract(box, tool)
    assert(leftovers, 'Convex subtraction failed: ' .. tostring(removed))
    assert(close(removed, 16000), 'Incorrect subtraction volume')
    local remaining = 0
    for _, piece in leftovers do
        assert(FORM.validate(piece).ok, 'Subtraction created invalid geometry')
        remaining += FORM.signedVolume(piece)
    end
    assert(close(remaining, 84000), 'Subtraction did not conserve stock material')

    local failures = {}

    local function verifyUnified(label, stockSolid, cutterSolid, expected)
        local success, mesh, reason, stats = pcall(Union.subtractBoundary, stockSolid, cutterSolid, expected)
        if not success then
            failures[#failures + 1] = label .. ': ' .. tostring(mesh)
            warn('[FORM] ' .. label .. ' reconstruction error: ' .. tostring(mesh))
            return
        end

        if not mesh then
            failures[#failures + 1] = label .. ': ' .. tostring(reason)
            warn('[FORM] ' .. label .. ' reconstruction rejected: ' .. tostring(reason))
            if stats and stats.weld then
                local weld = stats.weld
                print(string.format('[FORM] %s weld: %d triangles, %d edge splits, %d T-junctions, Euler=%d, components=%d',
                    label, weld.trianglesAfter, weld.repairedJunctions, weld.tJunctions,
                    weld.eulerCharacteristic, weld.connectedComponents))
                for code, count in weld.issueCounts do
                    print(string.format('[FORM] %s topology: %s x%d', label, code, count))
                end
                for _, detail in weld.issueDetails do print('[FORM] Fault edge: ' .. detail) end
                for _, detail in weld.junctionDetails do print('[FORM] Residual T-junction: ' .. detail) end
            end
            return
        end

        local weld = stats.weld
        if weld.connectedComponents ~= 1 or weld.eulerCharacteristic ~= 0 then
            failures[#failures + 1] = label .. ': unexpected topology / hole genus'
        end
        assert(FORM.validate(mesh).ok, label .. ' reconstructed mesh failed validation')
        assert(close(FORM.signedVolume(mesh), expected), label .. ' reconstructed volume mismatch')
        print(string.format('[FORM] %s unified: %d vertices, %d triangles, components=%d, Euler=%d, volume=%.4f mm^3',
            label, weld.verticesAfter, weld.trianglesAfter, weld.connectedComponents,
            weld.eulerCharacteristic, FORM.signedVolume(mesh)))
    end

    verifyUnified('Rectangular', box, tool, remaining)

    local joinedA = FORM.box(Vector3.new(30, 20, 10))
    local joinedB = FORM.box(Vector3.new(30, 20, 10))
    for i, vertex in joinedA.vertices do joinedA.vertices[i] = vertex - Vector3.new(15, 0, 0) end
    for i, vertex in joinedB.vertices do joinedB.vertices[i] = vertex + Vector3.new(15, 0, 0) end
    local adjacentMesh, adjacentReason, adjacentStats = Union.reconstruct({joinedA, joinedB}, 12000)
    assert(adjacentMesh, 'Adjacent block union failed: ' .. tostring(adjacentReason))
    assert(adjacentStats.weld.connectedComponents == 1, 'Adjacent union disconnected')
    assert(adjacentStats.weld.eulerCharacteristic == 2, 'Adjacent union has incorrect Euler characteristic')
    assert(close(FORM.signedVolume(adjacentMesh), 12000), 'Adjacent union changed volume')
    print(string.format('[FORM] Adjacent box union: %d triangles, Euler=%d, volume=%.4f mm^3',
        #adjacentMesh.triangles, adjacentStats.weld.eulerCharacteristic, FORM.signedVolume(adjacentMesh)))

    print(string.format('[FORM] Boolean subtract: %d pieces, removed %.4f mm^3', #leftovers, removed))
    local cylinder = FORM.cylinder(7, 70, 12)
    assert(FORM.validate(cylinder).ok, 'Cylindrical cutter is not watertight')

    local expectedCylinder = 12 * 7 * 7 * math.sin(2 * math.pi / 12) * 70 / 2
    assert(math.abs(FORM.signedVolume(cylinder) - expectedCylinder) < 0.05,
        'Cylinder mesh has incorrect volume')

    local drilled, drillRemoved = Boolean.subtract(box, cylinder)
    assert(drilled, 'Cylindrical subtraction failed: ' .. tostring(drillRemoved))

    local drillRemaining = 0
    for _, piece in drilled do
        assert(FORM.validate(piece).ok, 'Drilling generated invalid topology')
        drillRemaining += FORM.signedVolume(piece)
    end

    assert(math.abs(drillRemoved - expectedCylinder * 50 / 70) < 0.1,
        'Incorrect drilling removal volume')
    assert(math.abs(drillRemaining + drillRemoved - FORM.signedVolume(box)) < 0.01,
        'Drilling failed volume conservation')
    verifyUnified('Drilled', box, cylinder, drillRemaining)

    print(string.format('[FORM] Drilled %d-sided opening: removed %.4f mm^3 across %d solids',
        12, drillRemoved, #drilled))

    assert(#failures == 0, '[FORM] Topology reconstruction failures: ' .. table.concat(failures, ' | '))
    print('[FORM] Foundation, cuts, subtraction, and direct stock/cutter boundary tests passed')
end

run()
