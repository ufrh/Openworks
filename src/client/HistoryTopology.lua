--!strict
-- Analytic face/edge provenance for FORM's manufactured solids.
-- CSG MeshPart readback is not reliable at runtime. Reconstruct candidates
-- from Document feature history, then confirm hits against the live solid.
-- Candidate geometry remains local to the visible part; no EditableMesh.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local FORM=ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM")
local Compiler=require(FORM.Compiler)
local SurfaceTopology=require(script.Parent.SurfaceTopology)
local BevelJunction=require(FORM.BevelJunction)

local HistoryTopology={}
local EPS=0.0005
local function key(p:Vector3):string
	return string.format("%d,%d,%d",
		math.round(p.X/EPS),math.round(p.Y/EPS),math.round(p.Z/EPS))
end
local function edgeKey(a:Vector3,b:Vector3):string
	local ka,kb=key(a),key(b)
	return if ka<kb then ka.."|"..kb else kb.."|"..ka
end
local function polygonAreaXZ(p:{Vector2}):number
	local area=0
	for i,v in ipairs(p) do
		local q=p[i%#p+1]
		area+=v.X*q.Y-q.X*v.Y
	end
	return area/2
end
local function rect(x0:number,x1:number,z0:number,z1:number,y:number):{Vector3}
	return {Vector3.new(x0,y,z0),Vector3.new(x1,y,z0),
		Vector3.new(x1,y,z1),Vector3.new(x0,y,z1)}
end

function HistoryTopology.build(part:BasePart,component)
	local node=component.nodes[1]
	if not node then return nil,"No FORM source node" end
	local pose=Compiler.pose(node)
	local toPart=part.CFrame:ToObjectSpace(pose)
	local faces,edges,edgeMap={}, {}, {}
	local pendingHoles={}
	local innerVerticalVertices={}
	local completedBevels={}
	local bevelJunctions={}
	local half=node.size/2
	local topFace=nil
	local function point(p:Vector3):Vector3 return toPart:PointToWorldSpace(p) end
	local function direction(n:Vector3):Vector3
		return toPart:VectorToWorldSpace(n).Unit
	end
	local function addFace(raw:{Vector3},normal:Vector3,tag:string,curved:boolean?)
		if #raw<3 then return nil end
		local polygon={}
		for _,v in ipairs(raw) do table.insert(polygon,point(v)) end
		local face={id=#faces+1,normal=direction(normal),polygon=polygon,
			edges={},vertices=table.clone(polygon),holes=false,tag=tag,curved=curved==true}
		table.insert(faces,face)
		for i,a in ipairs(polygon) do
			local b=polygon[i%#polygon+1]
			if (a-b).Magnitude<EPS then continue end
			local k=edgeKey(a,b)
			local edge=edgeMap[k]
			if not edge then
				edge={a=a,b=b,faces={},curved=false}
				edgeMap[k]=edge
				table.insert(edges,edge)
			end
			if not table.find(edge.faces,face.id) then table.insert(edge.faces,face.id) end
			if curved then edge.curved=true end
			table.insert(face.edges,edge)
		end
		return face
	end
	local function addHole(face,raw:{Vector3})
		if not face then return end
		face.holes=true
		-- The wall edges are created later than the parent face's
		-- recess, so link the inner loop in a final topology pass.
		table.insert(pendingHoles,{face=face,loop=table.clone(raw)})
	end
	local function onPlaneFace(raw:{Vector3},normal:Vector3)
		if #raw<3 then return nil end
		local target=point(raw[1])
		local n=direction(normal)
		local result=nil
		-- Prefer the latest matching plane/patch; holes may be nested.
		for _,f in ipairs(faces) do
			if f.normal:Dot(n)>0.985 and
				math.abs((target-f.polygon[1]):Dot(f.normal))<0.005 then
				result=f
			end
		end
		return result
	end
	local function profileWalls(poly:{Vector2},bottom:number,top:number,
		outer:boolean,tag:string)
		local sign=if polygonAreaXZ(poly)>=0 then 1 else -1
		for i,p in ipairs(poly) do
			local q=poly[i%#poly+1]
			local dx,dz=q.X-p.X,q.Y-p.Y
			local length=math.sqrt(dx*dx+dz*dz)
			if length<EPS then continue end
			local n=Vector3.new(sign*dz/length,0,-sign*dx/length)
			if not outer then n=-n end
			addFace({
				Vector3.new(p.X,bottom,p.Y),
				Vector3.new(q.X,bottom,q.Y),
				Vector3.new(q.X,top,q.Y),
				Vector3.new(p.X,top,p.Y),
			},n,tag)
		end
		-- The original polygon tells us which *vertical corner* is
		-- re-entrant. For an outer contour, a concave vertex is internal;
		-- for a removed hole, a convex hole vertex is internal to the
		-- manufactured solid. Do not infer this from face normal pairs,
		-- which look identical at convex and concave right-angle corners.
		for i,p in ipairs(poly) do
			local prev=poly[(i-2)%#poly+1]
			local nextP=poly[i%#poly+1]
			local a,b=p-prev,nextP-p
			local bend=(a.X*b.Y-a.Y*b.X)*sign
			local isInner=if outer then bend < -1e-6 else bend > 1e-6
			if not isInner then continue end
			local low=point(Vector3.new(p.X,bottom,p.Y))
			local high=point(Vector3.new(p.X,top,p.Y))
			local edge=edgeMap[edgeKey(low,high)]
			if edge then edge.interior=true end
			innerVerticalVertices[key(low)]=true
			innerVerticalVertices[key(high)]=true
		end
	end
	local function profileCap(poly:{Vector2},y:number,up:boolean,tag:string)
		local ring={}
		for _,p in ipairs(poly) do table.insert(ring,Vector3.new(p.X,y,p.Y)) end
		return addFace(ring,if up then Vector3.yAxis else -Vector3.yAxis,tag)
	end
	local function boxFaces()
		local x,y,z=half.X,half.Y,half.Z
		local top=addFace(rect(-x,x,-z,z,y),Vector3.yAxis,"stock_top")
		addFace(rect(-x,x,-z,z,-y),-Vector3.yAxis,"stock_bottom")
		addFace({Vector3.new(x,-y,-z),Vector3.new(x,y,-z),
			Vector3.new(x,y,z),Vector3.new(x,-y,z)},Vector3.xAxis,"stock_side")
		addFace({Vector3.new(-x,-y,-z),Vector3.new(-x,-y,z),
			Vector3.new(-x,y,z),Vector3.new(-x,y,-z)},-Vector3.xAxis,"stock_side")
		addFace({Vector3.new(-x,-y,z),Vector3.new(x,-y,z),
			Vector3.new(x,y,z),Vector3.new(-x,y,z)},Vector3.zAxis,"stock_side")
		addFace({Vector3.new(-x,-y,-z),Vector3.new(-x,y,-z),
			Vector3.new(x,y,-z),Vector3.new(x,-y,-z)},-Vector3.zAxis,"stock_side")
		return top
	end
	local function cylinderProfile(cx:number,cz:number,radius:number)
		local out={}
		for i=0,31 do
			local t=i*math.pi/16
			table.insert(out,Vector2.new(cx+radius*math.cos(t),cz+radius*math.sin(t)))
		end
		return out
	end
	local function circleCut(center:Vector3,normal:Vector3,radius:number,
		depth:number,through:boolean,tag:string)
		local n=normal.Unit
		local tangent=if math.abs(n.Y)<0.9 then n:Cross(Vector3.yAxis).Unit
			else Vector3.xAxis
		local bitangent=n:Cross(tangent).Unit
		local bottom=center-n*(if through then node.size.Magnitude*2 else depth)
		local ringTop,ringBottom={},{}
		for i=0,31 do
			local t=i*math.pi/16
			local radial=tangent*math.cos(t)+bitangent*math.sin(t)
			table.insert(ringTop,center+radial*radius)
			table.insert(ringBottom,bottom+radial*radius)
		end
		local parent=onPlaneFace(ringTop,n)
		if parent then
			parent.holes=true
			addHole(parent,ringTop)
		end
		if not through then addFace(ringBottom,n,tag.."_floor",true) end
		for i=1,32 do
			local j=i%32+1
			local d=((ringTop[i]+ringTop[j])*0.5-center).Unit
			addFace({ringTop[i],ringTop[j],ringBottom[j],ringBottom[i]},
				-d,tag.."_wall",true)
		end
	end
	local function pocket(loop:{Vector3},normal:Vector3,depth:number,through:boolean,tag:string)
		if #loop<3 then return end
		local n=normal.Unit
		local parent=onPlaneFace(loop,n)
		if parent then addHole(parent,loop) end
		local bottom={}
		local travel=if through then node.size.Magnitude*2 else depth
		for _,p in ipairs(loop) do table.insert(bottom,p-n*travel) end
		if not through then addFace(bottom,n,tag.."_floor") end
		for i,a in ipairs(loop) do
			local j=i%#loop+1
			local b=loop[j]
			local side=(b-a):Cross(n)
			if side.Magnitude>EPS then
				addFace({a,b,bottom[j],bottom[i]},side.Unit,tag.."_wall")
			end
		end
		-- An inset/pocket wall-wall corner is also re-entrant when the
		-- chosen cavity loop is convex at that vertex. Concave vertices
		-- of the cavity are convex material corners instead.
		local signedArea=0
		for i,p in ipairs(loop) do
			local q=loop[i%#loop+1]
			signedArea+=p:Cross(q):Dot(n)
		end
		local sign=if signedArea>=0 then 1 else -1
		for i,p in ipairs(loop) do
			local previous=loop[(i-2)%#loop+1]
			local nextP=loop[i%#loop+1]
			local turn=(p-previous):Cross(nextP-p):Dot(n)*sign
			if turn<=1e-6 then continue end
			local edge=edgeMap[edgeKey(point(p),point(bottom[i]))]
			if edge then edge.interior=true end
			innerVerticalVertices[key(point(p))]=true
			innerVerticalVertices[key(point(bottom[i]))]=true
		end
	end
	local function kerfLoop(a:Vector3,b:Vector3,n:Vector3,width:number):{Vector3}?
		local d=b-a
		if d.Magnitude<EPS then return nil end
		local side=n:Cross(d.Unit)*(width/2)
		local extension=d.Unit*(width/2)
		return {a-extension-side,b+extension-side,b+extension+side,a-extension+side}
	end

	if node.kind=="Block" then
		topFace=boxFaces()
	elseif node.kind=="Cylinder" then
		local poly=cylinderProfile(0,0,node.size.X/2)
		topFace=profileCap(poly,half.Y,true,"cylinder_top")
		profileCap(poly,-half.Y,false,"cylinder_bottom")
		profileWalls(poly,-half.Y,half.Y,true,"cylinder_wall")
		for _,e in ipairs(edges) do e.curved=true end
	else
		return nil,"Unsupported primitive type"
	end
	for _,op in ipairs(component.operations or {}) do
		if op.enabled==false then continue end
		local kind=op.kind
		if kind=="SketchExtrude" then
			local poly={}
			for _,p in ipairs(op.points) do
				table.insert(poly,Vector2.new(p.X-half.X,p.Y-half.Z))
			end
			if op.mode=="Intersect" then
				-- Source material is replaced by its clipped, sketched
				-- cross section. The original stock faces are not candidates.
				table.clear(faces)
				table.clear(edges)
				table.clear(edgeMap)
				table.clear(pendingHoles)
				table.clear(innerVerticalVertices)
				topFace=profileCap(poly,half.Y,true,"profile_top")
				profileCap(poly,-half.Y,false,"profile_bottom")
				profileWalls(poly,-half.Y,half.Y,true,"profile_side")
			elseif op.mode=="Add" then
				local raised=half.Y+op.depth
				local loop={}
				for _,p in ipairs(poly) do table.insert(loop,Vector3.new(p.X,half.Y,p.Y)) end
				addHole(topFace,loop)
				profileCap(poly,raised,true,"extruded_top")
				profileWalls(poly,half.Y,raised,true,"extruded_side")
			elseif op.mode=="Remove" then
				local low=if op.through then -half.Y else half.Y-op.depth
				local loop={}
				for _,p in ipairs(poly) do table.insert(loop,Vector3.new(p.X,half.Y,p.Y)) end
				addHole(topFace,loop)
				if not op.through then profileCap(poly,low,true,"profile_cut_floor") end
				profileWalls(poly,low,half.Y,false,"profile_cut_wall")
			end
		elseif kind=="Drill" then
			circleCut(Vector3.new(op.x-half.X,half.Y,op.z-half.Z),
				Vector3.yAxis,op.diameter/2,op.depth or node.size.Y,
				op.through~=false,"drill")
		elseif kind=="DrillFace" then
			circleCut(op.origin,op.normal,op.diameter/2,op.depth,
				op.through~=false,"drill")
		elseif kind=="Inset" then
			local m=op.margin
			pocket(rect(-half.X+m,half.X-m,-half.Z+m,half.Z-m,half.Y),
				Vector3.yAxis,op.depth,false,"inset")
		elseif kind=="InsetFace" then
			pocket(op.points,op.normal,op.depth,false,"inset")
		elseif kind=="Groove" or kind=="Saw" then
			local a=Vector3.new(op.x1-half.X,half.Y,op.z1-half.Z)
			local b=Vector3.new(op.x2-half.X,half.Y,op.z2-half.Z)
			local loop=kerfLoop(a,b,Vector3.yAxis,op.kerf)
			if loop then pocket(loop,Vector3.yAxis,op.depth or node.size.Y,
				kind=="Saw" or op.through==true,"groove") end
		elseif kind=="GrooveFace" then
			local loop=kerfLoop(op.a,op.b,op.normal,op.width)
			if loop then pocket(loop,op.normal,op.depth,op.through==true,"groove") end
		elseif kind=="File" or kind=="FileMesh" then
			local spec=BevelJunction.spec(node,op)
			if spec then table.insert(completedBevels,spec) end
		end
	end
	-- Link pocket/bore lip edges to their actual containing planar face.
	-- Without this step, the first cut's rim has only one adjacent face,
	-- so a valid manufactured sharp edge could not be filed.
	for _,entry in ipairs(pendingHoles) do
		local face=entry.face
		for i,v in ipairs(entry.loop) do
			local a,b=point(v),point(entry.loop[i%#entry.loop+1])
			local edge=edgeMap[edgeKey(a,b)]
			if edge then
				if not table.find(edge.faces,face.id) then
					table.insert(edge.faces,face.id)
				end
				if not table.find(face.edges,edge) then
					table.insert(face.edges,edge)
				end
			end
		end
	end
	-- Reconcile the SAME FILE junctions used by the CSG compiler, then
	-- rebuild the actual bevel boundary graph. A new additive inside wedge
	-- must shorten where an existing outside bevel plane cuts across it.
	-- Source sharp edges are retired; trim lines and joined-corner edges
	-- replace them in the next hover/click selection pass.
	for i,spec in ipairs(completedBevels) do
		for j=1,i-1 do
			local plan=BevelJunction.plan(completedBevels[j],spec)
			if plan then table.insert(bevelJunctions,plan) end
		end
	end

	local function clipContour(poly:{Vector3},planePoint:Vector3,planeNormal:Vector3):{Vector3}
		local result={}
		for i,a in ipairs(poly) do
			local b=poly[i%#poly+1]
			local da=(a-planePoint):Dot(planeNormal)-0.002
			local db=(b-planePoint):Dot(planeNormal)-0.002
			local insideA,insideB=da<=0,db<=0
			if insideA then table.insert(result,a) end
			if insideA~=insideB then
				local t=math.clamp(da/(da-db),0,1)
				table.insert(result,a+(b-a)*t)
			end
		end
		-- Avoid zero-length edges at exactly coplanar intersections.
		local clean={}
		for _,v in ipairs(result) do
			if #clean==0 or (clean[#clean]-v).Magnitude>EPS then
				table.insert(clean,v)
			end
		end
		if #clean>=2 and (clean[1]-clean[#clean]).Magnitude<EPS then
			table.remove(clean)
		end
		return clean
	end

	local faceByFile={}
	local function addAdjacent(edge,face)
		if not edge or not face or table.find(edge.faces,face.id) then return end
		table.insert(edge.faces,face.id)
		if not table.find(face.edges,edge) then table.insert(face.edges,edge) end
	end

	for _,spec in ipairs(completedBevels) do
		local a,b,n1,n2,w=spec.a,spec.b,spec.n1,spec.n2,spec.width
		local old=edgeMap[edgeKey(point(a),point(b))]
		if old then old.retired=true end
		local normalSum=n1+n2
		local dot=n1:Dot(n2)
		if normalSum.Magnitude<0.01 or math.abs(dot)>0.84 then continue end
		local d1=(n1*dot-n2).Unit
		local d2=(n2*dot-n1).Unit
		local sign=if spec.interior then -1 else 1
		local contour={
			a+d1*w*sign,b+d1*w*sign,
			b+d2*w*sign,a+d2*w*sign,
		}
		if spec.interior then
			for _,junction in ipairs(bevelJunctions) do
				if junction.inner~=spec then continue end
				local o=junction.outer
				local nd=o.n1:Dot(o.n2)
				local tangent=(o.n1*nd-o.n2).Unit
				local bevelPlanePoint=o.a+tangent*o.width
				local bevelPlaneNormal=(o.n1+o.n2).Unit
				contour=clipContour(contour,bevelPlanePoint,bevelPlaneNormal)
				if #contour<3 then break end
			end
		end
		if #contour<3 then continue end
		local face=addFace(contour,normalSum.Unit,"file_chamfer")
		if not face then continue end
		faceByFile[spec]=face
		-- The chamfer's two long boundary lines lie on the original
		-- adjacent faces. Attach them there; never leave them as one-face
		-- decoration while the obsolete sharp edge remains selectable.
		for _,edge in ipairs(face.edges) do
			for _,rawNormal in ipairs({n1,n2}) do
				local wanted=direction(rawNormal)
				local origin=point(a)
				if math.abs((edge.a-origin):Dot(wanted))>0.008
					or math.abs((edge.b-origin):Dot(wanted))>0.008 then
					continue
				end
				local found=nil
				if old then
					for _,fid in ipairs(old.faces) do
						local f=faces[fid]
						if f and f~=face and f.normal:Dot(wanted)>0.97 then
							found=f break
						end
					end
				end
				if not found then
					for _,f in ipairs(faces) do
						if f~=face and f.normal:Dot(wanted)>0.97 and
							math.abs((edge.a-f.polygon[1]):Dot(f.normal))<0.008 then
							found=f
						end
					end
				end
				addAdjacent(edge,found)
			end
		end
	end

	-- When the interior bevel is capped by an exterior bevel plane, the
	-- resulting V-shaped trim edge is adjacent to BOTH new bevel surfaces.
	-- Generate its selection adjacency from those actual shared planes.
	for _,junction in ipairs(bevelJunctions) do
		local innerFace=faceByFile[junction.inner]
		local outerFace=faceByFile[junction.outer]
		if not innerFace or not outerFace then continue end
		local outside=junction.outer
		local dot=outside.n1:Dot(outside.n2)
		local surfacePoint=point(outside.a+(outside.n1*dot-outside.n2).Unit*outside.width)
		local surfaceNormal=direction((outside.n1+outside.n2).Unit)
		for _,edge in ipairs(innerFace.edges) do
			if math.abs((edge.a-surfacePoint):Dot(surfaceNormal))<0.013
				and math.abs((edge.b-surfacePoint):Dot(surfaceNormal))<0.013 then
				addAdjacent(edge,outerFace)
			end
		end
	end

	-- Flat perimeter bevels taper at the endpoints of *concave*
	-- vertical corners. Without this the cutter retains a full-width
	-- rectangular endcap, creating the boxed triangle at the notch top
	-- and bottom shown in Studio.
	local vertical=direction(Vector3.yAxis)
	for _,edge in ipairs(edges) do
		local directionAlong=edge.b-edge.a
		if directionAlong.Magnitude>EPS
			and math.abs(directionAlong.Unit:Dot(vertical))<0.2 then
			edge.taperA=innerVerticalVertices[key(edge.a)]==true
			edge.taperB=innerVerticalVertices[key(edge.b)]==true
		end
	end
	-- Edges that have been replaced by chamfers are not selectable
	-- again. Keep the new bevel trim lines (shared with real neighboring
	-- faces) and expose the same joined-corner set used by Fabricator.
	local activeEdges={}
	for _,edge in ipairs(edges) do
		if not edge.retired then table.insert(activeEdges,edge) end
	end
	for _,face in ipairs(faces) do
		face.vertices=table.clone(face.polygon)
	end
	return setmetatable({faces=faces,edges=activeEdges,part=part,
		junctions=bevelJunctions,
		vertices={},triangles={},history=true,componentId=component.id},
		{__index=SurfaceTopology}),nil
end
return HistoryTopology
