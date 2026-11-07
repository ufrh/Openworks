local RunService = game:GetService('RunService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')

local Component = require(script.Parent.Component)

local NativeRuntime = {}
NativeRuntime.__index = NativeRuntime

local function DisconnectAll(Connections)
	for _, Connection in ipairs(Connections) do
		Connection:Disconnect()
	end
	table.clear(Connections)
end

local function DestroyAll(Objects)
	for _, Object in ipairs(Objects) do
		Object:Destroy()
	end
	table.clear(Objects)
end

function NativeRuntime.new(ScreenGui)
	assert(typeof(ScreenGui) == 'Instance' and ScreenGui:IsA('ScreenGui'), 'NativeRuntime requires a ScreenGui.')

	local self = setmetatable({}, NativeRuntime)
	self.ScreenGui = ScreenGui
	self.Screens = {}
	self.ScreensByName = {}
	self.Components = {}
	self.Connections = {}
	self.Destroyed = false
	self:_Attach()
	return self
end

function NativeRuntime:_AttachScreen(Screen)
	if self.Screens[Screen] or not Screen:IsA('GuiObject') then return end

	local Name = Screen:GetAttribute('FORGEScreenName')
	if type(Name) ~= 'string' or Name == '' then return end

	local Entry = {
		Name = Name,
		Screen = Screen,
	}
	self.Screens[Screen] = Entry
	self.ScreensByName[Name] = Screen
end

function NativeRuntime:_DetachScreen(Screen)
	local Entry = self.Screens[Screen]
	if not Entry then return end

	self.Screens[Screen] = nil
	if self.ScreensByName[Entry.Name] == Screen then
		self.ScreensByName[Entry.Name] = nil
	end
end

function NativeRuntime:_Attach()
	for _, Child in ipairs(self.ScreenGui:GetChildren()) do
		self:_AttachScreen(Child)
	end

	table.insert(self.Connections, self.ScreenGui.ChildAdded:Connect(function(Child)
		self:_AttachScreen(Child)
	end))

	table.insert(self.Connections, self.ScreenGui.ChildRemoved:Connect(function(Child)
		self:_DetachScreen(Child)
	end))

	if RunService:IsStudio() then
		print('[FORGE.UI] attached native UI without runtime geometry transforms')
	end
end

function NativeRuntime:GetScreen(Name)
	return self.ScreensByName[Name]
end

function NativeRuntime:ShowScreen(Name)
	local Target = self:GetScreen(Name)
	if not Target then return false end

	for Screen in pairs(self.Screens) do
		Screen.Visible = Screen == Target
	end
	return true
end

function NativeRuntime:Refresh()
	return self
end

function NativeRuntime:GetComponentLibrary()
	return ReplicatedStorage:FindFirstChild('FORGEComponents')
end

-- Compatibility alias for existing callers. New code should use GetComponentLibrary.
NativeRuntime.retrieveComponentLibrary = NativeRuntime.GetComponentLibrary

function NativeRuntime:Component(Name, Variant)
	assert(not self.Destroyed, 'Cannot create a component from a destroyed NativeRuntime.')
	assert(type(Name) == 'string' and Name ~= '', 'NativeRuntime:Component requires a component name.')
	Variant = Variant or 'Default'

	local Library = self:GetComponentLibrary()
	if not Library then
		warn('[FORGE.UI] Component library not found.')
		return nil
	end

	local RootFolder = Library:FindFirstChild(Name)
	if not RootFolder then
		warn(string.format('[FORGE.UI] Component %q not found.', Name))
		return nil
	end

	local Default = RootFolder:FindFirstChild('Default')
	local Variants = RootFolder:FindFirstChild('Variants')
	assert(Default and Variants, '[FORGE.UI] Malformed component architecture.')

	local Template = Default
	if Variant ~= 'Default' then
		Template = Variants:FindFirstChild(Variant)
		assert(Template ~= nil, string.format('[FORGE.UI] No variant %q found for component %q.', Variant, Name))
	end
	assert(Template:IsA('GuiObject'), '[FORGE.UI] Component template must be a GuiObject.')

	local NewComponent = Component.new(self, Name, Variant, Template:Clone())
	table.insert(self.Components, NewComponent)
	return NewComponent
end

function NativeRuntime:Destroy()
	if self.Destroyed then return end
	self.Destroyed = true

	DisconnectAll(self.Connections)
	DestroyAll(self.Components)
	table.clear(self.Screens)
	table.clear(self.ScreensByName)
	self.ScreenGui = nil
end

return NativeRuntime
