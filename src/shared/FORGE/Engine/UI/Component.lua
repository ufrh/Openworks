local Component = {}
Component.__index = Component
Component.ClassName = 'Component'

function Component.new(Runtime, Name, Variant, Object)
	assert(type(Runtime) == 'table', 'FORGE.UI.Component requires a runtime owner.')
	assert(type(Name) == 'string' and Name ~= '', 'FORGE.UI.Component requires a component name.')
	assert(typeof(Object) == 'Instance' and Object:IsA('GuiObject'), 'FORGE.UI.Component requires a GuiObject root.')

	local self = setmetatable({}, Component)
	self.Runtime = Runtime
	self.Name = Name
	self.Variant = Variant or 'Default'
	self.Object = Object
	self.Destroyed = false
	return self
end

function Component:IsMounted()
	return not self.Destroyed and self.Object ~= nil and self.Object.Parent ~= nil
end

function Component:Mount(Parent)
	assert(not self.Destroyed, 'Cannot mount a destroyed FORGE.UI.Component.')
	assert(typeof(Parent) == 'Instance', 'Component:Mount requires an Instance parent.')

	self.Object.Parent = Parent
	return self
end

function Component:Unmount()
	if self.Destroyed then return self end
	self.Object.Parent = nil
	return self
end

function Component:Destroy()
	if self.Destroyed then return end
	self.Destroyed = true

	local Object = self.Object
	self.Object = nil
	self.Runtime = nil

	if Object then Object:Destroy() end
end

return Component
