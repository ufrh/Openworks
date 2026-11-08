--!strict
-- CLIENT Studio Command Bar: manufactured three-part shaft joint checks.
local RS=game:GetService("ReplicatedStorage")
local modules=RS:WaitForChild("Openworks"):WaitForChild("Assembly")
local Matcher=require(modules.FeatureMatcher)
local Fit=require(modules.ShaftFit)
local Graph=require(modules.RelationshipGraph)
local Compiler=require(modules.ConstraintCompiler)
local a={id="hole:1",type="Hole",componentLocalCenter=Vector3.zero,
 componentLocalAxis=-Vector3.yAxis,diameter=.1,depth=.6,through=true}
local b={id="hole:2",type="Hole",componentLocalCenter=Vector3.new(.1,0,0),
 componentLocalAxis=-Vector3.yAxis,diameter=.104,depth=.6,through=true}
assert(Matcher.compatible(a,b))
local poseB=CFrame.new(-.1,0,0)
local poseS=CFrame.Angles(0,0,-math.pi/2)
local shaftSize=Vector3.new(.085,.6,.085)
local ok,why=Fit.validate(a,b,poseB,CFrame.identity,CFrame.identity,
 shaftSize,poseS)
assert(ok,why)
local wide=Fit.validate(a,b,poseB,CFrame.identity,CFrame.identity,
 Vector3.new(.11,.6,.11),poseS)
assert(not wide,"An oversized shaft must be rejected")
local misaligned=Fit.validate(a,b,poseB,CFrame.identity,CFrame.identity,
 shaftSize,CFrame.new(.2,0,0)*poseS)
assert(not misaligned,"The shaft must actually occupy both bores")
local graph=Graph.new()
local missing=graph:add("Revolute",
 {componentId=1,featureId=a.id},{componentId=2,featureId=b.id})
assert(not missing,"A two-hole joint without manufactured hardware is invalid")
local record,err=graph:add("Revolute",
 {componentId=1,featureId=a.id},{componentId=2,featureId=b.id},nil,3)
assert(record,err)
record.relativePose=poseB
record.shaftRelative=poseS
local restored=Graph.new()
restored:restore(graph:list())
assert(restored.joints[record.id] and restored.joints[record.id].shaftId==3)
local partA=Instance.new("Part")
local partB=Instance.new("Part")
local shaft=Instance.new("Part")
partA.Name="OW_Test_A" partB.Name="OW_Test_B" shaft.Name="OW_Test_Shaft"
partA.Anchored=true partB.Anchored=true shaft.Anchored=true
partA.CFrame=CFrame.identity partB.CFrame=poseB
shaft.Shape=Enum.PartType.Cylinder
shaft.Size=Vector3.new(.6,.085,.085)
shaft.CFrame=poseS
for _,p in ipairs({partA,partB,shaft}) do
 p:SetAttribute("OWSourceLocalFrame",CFrame.identity)
 p.Parent=workspace
end
local node={position=Vector3.zero,rotation=Vector3.zero}
local objects,problem=Compiler.compile(record,
 {[1]=partA,[2]=partB,[3]=shaft},
 {[1]={nodes={node}},[2]={nodes={node}},
  [3]={nodes={{kind="Cylinder",position=Vector3.zero,rotation=Vector3.zero}}}},
 {[1]={[a.id]=a},[2]={[b.id]=b}},workspace)
assert(objects,problem)
local hinge=nil
local hasRetention=false
local invented=false
for _,obj in ipairs(objects) do
 if obj:IsA("HingeConstraint") then hinge=obj end
 if obj:IsA("WeldConstraint") and obj.Part1==shaft then
  hasRetention=true
 end
 if obj:IsA("BasePart") then invented=true end
end
assert(hinge and hinge.Attachment0 and hinge.Attachment1)
assert(hasRetention,"Shaft must be retained by one manufactured body")
assert(not invented,"Compiler must NEVER generate a bolt or pin")
assert(math.abs(hinge.Attachment0.WorldAxis:Dot(-Vector3.yAxis))>.99,
 "Hinge must follow the manufactured bore centerline")
Compiler.destroy(objects)
partA:Destroy() partB:Destroy() shaft:Destroy()
print("Q3 SHAFT PASS: real hardware, clearance, matching axes, graph, hinge")
