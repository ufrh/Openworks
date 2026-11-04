--!strict
-- FORM bevel-junction numeric smoke test.
-- Execute in Roblox Studio Command Bar (server or client) after Rojo sync.
-- This tests pure junction geometry; CSG runtime results still need a
-- visual playtest using File on a real L-shaped workpiece.
local FORM=game:GetService("ReplicatedStorage"):WaitForChild("Openworks"):WaitForChild("FORM")
local BevelJunction=require(FORM.BevelJunction)

local X,Y,Z=Vector3.xAxis,Vector3.yAxis,Vector3.zAxis
local inner={
	a=Vector3.new(0,-1,0),b=Vector3.new(0,1,0),
	n1=X,n2=Z,width=0.20,interior=true,
}
local function outer(y:number,axis:Vector3,wall:Vector3)
	return {
		a=Vector3.new(0,y,0),b=Vector3.new(0,y,0)+axis*2,
		n1=if y>0 then Y else -Y,n2=wall,width=0.12,interior=false,
	}
end
local cases={
	outer(1,Z,X),
	{a=Vector3.new(0,1,0),b=Vector3.new(2,1,0),
		n1=Y,n2=Z,width=0.12,interior=false},
	outer(-1,Z,X),
	{a=Vector3.new(0,-1,0),b=Vector3.new(2,-1,0),
		n1=-Y,n2=Z,width=0.12,interior=false},
}
for index,exterior in ipairs(cases) do
	local plan=BevelJunction.plan(inner,exterior)
	assert(plan,"L-notch bevel junction #"..index.." not recognized")
	assert(plan.intoVoid:Dot(if index%2==1 then Z else X)>0.99,
		"Junction transitioned BACKWARD along the solid perimeter")
	local surface,normal=BevelJunction.surfacePolygon(plan)
	assert(#surface==3 and normal.Magnitude>0.99)
	assert((surface[1]-surface[2]).Magnitude>0.04)
	local profile,travel=BevelJunction.clipProfile(plan)
	assert(#profile==4 and travel.Magnitude>=inner.width)
	for _,point in ipairs(surface) do
		assert(math.abs((point-surface[1]):Dot(normal))<1e-5,
			"Corner wedge must lie on the original exterior bevel plane")
	end
end
local backwards={
	a=Vector3.new(0,1,0),b=Vector3.new(0,1,-2),
	n1=Y,n2=X,width=0.12,interior=false,
}
assert(BevelJunction.plan(inner,backwards)==nil,
	"Opposite-arm false junction must never cut the workpiece")
assert(BevelJunction.plan(cases[1],cases[2])==nil,
	"Two exterior bevels cannot form an additive junction")
print("FORM BevelJunction: 6 analytic smoke checks passed")
