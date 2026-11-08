--!strict
local Simulation = {}
Simulation.__index = Simulation
function Simulation.new(bridge:any, remote:any)
	return setmetatable({bridge = bridge, remote = remote, active = false}, Simulation)
end
function Simulation:Enter()
	self.bridge.enterAssembly()
	local ok, layout = self.remote:GetLayout()
	if not ok then
		error(tostring(layout))
	end
	local accepted, reason = self.remote:StartSimulation(layout.revision)
	if not accepted then
		error(tostring(reason))
	end
	self.bridge.setSimulationFocus(reason)
	self.active = true
	local projection = self.bridge.getAssemblyState().projection
	projection.simulating = true
	projection:clear()
end
function Simulation:Exit()
	local ok, reason = self.remote:StopSimulation()
	if not ok then
		error(tostring(reason))
	end
	self.active = false
	self.bridge.getAssemblyState().projection.simulating = false
	self.bridge.leaveAssembly()
end
function Simulation:CleanupFailedEnter() self:Exit() end
return Simulation
