--!strict
-- Parametric quarter-round inside-corner L prism. The XY profile is
-- extruded along Z. The outside corners stay square; the material
-- occupies the concave fillet joining the foot and upright.
local RoundedLProfile={}
RoundedLProfile.SEGMENTS=12
function RoundedLProfile.parameters(node)
	local width,height,depth=node.size.X,node.size.Y,node.size.Z
	local wall=math.min(width,height)*0.22
	local radius=math.min(width-wall,height-wall)*0.55
	return wall,radius
end
function RoundedLProfile.outline(node):{Vector2}
	local w,h=node.size.X,node.size.Y
	local wall,radius=RoundedLProfile.parameters(node)
	local points={
		Vector2.new(0,0),Vector2.new(w,0),
		Vector2.new(w,wall),Vector2.new(wall+radius,wall),
	}
	-- From horizontal floor to the upright wall; the quarter-circle
	-- is tangent to both and never exceeds the material envelope.
	for i=1,RoundedLProfile.SEGMENTS do
		local angle=i/RoundedLProfile.SEGMENTS*math.pi*0.5
		table.insert(points,Vector2.new(
			wall+radius-radius*math.sin(angle),
			wall+radius-radius*math.cos(angle)))
	end
	table.insert(points,Vector2.new(wall,h))
	table.insert(points,Vector2.new(0,h))
	return points
end
function RoundedLProfile.profile(node):({Vector3},Vector3)
	local half=node.size*0.5
	local result={}
	for _,p in ipairs(RoundedLProfile.outline(node)) do
		table.insert(result,Vector3.new(p.X-half.X,p.Y-half.Y,-half.Z))
	end
	return result,Vector3.new(0,0,node.size.Z)
end
return RoundedLProfile
