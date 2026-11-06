--!strict
-- Studio CLIENT command-bar smoke test after Rojo sync.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players")
local FORM=ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM")
local Profile=require(FORM.RoundedLProfile)
local Document=require(FORM.Document)
local Fabricator=require(FORM.Fabricator)
local HistoryTopology=require(Players.LocalPlayer.PlayerScripts.Openworks.HistoryTopology)
local doc=Document.new()
local component=doc:create("RoundedL",Vector3.zero)
local node=component.nodes[1]
assert(node.size==Vector3.new(1,1,0.6))
assert(Fabricator.requiresCompile(component),
	"Rounded L must be a manufactured solid even without added operations")
local wall,radius=Profile.parameters(node)
assert(wall>0 and radius>0 and wall+radius<node.size.X)
local xy=Profile.outline(node)
assert(#xy==4+Profile.SEGMENTS+2)
assert((xy[4]-Vector2.new(wall+radius,wall)).Magnitude<1e-6)
assert((xy[4+Profile.SEGMENTS]-Vector2.new(wall,wall+radius)).Magnitude<1e-5)
for i=5,3+Profile.SEGMENTS do
	local p=xy[i]
	local center=Vector2.new(wall+radius,wall+radius)
	assert(math.abs((p-center).Magnitude-radius)<1e-5,
		"Inner curved ramp must have a consistent true radius")
end
local temp=Instance.new("Part")
temp.Anchored=true
temp.CFrame=CFrame.identity
temp.Size=node.size
local topology,why=HistoryTopology.build(temp,Document.snapshot(component))
assert(topology,"Rounded L history topology failed: "..tostring(why))
local curved=0
for _,f in ipairs(topology.faces) do
	if f.tag=="rounded_l_inside" then
		assert(f.curved,"Inner ramp must be flagged as curved")
		curved+=1
	end
end
assert(curved==Profile.SEGMENTS,
	"Expected 12 separate inner rounded ramp facets")
temp:Destroy()
print("FORM RoundedL: L cross section, circular tangent ramp and manufactured topology validated")
