--!strict
-- CAD-like face utility for the current compiled mesh. Inset is initially
-- limited to one simple, convex perimeter loop without internal holes.
-- Do NOT flatten holes or silently use the old source stock rectangle.
local FaceTools={}
local EPS=0.0002
local function key(p:Vector3):string
	return string.format("%d:%d:%d",math.round(p.X/EPS),
		math.round(p.Y/EPS),math.round(p.Z/EPS))
end

function FaceTools.boundary(face): ({Vector3}?,string?)
	-- HistoryTopology owns the logical polygon of each manufactured face.
	-- Do NOT rebuild it from face.edges: cutout lips and neighboring faces
	-- share those edges, and treating all of them as a single ring can jump
	-- between disconnected loops or accidentally use the stock perimeter.
	if face.polygon then
		if #face.polygon < 3 or #face.polygon > 128 then
			return nil, "Face boundary is too complex"
		end
		local points={}
		for i,p in ipairs(face.polygon) do
			if typeof(p) ~= "Vector3" then return nil,"Invalid surface vertex" end
			local prev=face.polygon[(i-2)%#face.polygon+1]
			local nextP=face.polygon[i%#face.polygon+1]
			local u,v=p-prev,nextP-p
			if u.Magnitude>EPS and v.Magnitude>EPS
				and u.Unit:Dot(v.Unit)<0.9995 then
				table.insert(points,p)
			end
		end
		if #points<3 then return nil,"Degenerate planar boundary" end
		return points,nil
	end
	-- Compatibility with native/mesh-triangle selections.
	local links,locations,count={},{},0
	for _,edge in ipairs(face.edges) do
		local a,b=key(edge.a),key(edge.b)
		locations[a],locations[b]=edge.a,edge.b
		if not links[a] then links[a]={} end
		if not links[b] then links[b]={} end
		table.insert(links[a],b)
		table.insert(links[b],a)
		count+=1
	end
	if count<3 or count>128 then return nil,"Face boundary is too complex" end
	local first=next(links)
	if not first then return nil,"Face has no exposed boundary" end
	for _,neighbors in pairs(links) do
		if #neighbors~=2 then return nil,"Face has multiple or branched boundary loops" end
	end
	local points,previous,current,seen={},nil,first,{}
	repeat
		if seen[current] then return nil,"Face boundary loops intersect" end
		seen[current]=true
		table.insert(points,locations[current])
		local neighbors=links[current]
		local following=if neighbors[1]==previous then neighbors[2] else neighbors[1]
		previous,current=current,following
	until current==first or #points>count
	if current~=first or #points~=count then
		return nil,"Inset requires a single closed face boundary"
	end
	local simplified={}
	for i,p in ipairs(points) do
		local prev=points[(i-2)%#points+1]
		local nextP=points[i%#points+1]
		local u,v=p-prev,nextP-p
		if u.Magnitude>EPS and v.Magnitude>EPS and
			u.Unit:Dot(v.Unit)<0.9995 then table.insert(simplified,p) end
	end
	if #simplified<3 then return nil,"Degenerate face loop" end
	return simplified,nil
end

function FaceTools.inset(face,margin:number):({Vector3}?,string?)
	if face.holes then
		return nil,"Inset on faces with holes or raised features needs multiple contour loops"
	end
	if face.curved then return nil,"Inset needs a planar face" end
	local loop,why=FaceTools.boundary(face)
	if not loop then return nil,why end
	local normal=face.normal.Unit
	local signed=0
	for i,p in ipairs(loop) do
		local q=loop[i%#loop+1]
		signed+=(p:Cross(q)):Dot(normal)
	end
	if math.abs(signed)<1e-7 then return nil,"Degenerate planar face" end
	if signed<0 then
		local reversed={}
		for i=#loop,1,-1 do table.insert(reversed,loop[i]) end
		loop=reversed
	end
	-- Offset every actual polygon edge, including concave profile corners.
	-- Reject an offset if it self-crosses or leaves the original region.
	-- Concave shapes that split into multiple islands need a polygon clipping
	-- kernel; they are not converted into a misleading rectangular pocket.
	local result={}
	for i,p in ipairs(loop) do
		local previous=loop[(i-2)%#loop+1]
		local nextP=loop[i%#loop+1]
		local prevDir=(p-previous).Unit
		local nextDir=(nextP-p).Unit
		local inwardPrev=normal:Cross(prevDir)
		local inwardNext=normal:Cross(nextDir)
		local a=p+inwardPrev*margin
		local b=p+inwardNext*margin
		local determinant=prevDir:Cross(nextDir):Dot(normal)
		if math.abs(determinant)<0.0001 then return nil,"Inset has an ambiguous corner" end
		local t=(b-a):Cross(nextDir):Dot(normal)/determinant
		local point=a+prevDir*t
		if (point-p).Magnitude>margin*12 then return nil,"Inset border produces an oversized miter" end
		table.insert(result,point)
	end
	-- Reject inverted, self-crossing or outside offsets explicitly.
	local function orient(a:Vector2,b:Vector2,c:Vector2):number
		return (b.X-a.X)*(c.Y-a.Y)-(b.Y-a.Y)*(c.X-a.X)
	end
	local function project(v:Vector3):Vector2
		local a,b,c=math.abs(normal.X),math.abs(normal.Y),math.abs(normal.Z)
		if b>=a and b>=c then return Vector2.new(v.X,v.Z) end
		if a>=c then return Vector2.new(v.Z,v.Y) end
		return Vector2.new(v.X,v.Y)
	end
	local source2,inner2={},{}
	for _,p in ipairs(loop) do table.insert(source2,project(p)) end
	for _,p in ipairs(result) do table.insert(inner2,project(p)) end
	local function inPolygon(p:Vector2,ring:{Vector2}):boolean
		local inside=false
		for i,a in ipairs(ring) do
			local b=ring[i%#ring+1]
			local d=b-a
			if d.Magnitude>1e-8 then
				local t=math.clamp((p-a):Dot(d)/d:Dot(d),0,1)
				if (a+d*t-p).Magnitude<0.0002 then return true end
			end
			if (a.Y>p.Y)~=(b.Y>p.Y) then
				local x=a.X+(p.Y-a.Y)*(b.X-a.X)/(b.Y-a.Y)
				if p.X<x then inside=not inside end
			end
		end
		return inside
	end
	for _,p in ipairs(inner2) do
		if not inPolygon(p,source2) then
			return nil,"Inset border exceeds this face's available geometry"
		end
	end
	local signedArea=0
	for i,p in ipairs(result) do
		local q=result[i%#result+1]
		signedArea+=(p:Cross(q)):Dot(normal)
	end
	if signedArea<1e-7 then return nil,"Inset collapses or inverts face area" end
	for i=1,#inner2 do
		local a,b=inner2[i],inner2[i%#inner2+1]
		for j=i+1,#inner2 do
			if j==i+1 or (i==1 and j==#inner2) then continue end
			local c,d=inner2[j],inner2[j%#inner2+1]
			local o1,o2=orient(a,b,c),orient(a,b,d)
			local o3,o4=orient(c,d,a),orient(c,d,b)
			if o1*o2 < -1e-10 and o3*o4 < -1e-10 then
				return nil,"Inset would create crossing edges on this face"
			end
		end
	end

	return result,nil
end

return FaceTools
