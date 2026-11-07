--!strict
-- Small explicit lifecycle contract. Systems never discover dependencies by
-- scanning all ModuleScripts; the bootstrap declares their order.
local Lifecycle={}
function Lifecycle.start(service:any,context:any)
	if service.Start then service:Start(context) end
end
function Lifecycle.stop(service:any)
	if service.Stop then service:Stop() end
end
function Lifecycle.destroy(service:any)
	if service.Destroy then service:Destroy()
	elseif service.destroy then service:destroy() end
end
return Lifecycle
