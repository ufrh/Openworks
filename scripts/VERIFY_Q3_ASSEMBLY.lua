--!strict
-- CLIENT/Studio Command Bar. Pure feature graph + physical constraint tests.
local RS=game:GetService("ReplicatedStorage")
local modules=RS:WaitForChild("Openworks"):WaitForChild("Assembly")
local Matcher=require(modules.FeatureMatcher)
local Graph=require(modules.RelationshipGraph)
local Compiler=require(modules.ConstraintCompiler)
local a={id="hole:1",type="Hole",componentLocalCenter=Vector3.zero,
 componentLocalAxis=-Vector3.yAxis,diameter=.1,depth=.6,through=true}
local b={id="hole:2",type="Hole",componentLocalCenter=Vector3.new(.1,0,0),
 componentLocalAxis=-Vector3.yAxis,diameter=.104,depth=.6,through=true}
assert(Matcher.compatible(a,b))
assert(not Matcher.compatible(a,{id="wrong",type="Hole",
 componentLocalCenter=Vector3.zero,componentLocalAxis=Vector3.yAxis,
 diameter=.25,depth=.2}))
local pose=CFrame.new(-.1,0,0)
local matched=Matcher.candidates({a},{b},CFrame.identity,pose,.5)
assert(#matched==1 and matched[1].distance<.001)
local fitting,why=Matcher.validateRelative(a,b,pose,CFrame.identity,CFrame.identity)
assert(fitting,why)
local fail=Matcher.validateRelative(a,b,CFrame.new(.6,0,0),
 CFrame.identity,CFrame.identity)
assert(not fail,"Server must reject holes which miss laterally")
local graph=Graph.new()
local record,err=graph:add("Revolute",
 {componentId=1,featureId=a.id},{componentId=2,featureId=b.id})
assert(record,err)
record.relativePose=pose
local duplicate=graph:add("Rigid",
 {componentId=1,featureId=a.id},{componentId=2,featureId=b.id})
assert(not duplicate,"Duplicate relationship must be rejected")
local restored=Graph.new()
restored:restore(graph:list())
assert(restored.joints[record.id] and
 restored.joints[record.id].relativePose==pose,
 "Joint identity and relative placement must survive reload")
local partA=Instance.new("Part")
local partB=Instance.new("Part")
partA.Name="OW_Test_A" partB.Name="OW_Test_B"
partA.Anchored=true partB.Anchored=true
partA.CFrame=CFrame.identity partB.CFrame=pose
partA:SetAttribute("OWSourceLocalFrame",CFrame.identity)
partB:SetAttribute("OWSourceLocalFrame",CFrame.identity)
partA.Parent=workspace partB.Parent=workspace
local node={position=Vector3.zero,rotation=Vector3.zero}
local objects,problem=Compiler.compile(record,
 {[1]=partA,[2]=partB},
 {[1]={nodes={node}},[2]={nodes={node}}},
 {[1]={[a.id]=a},[2]={[b.id]=b}},workspace)
assert(objects,problem)
local hinge=nil
for _,obj in ipairs(objects) do
 if obj:IsA("HingeConstraint") then hinge=obj end
end
assert(hinge and hinge.Attachment0 and hinge.Attachment1)
assert(math.abs(hinge.Attachment0.WorldAxis:Dot(-Vector3.yAxis))>.99,
 "Hinge axis must align to the manufactured hole centerline")
Compiler.destroy(objects)
partA:Destroy() partB:Destroy()
print("Q3 ASSEMBLY PASS: clearance, axial fit, graph stability and real hinge axis")
