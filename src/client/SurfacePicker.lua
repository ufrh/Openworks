--!strict
-- Async compiled-surface cache. Mesh reads are performed once per visible
-- manufactured revision, NEVER inside hover/render or mouse-click handlers.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local FORM=ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM")
local Fabricator=require(FORM.Fabricator)
local Document=require(FORM.Document)
local HistoryTopology=require(script.Parent.HistoryTopology)
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

function SurfacePicker:request(id:number,model:Model?,component)
	local part=solid(model)
	if not part or not component then return end
	local signature=Fabricator.geometryKey(component)
	local existing=self.cache[id]
	if existing and existing.part==part and existing.signature==signature then return end
	local snapshot=Document.snapshot(component)
	local entry={part=part,signature=signature,ready=false,topology=nil,error=nil}
	self.cache[id]=entry
	-- This indexes FORM's authored feature history, NOT the internal CSG
	-- mesh. GeometryService's generated mesh content cannot be assumed
	-- to support CreateEditableMeshAsync readback in the live editor.
	task.spawn(function()
		local ok,topology,why=pcall(HistoryTopology.build,part,snapshot)
		if self.cache[id]~=entry then return end
		entry.ready=true
		entry.topology=if ok then topology else nil
		entry.error=if ok then why else tostring(topology)
		if entry.topology then
			self.onStatus(string.format("FORM surfaces: %d faces / %d edges (history)",
				#entry.topology.faces,#entry.topology.edges))
		else
			self.onStatus("Surface indexing failed: "..tostring(entry.error))
		end
	end)
end

function SurfacePicker:get(id:number,model:Model?,component)
	local part=solid(model)
	if not part or not component then return nil,"No selected workpiece" end
	local entry=self.cache[id]
	local signature=Fabricator.geometryKey(component)
	if not entry or entry.part~=part or entry.signature~=signature then
		self:request(id,model,component)
		return nil,"Building surface selection"
	end
	if not entry.ready then return nil,"Building surface selection" end
	if not entry.topology then return nil,entry.error or "Surface indexing failed" end
	return entry.topology,nil
end

function SurfacePicker:remove(id:number)
	self.cache[id]=nil
end

return SurfacePicker
