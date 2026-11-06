--!strict
-- Scalar budget: actual material volume in mm^3, never the dimensions
-- of an enclosing cuboid. Base primitives are analytic. Fabricated CSG
-- volume is measured from Roblox's collision solid at unit density.
local Quantize=require(script.Parent.Quantize)
local RoundedLProfile=require(script.Parent.RoundedLProfile)
local AssetService=game:GetService("AssetService")
local Volume={}
Volume.MM_PER_STUD=280
Volume.MM3_PER_STUD3=Volume.MM_PER_STUD^3
Volume.MaxMM3=Quantize.MaxComponentVolumeMM3

local function polygonArea(points:{Vector2}):number
	local sum=0
	for i,p in ipairs(points) do
		local q=points[i%#points+1]
		sum+=p.X*q.Y-p.Y*q.X
	end
	return math.abs(sum)*0.5
end

function Volume.primitive(kind:string,size:Vector3):number
	if kind=="Block" then return size.X*size.Y*size.Z end
	if kind=="Cylinder" then
		return math.pi*(size.X*0.5)^2*size.Y
	end
	if kind=="RoundedL" then
		return polygonArea(RoundedLProfile.outline({size=size}))*size.Z
	end
	error("Unknown material primitive: "..tostring(kind))
end

function Volume.fromPart(solid:BasePart):number
	-- Density 1 makes Roblox physical mass numerically equal to the
	-- collision solid's volume in stud^3. For MeshParts/CSG this is
	-- a collision-fidelity estimate, NOT visual AABB volume.
	local prior=solid.CustomPhysicalProperties
	solid.CustomPhysicalProperties=PhysicalProperties.new(1,0.3,0.5,1,1)
	local success,mass=pcall(function() return solid:GetMass() end)
	solid.CustomPhysicalProperties=prior
	if not success or type(mass)~="number" or not Quantize.isFinite(mass)
		or mass<0 then
		return math.huge
	end
	return mass
end

-- Prefer the watertight *render mesh* for manufactured solids. This
-- distinguishes actual cavities from collision hull approximations.
-- Engine/asset permissions can deny readback; only then use physical
-- collision volume as a documented estimate.
function Volume.fromPartAsync(solid:BasePart):(number,boolean)
	if solid:IsA("MeshPart") then
		local loaded,editable=pcall(function()
			return AssetService:CreateEditableMeshAsync(solid.MeshContent)
		end)
		if loaded and editable then
			local ok,volume=pcall(function()
				local size=editable:GetSize()
				if math.min(size.X,size.Y,size.Z)<=0 then
					error("Empty mesh")
				end
				local sx=solid.Size.X/size.X
				local sy=solid.Size.Y/size.Y
				local sz=solid.Size.Z/size.Z
				local positions={}
				local signed=0
				for _,id in ipairs(editable:GetFaces()) do
					local ids=editable:GetFaceVertices(id)
					if #ids>=3 then
						local function vertex(vertexId:number):Vector3
							local cached=positions[vertexId]
							if cached then return cached end
							local p=editable:GetPosition(vertexId)
							p=Vector3.new(p.X*sx,p.Y*sy,p.Z*sz)
							positions[vertexId]=p
							return p
						end
						local a=vertex(ids[1])
						for i=2,#ids-1 do
							local b=vertex(ids[i])
							local c=vertex(ids[i+1])
							signed+=a:Dot(b:Cross(c))/6
						end
					end
				end
				return math.abs(signed)
			end)
			editable:Destroy()
			-- Signed tetrahedra give true material volume for closed
			-- consistently wound meshes. Sanity check the bounds.
			if ok and type(volume)=="number" and Quantize.isFinite(volume)
				and volume>1e-9 and volume<=solid.Size.X*solid.Size.Y*solid.Size.Z*1.01 then
				return volume,true
			end
		end
	end
	return Volume.fromPart(solid),false
end

function Volume.toMM3(stud3:number):number
	return stud3*Volume.MM3_PER_STUD3
end

function Volume.within(stud3:number):boolean
	return stud3<=Volume.MaxMM3/Volume.MM3_PER_STUD3+1e-7
end

function Volume.display(stud3:number):string
	if not Quantize.isFinite(stud3) then return "Calculating…" end
	local digits=tostring(math.floor(Volume.toMM3(stud3)+0.5))
	return (digits:reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","")).." mm³"
end

return Volume
