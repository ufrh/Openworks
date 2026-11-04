--!strict
-- Async compiled-surface cache. Mesh reads are performed once per visible
-- manufactured revision, NEVER inside hover/render or mouse-click handlers.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local SurfaceTopology=require(script.Parent.SurfaceTopology)
local SurfacePicker={}
SurfacePicker.__index=SurfacePicker

function SurfacePicker.new(onStatus)
	return setmetatable({cache={},onStatus=onStatus},SurfacePicker)
end

local function solid(model:Model?):BasePart?
	if not model then return nil end
	local part=model:FindFirstChild("Solid")
	if part and part:IsA("BasePart") then return part end
	return nil
end

function SurfacePicker:request(id:number,model:Model?)
	local part=solid(model)
	if not part then return end
	local existing=self.cache[id]
	if existing and existing.part==part then return end
	local entry={part=part,ready=false,topology=nil,error=nil}
	self.cache[id]=entry
	-- Reads can yield; old completions must never replace newer geometry.
	task.spawn(function()
		local topology,why=SurfaceTopology.extract(part)
		if self.cache[id]~=entry then return end
		entry.ready=true
		entry.topology=topology
		entry.error=why
		if topology then
			self.onStatus(string.format("Surface indexed: %d faces · %d edges",
				#topology.faces,#topology.edges))
		else
			self.onStatus("Surface selection unavailable: "..tostring(why))
		end
	end)
end

function SurfacePicker:get(id:number,model:Model?)
	local part=solid(model)
	local entry=self.cache[id]
	if not entry or entry.part~=part then
		self:request(id,model)
		return nil,"Surface indexing in progress"
	end
	if not entry.ready then return nil,"Surface indexing in progress" end
	if not entry.topology then return nil,entry.error or "Surface indexing failed" end
	return entry.topology,nil
end

function SurfacePicker:remove(id:number)
	self.cache[id]=nil
end

return SurfacePicker
