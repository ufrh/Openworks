--!strict
-- One narrowly scoped repair: two exterior File bevels ending at the
-- SAME concave profile corner leave a small square top cap. Replace just
-- that cap with one triangular corner face.
--
-- Not a generic bevel junction solver and NOT interior vertical filing.
local CornerTriangle={}
local EPS=0.008

function CornerTriangle.fileSpec(node,op)
	if op.kind=="FileMesh" then
		if op.interior==true or op.enabled==false then return nil end
		return {a=op.a,b=op.b,n1=op.normalA.Unit,n2=op.normalB.Unit,width=op.width}
	end
	if op.kind~="File" or op.enabled==false or node.kind~="Block" then return nil end
	local hx,hy,hz=node.size.X/2,node.size.Y/2,node.size.Z/2
	if op.edge=="X+" then
		return {a=Vector3.new(hx,hy,-hz),b=Vector3.new(hx,hy,hz),
			n1=Vector3.yAxis,n2=Vector3.xAxis,width=op.width}
	elseif op.edge=="X-" then
		return {a=Vector3.new(-hx,hy,-hz),b=Vector3.new(-hx,hy,hz),
			n1=Vector3.yAxis,n2=-Vector3.xAxis,width=op.width}
	elseif op.edge=="Z+" then
		return {a=Vector3.new(-hx,hy,hz),b=Vector3.new(hx,hy,hz),
			n1=Vector3.yAxis,n2=Vector3.zAxis,width=op.width}
	elseif op.edge=="Z-" then
		return {a=Vector3.new(-hx,hy,-hz),b=Vector3.new(hx,hy,-hz),
			n1=Vector3.yAxis,n2=-Vector3.zAxis,width=op.width}
	end
	return nil
end

local function capAndWall(spec)
	if spec.n1.Y>0.985 then return spec.n1,spec.n2 end
	if spec.n2.Y>0.985 then return spec.n2,spec.n1 end
	return nil,nil
end

function CornerTriangle.between(first,second)
	local capA,wallA=capAndWall(first)
	local capB,wallB=capAndWall(second)
	if not capA or not capB then return nil end
	if capA:Dot(capB)<0.985 or math.abs(wallA:Dot(wallB))>0.12 then
		return nil
	end
	local p=nil
	local otherA,otherB=nil,nil
	for _,aa in ipairs({{first.a,first.b},{first.b,first.a}}) do
		for _,bb in ipairs({{second.a,second.b},{second.b,second.a}}) do
			if (aa[1]-bb[1]).Magnitude<EPS then
				p=(aa[1]+bb[1])*0.5
				otherA,otherB=aa[2],bb[2]
				break
			end
		end
		if p then break end
	end
	if not p then return nil end
	local a=otherA-p
	local b=otherB-p
	if a.Magnitude<first.width*1.5 or b.Magnitude<second.width*1.5 then return nil end
	-- At a CONCAVE L notch, the two perimeter rays point along the
	-- adjoining wall's OUTWARD normal (towards empty space). At convex
	-- box corners they point oppositely, and must not be modified.
	if a.Unit:Dot(wallB)<0.985 or b.Unit:Dot(wallA)<0.985 then return nil end
	local wa=first.width
	local wb=second.width
	-- All four points are attached to the EXISTING top and wall planes.
	-- The interior vertex is directly below the shared corner.
	local triangle={
		p,
		p-wallA*wa,
		p-wallB*wb,
		p-capA*math.min(wa,wb),
	}
	return {corner=p,points=triangle,cap=capA,wallA=wallA,wallB=wallB}
end

function CornerTriangle.faces(junction)
	local p=junction.points
	local centroid=(p[1]+p[2]+p[3]+p[4])*0.25
	local faces={}
	for _,ids in ipairs({{1,2,3},{1,4,2},{1,3,4},{2,4,3}}) do
		local a,b,c=p[ids[1]],p[ids[2]],p[ids[3]]
		local n=(b-a):Cross(c-a)
		if n.Magnitude<1e-9 then return nil,"Collapsed corner triangle" end
		if n:Dot((a+b+c)/3-centroid)<0 then b,c=c,b n=-n end
		table.insert(faces,{polygon={a,b,c},normal=n.Unit})
	end
	return faces
end

return CornerTriangle
