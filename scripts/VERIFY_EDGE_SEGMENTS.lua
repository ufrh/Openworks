--!strict
-- Run during Studio Play in the CLIENT Command Bar after Rojo sync.
-- Simulates a raised 0.5-stud block obstructing the middle of a base edge.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local player=Players.LocalPlayer
assert(player,"Run this test on the client during Play")
local EdgeAvailability=require(player:WaitForChild("PlayerScripts")
	:WaitForChild("Openworks"):WaitForChild("EdgeAvailability"))
local FORM=ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM")
local Document=require(FORM.Document)
local GeometryCutter=require(FORM.GeometryCutter)
local Fabricator=require(FORM.Fabricator)
local HistoryTopology=require(player.PlayerScripts.Openworks.HistoryTopology)

local a,b=Vector3.new(-1,0.5,-1),Vector3.new(1,0.5,-1)
local component={nodes={{kind="Block",size=Vector3.new(2,1,2)}},
	operations={{kind="SketchExtrude",mode="Add",enabled=true,depth=0.5,
		points={
			Vector2.new(0.75,0),Vector2.new(1.25,0),
			Vector2.new(1.25,0.20),Vector2.new(0.75,0.20)
		}}}}
local open=EdgeAvailability.segments(a,b,component,0.05)
assert(#open==2,"Raised block must split base edge into two exposed segments")
assert(open[1].b.X < -0.24 and open[2].a.X > 0.24,
	"Filed segments must not extend under the raised block")
assert((open[1].a-a).Magnitude<1e-5 and (open[2].b-b).Magnitude<1e-5,
	"Unobstructed outer endpoints must stay unchanged")
component.operations[1].points={
	Vector2.new(0.75,0.5),Vector2.new(1.25,0.5),
	Vector2.new(1.25,0.7),Vector2.new(0.75,0.7)
}
open=EdgeAvailability.segments(a,b,component,0.05)
assert(#open==1 and open[1].a==a and open[1].b==b,
	"Remote raised block must not shorten an unrelated edge")

-- Ensure the authored history retires ONLY the filed side, rather
-- than leaving the full stock edge available for another whole-edge cut.
local localNode={
	id=1,kind="Block",position=Vector3.zero,
	size=Vector3.new(2,1,2),rotation=Vector3.zero,
}
local livePart=Instance.new("Part")
livePart.Anchored=true
livePart.Size=localNode.size
livePart.CFrame=CFrame.identity
local modified={
	id=999,nodes={localNode},
	operations={
		component.operations[1],
		{kind="FileMesh",a=a,b=Vector3.new(-0.256,0.5,-1),
			normalA=Vector3.yAxis,normalB=-Vector3.zAxis,
			width=0.05,segments=1,enabled=true},
	},
}
-- Restore the blocking footprint for the manufactured-body test.
modified.operations[1]={
	kind="SketchExtrude",mode="Add",enabled=true,depth=0.5,
	points={
		Vector2.new(0.75,0),Vector2.new(1.25,0),
		Vector2.new(1.25,0.20),Vector2.new(0.75,0.20),
	},
}
local topology,why=HistoryTopology.build(livePart,modified)
assert(topology,"Manufactured topology failed: "..tostring(why))
local original=false
local remainder=false
for _,edge in ipairs(topology.edges) do
	if (edge.a-a).Magnitude<0.002 and (edge.b-b).Magnitude<0.002
		or (edge.b-a).Magnitude<0.002 and (edge.a-b).Magnitude<0.002 then
		original=true
	end
	if (edge.a-b).Magnitude<0.002 or (edge.b-b).Magnitude<0.002 then
		remainder=true
	end
end
assert(not original,"Original full stock edge must retire after partial filing")
assert(remainder,"Unfiled subsegment must remain in manufactured topology")
livePart:Destroy()

local document=Document.new()
local body=document:create("Block",Vector3.zero)
local smooth={
	a=Vector3.new(0,0.2,-0.3),
	b=Vector3.new(0,0.2,0.3),
	normalA=Vector3.yAxis,
	normalB=Vector3.xAxis,
	radius=14/280,segments=8,
}
local accepted,reason=document:addOperation(body,"SmoothInside",smooth)
assert(accepted,"Interior smooth operation rejected: "..tostring(reason))
assert(body.operations[#body.operations].kind=="SmoothInside")
local refused,adjacentReason=document:addOperation(body,"FileMesh",{
	a=smooth.a,b=smooth.a+Vector3.zAxis*0.15,
	normalA=Vector3.yAxis,normalB=Vector3.xAxis,
	width=14/280,segments=1,
})
assert(not refused and string.find(tostring(adjacentReason),"smoothed"),
	"File must be blocked on an edge adjoining interior smoothing")

local faces=GeometryCutter.smoothInteriorFaces(
	smooth.a,smooth.b,smooth.normalA,smooth.normalB,
	smooth.radius,smooth.segments)
assert(#faces==8,"Interior fillet must create eight rounded surface facets")
for _,face in ipairs(faces) do
	assert(#face.polygon==4 and face.normal.Magnitude>0.99,
		"Smooth facet must be a valid planar quadrilateral")
end
local key=Fabricator.geometryKey(body)
assert(string.find(key,"SI|",1,true)~=nil,
	"Interior smoothing must invalidate CSG preview cache")
print("FORM: split edge, untouched remote edge, interior smooth history and round facets verified")
