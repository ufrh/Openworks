--!strict
-- Run on the Roblox Studio CLIENT Command Bar during Play, after Rojo
-- synchronization. This is a real FORGE server round trip, not a mock.
local RS=game:GetService("ReplicatedStorage")
local FORGE=require(RS:WaitForChild("FORGE"))
local FORM=RS:WaitForChild("Openworks"):WaitForChild("FORM")
local Document=require(FORM.Document)
local api=FORGE:GetService("OpenWorksDocuments")
assert(api and api.CreateSketchBody and api.ApplyOperation,
 "Q2 FORGE document service was not loaded on the server")

local ring={
 Vector2.new(-.5,-.5),Vector2.new(.5,-.5),
 Vector2.new(.5,.5),Vector2.new(-.5,.5),
}
local ok,body=api:CreateSketchBody("Q2 Server Roundtrip",
 Vector3.new(15,0,-20),Vector3.new(-.5,200,-.5),
 Vector3.new(1,1,1),ring,.35)
assert(ok and body and body.id,"Server rejected valid component: "..tostring(body))
local id=body.id
local stale,rejection=api:ApplyOperation(id,body.revision-1,
 "DrillFace",{origin=Vector3.new(0,.175,0),normal=Vector3.yAxis,
 diameter=.05,depth=.35,through=true})
assert(not stale and type(rejection)=="string",
 "Stale revision did not fail")

local original=body.revision
local applied
applied,body=api:ApplyOperation(id,original,"DrillFace",{
 origin=Vector3.new(.1,.175,.05),normal=Vector3.yAxis,
 diameter=.05,depth=.35,through=true,
})
assert(applied and body.revision>original,
 "FORGE rejected valid drill: "..tostring(body))
local doc=Document.new()
local part=doc:adoptSnapshot(body)
assert(part and #doc:listFeatures(part)==1,
 "Server drill snapshot did not preserve hole metadata")
local savedId=doc:listFeatures(part)[1].id
local accepted,updated=api:GetSnapshot(id)
assert(accepted and updated.revision==body.revision)
assert(#updated.operations==1)
local reverted
reverted,body=api:RestoreRevision(id,updated.revision,original)
assert(reverted and #body.operations==0,
 "Rollback to a prior server-issued revision failed: "..tostring(body))
local removed,problem=api:DeleteComponent(id,body.revision)
assert(removed,"Q2 test component cleanup failed: "..tostring(problem))
local found=api:GetSnapshot(id)
assert(not found,"Deleted component can still be fetched")
print("OPENWORKS Q2 FORGE PASS: create, revision rejection, drill "..savedId..
 ", server snapshots, rollback and cleanup")
