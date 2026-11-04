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
		return {a=op.a,b=op.b,n1=op.normalA.Unit,n2=op.normalB.Unit,width=op.width,segments=op.segments or 1}
	end
	if op.kind~="File" or op.enabled==false or node.kind~="Block" then return nil end
	local hx,hy,hz=node.size.X/2,node.size.Y/2,node.size.Z/2
	if op.edge=="X+" then
		return {a=Vector3.new(hx,hy,-hz),b=Vector3.new(hx,hy,hz),
			n1=Vector3.yAxis,n2=Vector3.xAxis,width=op.width,segments=op.segments or 1}
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

local function face(points,centroid,exposed)
	local unique={}
	for _,p in ipairs(points) do
		if #unique==0 or (unique[#unique]-p).Magnitude>1e-6 then
			table.insert(unique,p)
		end
	end
	if #unique>1 and (unique[1]-unique[#unique]).Magnitude<1e-6 then
		table.remove(unique)
	end
	if #unique<3 then return nil end
	local normal=nil
	for i=2,#unique-1 do
		local cross=(unique[i]-unique[1]):Cross(unique[i+1]-unique[1])
		if cross.Magnitude>1e-8 then normal=cross.Unit break end
	end
	if not normal then return nil end
	local middle=Vector3.zero
	for _,p in ipairs(unique) do middle+=p end
	middle/=#unique
	if normal:Dot(middle-centroid)<0 then
		local reversed={}
		for i=#unique,1,-1 do table.insert(reversed,unique[i]) end
		unique=reversed
		normal=-normal
	end
	return {polygon=unique,normal=normal,exposed=exposed}
end

function CornerTriangle.faces(junction)
	local p=junction.corner
	local cap= junction.cap
	local wallA,wallB=junction.wallA,junction.wallB
	local radius=junction.width
	local count=junction.segments
	local a,b,seam={}, {}, {}
	for i=0,count do
		local theta=i/count*math.pi*0.5
		local inset=radius*(1-math.sin(theta))
		local vertical=radius*(1-math.cos(theta))
		local top=p-cap*vertical
		table.insert(a,top-wallA*inset)
		table.insert(b,top-wallB*inset)
		table.insert(seam,top-(wallA+wallB)*inset)
	end
	local centroid=p-(cap+wallA+wallB)*(radius*0.3)
	local result={}
	local function add(points,exposed)
		local polygon=face(points,centroid,exposed)
		if polygon then table.insert(result,polygon) end
	end
	-- One top cap and two original wall-plane closures.
	add({p,a[1],seam[1],b[1]},false)
	local sideA={p}
	local sideB={p}
	for i=1,#a do table.insert(sideA,a[i]) table.insert(sideB,b[i]) end
	add(sideA,false)
	add(sideB,false)
	-- Two families of sloped strips; they share the diagonal miter seam.
	-- With 1 segment these are exactly TWO planar triangular slopes.
	-- With N segments they become 2*N tangent-approximating strips.
	for i=1,count do
		add({a[i],seam[i],seam[i+1],a[i+1]},true)
		add({b[i],b[i+1],seam[i+1],seam[i]},true)
	end
	if #result<5 then return nil,"Miter solid collapsed" end
	return result
end

return CornerTriangle
