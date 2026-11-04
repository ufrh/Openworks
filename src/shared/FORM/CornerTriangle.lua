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
			n1=Vector3.yAxis,n2=Vector3.zAxis,width=op.width,segments=op.segments or 1} then
		return {a=Vector3.new(-hx,hy,-hz),b=Vector3.new(hx,hy,-hz),
			n1=Vector3.yAxis,n2=-Vector3.zAxis,width=op.width,segments=op.segments or 1}
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

local function face(points,exposed)
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
	return {polygon=unique,exposed=exposed}
end

local function orientClosedShell(faces)
	local incidence={}
	local function vertexKey(p:Vector3)
		return string.format("%d:%d:%d",math.round(p.X*1e5),
			math.round(p.Y*1e5),math.round(p.Z*1e5))
	end
	for index,surface in ipairs(faces) do
		local polygon=surface.polygon
		for i,a in ipairs(polygon) do
			local b=polygon[i%#polygon+1]
			local ak,bk=vertexKey(a),vertexKey(b)
			if ak==bk then return nil,"Degenerate miter edge" end
			local key=if ak<bk then ak.."|"..bk else bk.."|"..ak
			local edge=incidence[key]
			if not edge then edge={} incidence[key]=edge end
			table.insert(edge,{index=index,direction=if ak<bk then 1 else -1})
		end
	end
	local neighbors={}
	for i=1,#faces do neighbors[i]={} end
	for _,incident in pairs(incidence) do
		if #incident~=2 then return nil,"Miter shell is not watertight" end
		local a,b=incident[1],incident[2]
		table.insert(neighbors[a.index],{other=b.index,sign=-a.direction*b.direction})
		table.insert(neighbors[b.index],{other=a.index,sign=-a.direction*b.direction})
	end
	local orientation={[1]=1}
	local queue={1}
	local head=1
	while head<=#queue do
		local i=queue[head]
		head+=1
		for _,neighbor in ipairs(neighbors[i]) do
			local expected=orientation[i]*neighbor.sign
			if orientation[neighbor.other] then
				if orientation[neighbor.other]~=expected then
					return nil,"Miter faces have conflicting winding"
				end
			else
				orientation[neighbor.other]=expected
				table.insert(queue,neighbor.other)
			end
		end
	end
	if #queue~=#faces then return nil,"Miter has disconnected surfaces" end
	local volume6=0
	for i,surface in ipairs(faces) do
		local points=surface.polygon
		if orientation[i]<0 then
			local reversed={}
			for j=#points,1,-1 do table.insert(reversed,points[j]) end
			points=reversed
			surface.polygon=points
		end
		for j=2,#points-1 do
			volume6+=points[1]:Dot(points[j]:Cross(points[j+1]))
		end
	end
	if math.abs(volume6)<1e-8 then return nil,"Miter has no volume" end
	if volume6<0 then
		for _,surface in ipairs(faces) do
			local reversed={}
			for i=#surface.polygon,1,-1 do
				table.insert(reversed,surface.polygon[i])
			end
			surface.polygon=reversed
		end
	end
	for _,surface in ipairs(faces) do
		local points=surface.polygon
		local normal=nil
		for j=2,#points-1 do
			local cross=(points[j]-points[1]):Cross(points[j+1]-points[1])
			if cross.Magnitude>1e-8 then normal=cross.Unit break end
		end
		if not normal then return nil,"Miter contains a collapsed face" end
		surface.normal=normal
	end
	return faces,nil
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
	local result={}
	local function add(points,exposed)
		local polygon=face(points,exposed)
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
	return orientClosedShell(result)
end

return CornerTriangle
