--!strict
local Registry={}
Registry.__index=Registry
function Registry.new()
	return setmetatable({services={},order={}},Registry)
end
function Registry:register(name:string,instance:any)
	assert(type(name)=="string" and name~="","Service name required")
	assert(self.services[name]==nil,"Service already registered: "..name)
	self.services[name]=instance
	table.insert(self.order,name)
	return instance
end
function Registry:get(name:string):any
	local service=self.services[name]
	assert(service~=nil,"Unknown OpenWorks service: "..name)
	return service
end
function Registry:find(name:string):any
	return self.services[name]
end
function Registry:clear()
	table.clear(self.services)
	table.clear(self.order)
end
return Registry
