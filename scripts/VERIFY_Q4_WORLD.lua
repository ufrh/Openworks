--!strict
-- CLIENT Studio Play Command Bar. Requires server CSG availability.
local RS=game:GetService("ReplicatedStorage")
local FORGE=require(RS:WaitForChild("FORGE"))
local docs=FORGE:GetService("OpenWorksDocuments")
local world=FORGE:GetService("OpenWorksWorld")
assert(docs and world,"Q4 FORGE world service did not boot")
local square={Vector2.new(-.3,-.3),Vector2.new(.3,-.3),
 Vector2.new(.3,.3),Vector2.new(-.3,.3)}
local ok,body=docs:CreateSketchBody("Q4 Test",Vector3.new(0,3,0),
 Vector3.new(-.3,200,-.3),Vector3.new(.6,1,.6),square,.2)
assert(ok and body,"Server document creation failed: "..tostring(body))
local published,why=world:PublishAll()
assert(published,why)
local folder=workspace:WaitForChild("OPENWORKS_Published",10)
local owner=folder and folder:WaitForChild(tostring(game.Players.LocalPlayer.UserId),20)
local part=nil
for _=1,100 do
 part=owner and owner:FindFirstChild("Component_"..body.id)
 if part then break end
 task.wait(.2)
end
if not part then
 local _,stats=world:GetStats()
 error("Server CSG publication did not produce physical body: "..
  tostring(stats and stats.error))
end
assert(part:IsA("BasePart") and not part.Anchored and part.CanCollide)
assert(part:GetAttribute("OWComponentId")==body.id)
local drag=part:FindFirstChild("OW_ServerPhysicalDrag")
assert(drag and drag:IsA("DragDetector") and drag.RunLocally==false,
 "Published part must have replicated server-side physical dragging")
local _,stats=world:GetStats()
assert(stats.published>=1)
local deleteOK,err=docs:DeleteComponent(body.id,body.revision)
assert(deleteOK,err)
task.wait(.2)
assert(part.Parent==nil,"Deleted source still has a published world body")
print("Q4 WORLD PASS: server CSG, replicated physics ownership and cleanup")
