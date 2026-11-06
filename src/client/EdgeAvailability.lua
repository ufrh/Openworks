--!strict
-- File ONLY the exposed straight portion of an authored edge. An Add
-- extrusion's footprint can obstruct a long stock edge even when the
-- original edge continues behind it. Split by the actual cutter clearance.
local EdgeAvailability={}
local EPS=1e-5
local function polygonClip(poly:{Vector2},normal:Vector2,limit:number):{Vector2}
	local result={}
	if #poly==0 then return result end
	for i,a in ipairs(poly) do
		local b=poly[i%#poly+1]
		local da=a:Dot(normal)-limit
		local db=b:Dot(normal)-limit
		if da<=EPS then table.insert(result,a) end
		if (da<=EPS)~=(db<=EPS) and math.abs(da-db)>1e-8 then
			table.insert(result,a+(b-a)*math.clamp(da/(da-db),0,1))
		end
	end
	return result
end

-- a,b and stored op points are all in source NODE local coordinates.
-- Return only intervals that can fit the selected File width without
-- intersecting raised material. No CSG readback or arbitrary mesh bounds.
function EdgeAvailability.segments(a:Vector3,b:Vector3,component,width:number)
	local delta=b-a
	local length=delta.Magnitude
	if length<0.035 or width<=0 then return {} end
	local node=component.nodes[1]
	if not node or math.abs(a.Y-node.size.Y*0.5)>0.004
		or math.abs(b.Y-node.size.Y*0.5)>0.004
		or math.abs(delta.Y)>0.004 then
		return {{a=a,b=b}}
	end
	local dir=Vector2.new(delta.X,delta.Z)
	if dir.Magnitude<1e-5 then return {{a=a,b=b}} end
	dir=dir.Unit
	local perpendicular=Vector2.new(-dir.Y,dir.X)
	local start=Vector2.new(a.X,a.Z)
	local blocked={}
	for _,op in ipairs(component.operations or {}) do
		if op.enabled==false or op.kind~="SketchExtrude"
			or op.mode~="Add" then continue end
		local polygon={}
		for _,v in ipairs(op.points) do
			table.insert(polygon,Vector2.new(
				v.X-node.size.X*0.5,v.Y-node.size.Z*0.5)-start)
		end
		-- The band has the same width as the requested cutter. A raised
		-- footprint farther away than the chip width cannot obstruct it.
		local clearance=width+0.006
		local band=polygonClip(polygon,perpendicular,clearance)
		band=polygonClip(band,-perpendicular,clearance)
		if #band<3 then continue end
		local lo,hi=math.huge,-math.huge
		for _,v in ipairs(band) do
			local t=v:Dot(dir)
			lo=math.min(lo,t)
			hi=math.max(hi,t)
		end
		-- Stop before contacting the raised wall; do not overcut it.
		lo=math.max(0,lo-0.006)
		hi=math.min(length,hi+0.006)
		if hi>lo+EPS then table.insert(blocked,{lo,hi}) end
	end
	if #blocked==0 then return {{a=a,b=b}} end
	table.sort(blocked,function(x,y) return x[1]<y[1] end)
	local clear={}
	local cursor=0
	for _,span in ipairs(blocked) do
		if span[1]-cursor>=0.035 then
			table.insert(clear,{a=a+delta*(cursor/length),
				b=a+delta*(span[1]/length)})
		end
		cursor=math.max(cursor,span[2])
	end
	if length-cursor>=0.035 then
		table.insert(clear,{a=a+delta*(cursor/length),b=b})
	end
	return clear
end

return EdgeAvailability
