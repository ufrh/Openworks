--!strict
-- Two exterior File profiles meeting at a concave L corner form a real
-- 45-degree miter seam, with matching round segments on both sides.
--
-- Legacy module name; this does NOT enable interior vertical filing.
local CornerTriangle={}
local EPS=0.008

function CornerTriangle.fileSpec(node,op)
	if op.kind=="FileMesh" then
		if op.interior==true or op.enabled==false then return nil end
		return {a=op.a,b=op.b,n1=op.normalA.Unit,n2=op.normalB.Unit,width=op.width,segments=op.segments or 1}
	end
	if op.kind~="File" or op.enabled==false or node.kind~="Block" then return nil end
	local hx,hy,hz=node.size.X/2,node.size.Y/2,node.size.Z/2
	if op.edge=="X+" then
		return {a=Vector3.new(hx,hy,-hz),b=Vector3.new(hx,hy,hz),
			n1=Vector3.yAxis,n2=Vector3.xAxis,width=op.width,segments=op.segments or 1}
	elseif op.edge=="X-" then
		return {a=Vector3.new(-hx,hy,-hz),b=Vector3.new(-hx,hy,hz),
			n1=Vector3.yAxis,n2=-Vector3.xAxis,width=op.width,segments=op.segments or 1}
	elseif op.edge=="Z+" then
		return {a=Vector3.new(-hx,hy,hz),b=Vector3.new(hx,hy,hz),
			n1=Vector3.yAxis,n2=Vector3.zAxis,width=op.width,segments=op.segments or 1}
	elseif op.edge=="Z-" then
		return {a=Vector3.new(-hx,hy,-hz),b=Vector3.new(hx,hy,-hz),
			n1=Vector3.yAxis,n2=-Vector3.zAxis,width=op.width,segments=op.segments or 1}
	end
	return nil
end

local function capAndWall(spec)
	if math.abs(spec.n1.Y)>0.985 then return spec.n1,spec.n2 end
	if math.abs(spec.n2.Y)>0.985 then return spec.n2,spec.n1 end
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
	-- A genuine 45-degree miter has one common radius/profile. Different
	-- widths or segment counts cannot meet at a single continuous seam.
	if math.abs(wa-wb)>1/280 or (first.segments or 1)~=(second.segments or 1) then
		return nil
	end
	-- In plan view the two edge profiles meet on the 45-degree miter
	-- line. Their projected corner is a true 90-degree inside corner;
	-- there is no extra triangular cap. For rounded Files each sampled
	-- band joins its opposite band on that same diagonal seam.
	return {corner=p,cap=capA,wallA=wallA,wallB=wallB,
		width=(wa+wb)*0.5,segments=first.segments or 1}
end

-- This is the authoritative 45-degree junction plane. Each edge
-- cutter is TRIMMED directly to this plane; the old standalone corner
-- cutter is never manufactured. Both edge cutters therefore share the
-- same line at every rounded segment.
function CornerTriangle.miterEnds(junction,first,second)
	local normal=(junction.wallA-junction.wallB).Unit
	local corner=junction.corner
	local function endFor(spec)
		local atStart=(spec.a-corner).Magnitude<EPS
		local atEnd=(spec.b-corner).Magnitude<EPS
		if not atStart and not atEnd then
			error("Miter edge has no endpoint at its shared corner",0)
		end
		return {corner=corner,normal=normal,
			atStart=atStart,atEnd=atEnd,width=junction.width}
	end
	return endFor(first),endFor(second)
end

-- No CornerTriangle.faces() or standalone corner cutter. Both File
-- cutters are clipped directly by miterEnds() to the SAME plane.
return CornerTriangle
