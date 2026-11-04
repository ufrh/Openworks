--!strict
-- FORM bevel junction geometry. All inside-corner bevel additions are
-- CLIPPED BEFORE UNION against neighboring exterior chamfer planes.
-- This is a pure geometry module: Fabricator and HistoryTopology consume
-- identical convex face polygons. No post-hoc CSG cleanup operations.
local BevelJunction = {}
local EPS = 1e-6

function BevelJunction.spec(node,op)
	if op.enabled==false then return nil end
	if op.kind=="FileMesh" then
		return {a=op.a,b=op.b,n1=op.normalA.Unit,n2=op.normalB.Unit,
			width=op.width,interior=op.interior==true,segments=op.segments or 1,id=op.id}
	end
	if op.kind~="File" or node.kind~="Block" then return nil end
	local hx,hy,hz=node.size.X/2,node.size.Y/2,node.size.Z/2
	local a,b,n2
	if op.edge=="X+" then
		a,b=Vector3.new(hx,hy,-hz),Vector3.new(hx,hy,hz)
		n2=Vector3.xAxis
	elseif op.edge=="X-" then
		a,b=Vector3.new(-hx,hy,-hz),Vector3.new(-hx,hy,hz)
		n2=-Vector3.xAxis
	elseif op.edge=="Z+" then
		a,b=Vector3.new(-hx,hy,hz),Vector3.new(hx,hy,hz)
		n2=Vector3.zAxis
	elseif op.edge=="Z-" then
		a,b=Vector3.new(-hx,hy,-hz),Vector3.new(hx,hy,-hz)
		n2=-Vector3.zAxis
	else return nil end
	return {a=a,b=b,n1=Vector3.yAxis,n2=n2,
		width=op.width,interior=false,segments=op.segments or 1,id=op.id}
end

local function unit(v:Vector3):Vector3? 
	if v.Magnitude<1e-7 then return nil end
	return v.Unit
end

-- Intersect only when the outer File terminates at an endpoint of the
-- concave File and extends along the OTHER wall into the inside notch.
-- Never guess from proximity alone: both the shared normal and the
-- axial/end-cap direction have to agree.
function BevelJunction.pair(inner,outer)
	if not inner or not outer or not inner.interior or outer.interior then return nil end
	if inner.width<0.018 or outer.width<0.018 then return nil end
	local axis=unit(inner.b-inner.a)
	local outerAxis=unit(outer.b-outer.a)
	if not axis or not outerAxis or math.abs(axis:Dot(outerAxis))>0.10 then return nil end
	for _,candidate in ipairs({
		{corner=inner.a,opposite=inner.b},
		{corner=inner.b,opposite=inner.a},
	}) do
		local corner=candidate.corner
		local awayFromInner=unit(corner-candidate.opposite)
		if not awayFromInner then continue end
		for _,otherOuter in ipairs({outer.a,outer.b}) do
			local otherEnd=if (otherOuter-outer.a).Magnitude<0.001 then outer.b else outer.a
			if (otherEnd-corner).Magnitude>0.006 then continue end
			-- otherOuter is the nonmatching endpoint of the exterior edge.
			local outwardAlong=unit(otherOuter-corner)
			if not outwardAlong then continue end
			for _,shared in ipairs({inner.n1,inner.n2}) do
				local otherInner=if shared==inner.n1 then inner.n2 else inner.n1
				local matchNormal
				for _,outerNormal in ipairs({outer.n1,outer.n2}) do
					if shared:Dot(outerNormal)>0.985 then
						matchNormal=outerNormal
					end
				end
				if not matchNormal then continue end
				local cap=if matchNormal==outer.n1 then outer.n2 else outer.n1
				-- At the top cap points upward; at the bottom downward.
				if cap:Dot(awayFromInner)<0.96 then continue end
				if outwardAlong:Dot(otherInner)<0.96 then continue end
				if math.abs(cap:Dot(shared))>0.13 then continue end
				if (otherOuter-corner).Magnitude<inner.width*1.15 then continue end
				return {inner=inner,outer=outer,corner=corner,
					normal=(shared+cap).Unit,
					planePoint=corner-shared*outer.width}
			end
		end
	end
	return nil
end

function BevelJunction.planesFor(inner,specs)
	local planes={}
	if not inner or not inner.interior then return planes end
	for _,spec in ipairs(specs) do
		local pair=BevelJunction.pair(inner,spec)
		if pair then
			table.insert(planes,pair)
		end
	end
	return planes
end

-- Convex triangular prism, with all polygon faces oriented outward.
function BevelJunction.prismFaces(profile:{Vector3},travel:Vector3)
	if #profile~=3 or travel.Magnitude<0.01 then
		error("A file bevel requires a nondegenerate triangular prism")
	end
	local a,b,c=profile[1],profile[2],profile[3]
	local faces={
		{a,c,b},
		{a+travel,b+travel,c+travel},
		{a,b,b+travel,a+travel},
		{b,c,c+travel,b+travel},
		{c,a,a+travel,c+travel},
	}
	return faces
end

local function polygonNormal(poly:{Vector3}):Vector3?
	if #poly<3 then return nil end
	for i=2,#poly-1 do
		local cross=(poly[i]-poly[1]):Cross(poly[i+1]-poly[1])
		if cross.Magnitude>1e-8 then return cross.Unit end
	end
	return nil
end

local function dedupe(poly:{Vector3}):{Vector3}
	local clean={}
	for _,p in ipairs(poly) do
		if #clean==0 or (p-clean[#clean]).Magnitude>EPS then
			table.insert(clean,p)
		end
	end
	if #clean>1 and (clean[1]-clean[#clean]).Magnitude<EPS then table.remove(clean) end
	return clean
end

local function clipPolygon(poly:{Vector3},n:Vector3,p0:Vector3,intersections)
	local result={}
	for i,a in ipairs(poly) do
		local b=poly[i%#poly+1]
		local da=(a-p0):Dot(n)
		local db=(b-p0):Dot(n)
		local insideA,insideB=da<=EPS,db<=EPS
		if insideA then table.insert(result,a) end
		if insideA~=insideB then
			local denom=da-db
			if math.abs(denom)>EPS then
				local p=a+(b-a)*math.clamp(da/denom,0,1)
				table.insert(result,p)
				local exists=false
				for _,q in ipairs(intersections) do
					if (q-p).Magnitude<1e-5 then exists=true break end
				end
				if not exists then table.insert(intersections,p) end
			end
		end
	end
	return dedupe(result)
end

local function orderedCap(intersections:{Vector3},normal:Vector3)
	if #intersections<3 then return nil end
	local center=Vector3.zero
	for _,p in ipairs(intersections) do center+=p end
	center/= #intersections
	local axis=if math.abs(normal.Y)<0.90 then Vector3.yAxis else Vector3.xAxis
	local tangent=normal:Cross(axis).Unit
	local bitangent=normal:Cross(tangent).Unit
	table.sort(intersections,function(a,b)
		local da,db=a-center,b-center
		local aa=math.atan2(da:Dot(bitangent),da:Dot(tangent))
		local bb=math.atan2(db:Dot(bitangent),db:Dot(tangent))
		return aa<bb
	end)
	return intersections
end

function BevelJunction.clipFaces(baseFaces,planes)
	local faces={}
	for _,face in ipairs(baseFaces) do
		table.insert(faces,table.clone(face))
	end
	for _,plane in ipairs(planes) do
		local clipped,intersections={},{}
		for _,poly in ipairs(faces) do
			local nextPoly=clipPolygon(poly,plane.normal,plane.planePoint,intersections)
			if #nextPoly>=3 and polygonNormal(nextPoly) then
				table.insert(clipped,nextPoly)
			end
		end
		local cap=orderedCap(intersections,plane.normal)
		if cap then table.insert(clipped,cap) end
		faces=clipped
		if #faces<4 then return nil,"Bevel wedge completely clipped by adjoining chamfers" end
	end
	local centroid=Vector3.zero
	local count=0
	for _,face in ipairs(faces) do
		for _,p in ipairs(face) do
			centroid+=p
			count+=1
		end
	end
	if count<12 then return nil,"Bevel volume collapsed" end
	centroid/=count
	local output={}
	for _,poly in ipairs(faces) do
		local normal=polygonNormal(poly)
		if normal then
			local mid=Vector3.zero
			for _,p in ipairs(poly) do mid+=p end
			mid/=#poly
			if normal:Dot(mid-centroid)<0 then
				local reversed={}
				for i=#poly,1,-1 do table.insert(reversed,poly[i]) end
				poly=reversed
				normal=-normal
			end
			table.insert(output,{polygon=poly,normal=normal})
		end
	end
	-- Fail closed: a clipping operation must produce a watertight
	-- convex solid. Never send a torn or inverted mesh into Roblox CSG,
	-- where it can turn into the giant wedges seen in earlier tests.
	local counts={}
	local volume6=0
	local function positionKey(p:Vector3):string
		return string.format("%d,%d,%d",math.round(p.X*100000),
			math.round(p.Y*100000),math.round(p.Z*100000))
	end
	for _,surface in ipairs(output) do
		local poly=surface.polygon
		if #poly<3 then return nil,"Clipping produced an open bevel polygon" end
		for index,p in ipairs(poly) do
			local q=poly[index%#poly+1]
			if (q-p).Magnitude<1e-5 then
				return nil,"Clipping produced a zero-length bevel edge"
			end
			local ka,kb=positionKey(p),positionKey(q)
			local key=if ka<kb then ka.."|"..kb else kb.."|"..ka
			counts[key]=(counts[key] or 0)+1
		end
		for i=2,#poly-1 do
			volume6+=poly[1]:Dot(poly[i]:Cross(poly[i+1]))
		end
	end
	for _,count in pairs(counts) do
		if count~=2 then
			return nil,"Clipped bevel is nonmanifold; refusing CSG"
		end
	end
	if math.abs(volume6)<1e-7 then
		return nil,"Clipped bevel has no usable solid volume"
	end
	return output,nil
end

return BevelJunction
