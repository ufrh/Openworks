--!strict
-- The first authored sketch IS the component stock. No hidden Block,
-- Cylinder or other starting primitive participates in its geometry.
local SketchBodyProfile={}
function SketchBodyProfile.outline(node):{Vector2}
	local basis=node.profileSize
	local sx=node.size.X/basis.X
	local sz=node.size.Z/basis.Y
	local result={}
	for _,point in ipairs(node.profilePoints) do
		table.insert(result,Vector2.new(point.X*sx,point.Y*sz))
	end
	return result
end
function SketchBodyProfile.profile(node):({Vector3},Vector3)
	local positions={}
	for _,p in ipairs(SketchBodyProfile.outline(node)) do
		table.insert(positions,Vector3.new(p.X,-node.size.Y*0.5,p.Y))
	end
	return positions,Vector3.new(0,node.size.Y,0)
end
function SketchBodyProfile.area(node):number
	local ring=SketchBodyProfile.outline(node)
	local twice=0
	for i,p in ipairs(ring) do
		local nextP=ring[i%#ring+1]
		twice+=p.X*nextP.Y-nextP.X*p.Y
	end
	return math.abs(twice)*0.5
end
return SketchBodyProfile
