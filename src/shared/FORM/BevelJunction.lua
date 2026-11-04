--!strict
-- A bevel junction is an intersection of authored FILE surfaces, not an
-- independent corner-removal feature. Used by both manufacturing replay and
-- history-derived topology so finished geometry and selectable edges agree.
--
-- Scope: straight perpendicular concave (additive) / convex (subtractive)
-- bevels sharing an endpoint and one outward planar face. No guessed
-- tetrahedra, no edits to unconnected edges.
local BevelJunction={}
local NORMAL_DOT=0.985
local CORNER_TOLERANCE=0.009

function BevelJunction.spec(node,operation)
	if operation.enabled==false then return nil end
	if operation.kind=="FileMesh" then
		return {a=operation.a,b=operation.b,
			n1=operation.normalA,n2=operation.normalB,
			width=operation.width,interior=operation.interior==true,
			id=operation.id}
	end
	if operation.kind~="File" or node.kind~="Block" then return nil end
	local hx,hy,hz=node.size.X/2,node.size.Y/2,node.size.Z/2
	local a,b,n2
	if operation.edge=="X+" then
		a,b=Vector3.new(hx,hy,-hz),Vector3.new(hx,hy,hz)
		n2=Vector3.xAxis
	elseif operation.edge=="X-" then
		a,b=Vector3.new(-hx,hy,-hz),Vector3.new(-hx,hy,hz)
		n2=-Vector3.xAxis
	elseif operation.edge=="Z+" then
		a,b=Vector3.new(-hx,hy,hz),Vector3.new(hx,hy,hz)
		n2=Vector3.zAxis
	elseif operation.edge=="Z-" then
		a,b=Vector3.new(-hx,hy,-hz),Vector3.new(hx,hy,-hz)
		n2=-Vector3.zAxis
	else
		return nil
	end
	return {a=a,b=b,n1=Vector3.yAxis,n2=n2,
		width=operation.width,interior=false,id=operation.id}
end

-- The outside bevel must terminate at an endpoint of a vertical inside
-- bevel. One outer normal must be a wall normal shared with the inner
-- bevel; the other normal is the upper/lower exterior face normal.
function BevelJunction.plan(first,second)
	if not first or not second or first.interior==second.interior then return nil end
	local inner=if first.interior then first else second
	local outer=if first.interior then second else first
	if inner.width<0.018 or outer.width<0.018 then return nil end
	local outerAxis=outer.b-outer.a
	local innerAxis=inner.b-inner.a
	if outerAxis.Magnitude<0.04 or innerAxis.Magnitude<0.04 then return nil end
	if math.abs(outerAxis.Unit:Dot(innerAxis.Unit))>0.12 then return nil end
	local corner,otherOuter=nil,nil
	for oi,endpoint in ipairs({outer.a,outer.b}) do
		for _,innerEnd in ipairs({inner.a,inner.b}) do
			if (endpoint-innerEnd).Magnitude<CORNER_TOLERANCE then
				corner=(endpoint+innerEnd)/2
				otherOuter=if oi==1 then outer.b else outer.a
				break
			end
		end
		if corner then break end
	end
	if not corner or not otherOuter then return nil end
	local shared,unshared
	for _,o in ipairs({outer.n1,outer.n2}) do
		for _,i in ipairs({inner.n1,inner.n2}) do
			if o.Unit:Dot(i.Unit)>NORMAL_DOT then
				if shared then return nil end
				shared=o.Unit
				unshared=if o==outer.n1 then outer.n2.Unit else outer.n1.Unit
			end
		end
	end
	if not shared or not unshared then return nil end
	if math.abs(shared:Dot(unshared))>0.2 then return nil end
	-- The wedge lies between the two INSIDE WALL rays leaving the
	-- concave corner. Continue ALONG the existing perimeter edge, not
	-- backwards beyond its endpoint (which cuts the wrong solid arm).
	local intoVoid=(otherOuter-corner).Unit
	if math.abs(intoVoid:Dot(unshared))>0.12 then return nil end
	if math.abs(intoVoid:Dot(innerAxis.Unit))>0.12 then return nil end
	-- The perimeter ray must point toward the OTHER exposed wall normal.
	-- Without this test an outer edge from the opposite side of the
	-- corner could be paired and produce an unrelated CSG gouge.
	local otherInner=if shared:Dot(inner.n1)>NORMAL_DOT then inner.n2.Unit
		else inner.n1.Unit
	if intoVoid:Dot(otherInner)<0.86 then return nil end
	local remainingInner=if (corner-inner.a).Magnitude<(corner-inner.b).Magnitude
		then inner.b else inner.a
	local innerSpan=(remainingInner-corner).Magnitude
	if innerSpan<0.025 then return nil end
	-- A partial transition leaves another boxed ledge. Require enough
	-- continuous exterior edge length to trim the WHOLE additive wedge.
	if outerAxis.Magnitude<inner.width*1.08 then return nil end
	local span=inner.width*1.08
	return {corner=corner,intoVoid=intoVoid,shared=shared,
		unshared=unshared,outer=outer,inner=inner,span=span}
end

-- An EXTENSION of the existing outside bevel plane into the void introduced
-- by the inner bevel. This is a four-sided section (rather than another
-- guessed tetrahedral miter). The cutter is bounded near their shared
-- endpoint, so unrelated material cannot be changed.
function BevelJunction.clipProfile(plan):({Vector3},Vector3)
	local outer=plan.outer
	local wall=plan.shared
	local cap=plan.unshared
	local dot=wall:Dot(cap)
	local alongWall=(wall*dot-cap).Unit
	local alongCap=(cap*dot-wall).Unit
	local origin=plan.corner
	local wallPoint=origin+alongWall*outer.width
	local capPoint=origin+alongCap*outer.width
	local projected=plan.inner.width*1.15/outer.width
	local farPoint=wallPoint+(wallPoint-capPoint)*projected
	-- A very small inward overlap prevents coplanar seams with the
	-- original chamfer. The opposite boundary is far outside the solid.
	local eps=math.clamp(math.min(outer.width,plan.inner.width)*0.05,0.002,0.005)
	local height=math.max(outer.width,plan.inner.width)*3+0.05
	local profile={
		capPoint-cap*eps,
		farPoint-cap*eps,
		farPoint+cap*height,
		capPoint+cap*height,
	}
	local start=-plan.intoVoid*eps
	for i,p in ipairs(profile) do profile[i]=p+start end
	return profile,plan.intoVoid*(plan.span+eps*2)
end

-- Exposed extension of the OUTSIDE chamfer over the newly added inside
-- wedge. Its flat triangular surface bridges the old bevel to the
-- vertical inside chamfer; further adjacent planes split the triangle
-- into a proper shared corner wedge.
function BevelJunction.surfacePolygon(plan):({Vector3},Vector3)
	local outer=plan.outer
	local wall,cap=plan.shared,plan.unshared
	local dot=wall:Dot(cap)
	local onWall=(wall*dot-cap).Unit
	local onCap=(cap*dot-wall).Unit
	local corner=plan.corner
	local wallPoint=corner+onWall*outer.width
	local capPoint=corner+onCap*outer.width
	local reach=plan.span
	local beyondWall=wallPoint+(wallPoint-capPoint)*(reach/outer.width)
	local alongWall=wallPoint+plan.intoVoid*reach
	return {wallPoint,alongWall,beyondWall},(outer.n1+outer.n2).Unit
end

return BevelJunction
