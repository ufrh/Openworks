--!strict
-- Scalar budget: actual material volume in mm^3, never the dimensions
-- of an enclosing cuboid. Base primitives are analytic. Fabricated CSG
-- volume is measured from Roblox's collision solid at unit density.
local Quantize=require(script.Parent.Quantize)
local RoundedLProfile=require(script.Parent.RoundedLProfile)
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
