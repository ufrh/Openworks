--!strict
-- Studio Play CLIENT: adjustable snapping, source-of-truth sketch data,
-- immutable manufacturing feature identities and disable/enable behavior.
local RS=game:GetService("ReplicatedStorage")
local client=game.Players.LocalPlayer.PlayerScripts:WaitForChild("Openworks")
local SnapSettings=require(client.Tools.Snapping.SnapSettings)
local Grid=require(client.Experience.Visuals.GridOverlay)
local Sketch=require(client.Tools.Sketch.SketchEditor)
local FORM=RS:WaitForChild("Openworks"):WaitForChild("FORM")
local Document=require(FORM.Document)
local Features=require(FORM.Features)
local playerGui=game.Players.LocalPlayer.PlayerGui

local original=SnapSettings.get()
local grid=Grid.new(playerGui)
local corner=Vector3.new(0,200,0)
grid:update(corner,Vector3.new(2,1,2))
grid:setVisible(true)
assert(grid.visible and grid.lineCount>0)
local before=grid.lineCount
assert(SnapSettings.set(.25))
assert(SnapSettings.get()==.25)
assert(grid.visible and grid.lineCount~=before,
 "Grid must rebuild automatically at adjusted snap spacing")
assert(math.abs(SnapSettings.snap(.37)-.25)<1e-5)
assert(SnapSettings.set(original))
grid:destroy()

local doc=Document.new()
local ring={Vector2.new(-1,-1),Vector2.new(1,-1),
 Vector2.new(1,1),Vector2.new(-1,1)}
local part,why=doc:createSketchBody("Q2 Test",Vector3.zero,
 Vector3.new(2,1,2),ring,.5)
assert(part,why)
local points={Vector2.new(-.5,-.4),Vector2.new(.2,-.4),
 Vector2.new(.2,.3),Vector2.new(-.5,.3)}
local ok,reason=doc:addOperation(part,"SketchExtrude",{
 mode="Remove",through=true,depth=.5,points=points})
assert(ok,reason)
local op=part.operations[#part.operations]
assert(math.abs(op.points[1].X-points[1].X)<.005,
 "Sketch Boolean points must stay component-centered")
assert(math.abs(op.points[1].Y-points[1].Y)<.005)

ok,reason=doc:addOperation(part,"DrillFace",{
 origin=Vector3.new(.1,.25,.2),normal=Vector3.yAxis,
 diameter=.09,depth=.5,through=true})
assert(ok,reason)
local drill=part.operations[#part.operations]
local holes=doc:listFeatures(part)
assert(#holes==1 and holes[1].id=="hole:"..drill.id)
assert((holes[1].componentLocalCenter-Vector3.new(.1,.25,.2)).Magnitude<1e-5)
assert((holes[1].componentLocalAxis+Vector3.yAxis).Magnitude<1e-5)
assert(Features.get(part,holes[1].id)~=nil)
assert(doc:setOperationEnabled(part,drill.id,false))
assert(#doc:listFeatures(part)==0,
 "Disabled drills must not expose assembly hole candidates")
assert(doc:setOperationEnabled(part,drill.id,true))
assert(#doc:listFeatures(part)==1)
assert(doc:removeOperation(part,drill.id))
assert(#doc:listFeatures(part)==0,
 "Deleted drills must invalidate hole feature IDs")

print("OPENWORKS Q2 PASS: adjustable snap, persistent grid, centered sketch and stable drill features")
