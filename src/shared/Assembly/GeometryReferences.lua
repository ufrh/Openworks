--!strict
local Features = require(script.Parent.Parent.FORM.Features)
local Profile = require(script.Parent.Parent.FORM.SketchBodyProfile)
local References = {}
function References.list(component:any):{any}
	local node = component.nodes[1]
	local out = {}
	for _, f in ipairs(Features.list(component)) do
		table.insert(out, {id = f.id, kind = 'Axis', point = f.componentLocalCenter,
				direction = f.componentLocalAxis, diameter = f.diameter, feature = f})
	end
	if node.kind == 'Cylinder' and #component.operations == 0 then
		table.insert(out, {id = 'shaft', kind = 'Axis', point = Vector3.zero,
				direction = Vector3.yAxis, diameter = node.size.X, length = node.size.Y})
	end
	if node.kind == 'Block' or node.kind == 'Cylinder' or node.kind == 'SketchBody' then
		for _, sign in ipairs({-1, 1}) do
			table.insert(out, {id = 'face:Y' .. sign, kind = 'Plane',
					point = Vector3.yAxis*node.size.Y*.5*sign, direction = Vector3.yAxis*sign})
		end
	end
	if node.kind == 'Block' then
		for name, axis in pairs({X = Vector3.xAxis, Z = Vector3.zAxis}) do
			for _, sign in ipairs({-1, 1}) do
				table.insert(out, {id = 'face:' .. name .. sign, kind = 'Plane',
						point = axis*node.size[name]*.5*sign, direction = axis*sign})
			end
		end
	elseif node.kind == 'SketchBody' then
		local ring = Profile.outline(node)
		local signed = 0
		for i, p in ipairs(ring) do local q = ring[i%#ring+1]
			signed += p.X*q.Y-q.X*p.Y end
		for i, p in ipairs(ring) do
			local q = ring[i%#ring+1]
			local edge = Vector3.new(q.X-p.X, 0, q.Y-p.Y)
			if edge.Magnitude>1e-6 then
				table.insert(out, {id = 'edge:' .. i, kind = 'Plane',
						point = Vector3.new((p.X+q.X)*.5, 0, (p.Y+q.Y)*.5),
						direction = edge:Cross(Vector3.yAxis).Unit*(if signed>0 then 1 else -1)})
			end
		end
	end
	return out
end
function References.get(component:any, id:string):any?
	for _, ref in ipairs(References.list(component)) do if ref.id == id then return ref end end
	return nil
end
function References.world(ref:any, pose:CFrame):any
	local out = table.clone(ref)
	out.point = pose:PointToWorldSpace(ref.point)
	out.direction = pose:VectorToWorldSpace(ref.direction).Unit
	return out
end
return References
