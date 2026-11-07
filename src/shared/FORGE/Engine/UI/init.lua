local RunService = game:GetService('RunService')
local UIManager = require(script.UIManager)
local UserWidget = require(script.UserWidget)
local Widget = require(script.Widget)
local PanelWidget = require(script.PanelWidget)
local ContentWidget = require(script.ContentWidget)
local WidgetTree = require(script.WidgetTree)
local Slot = require(script.Slot)
local PanelSlot = require(script.PanelSlot)
local CanvasSlot = require(script.CanvasSlot)
local BoxSlot = require(script.BoxSlot)
local GridSlot = require(script.GridSlot)
local OverlaySlot = require(script.OverlaySlot)
local SizeBoxSlot = require(script.SizeBoxSlot)
local Panels = require(script.Panels)
local Controls = require(script.Controls)
local Animation = require(script.Animation)
local StyleSet = require(script.StyleSet)
local Enums = require(script.Enums)
local UIEvent = require(script.UIEvent)
local InputRouter = require(script.InputRouter)
local State = require(script.State)
local Component = require(script.Component)
local Collection = require(script.Collection)
local ProjectRuntime = require(script.ProjectRuntime)
local NativeRuntime = require(script.NativeRuntime)
local Responsive = require(script.Responsive)
local API = require(script.API)

local UI = {} do
	UI.API = API
	UI.Version = API.Version
	UI.Manager = UIManager.new()
	UI.Widget = Widget
	UI.UserWidget = UserWidget
	UI.PanelWidget = PanelWidget
	UI.ContentWidget = ContentWidget
	UI.WidgetTree = WidgetTree
	UI.Slot = Slot
	UI.PanelSlot = PanelSlot
	UI.CanvasSlot = CanvasSlot
	UI.BoxSlot = BoxSlot
	UI.GridSlot = GridSlot
	UI.OverlaySlot = OverlaySlot
	UI.SizeBoxSlot = SizeBoxSlot
	UI.Animation = Animation
	UI.StyleSet = StyleSet
	UI.Enums = Enums
	UI.UIEvent = UIEvent
	UI.InputRouter = InputRouter
	UI.State = State
	UI.Component = Component
	UI.Collection = Collection
	UI.ProjectRuntime = ProjectRuntime
	UI.NativeRuntime = NativeRuntime
	UI.Responsive = Responsive
	UI.NativeAttachments = setmetatable({}, {__mode = 'k'})
	UI.ActiveProject = nil

	UI.CanvasPanel = Panels.CanvasPanel
	UI.Overlay = Panels.Overlay
	UI.HorizontalBox = Panels.HorizontalBox
	UI.VerticalBox = Panels.VerticalBox
	UI.GridPanel = Panels.GridPanel
	UI.ScrollBox = Panels.ScrollBox
	UI.SizeBox = Panels.SizeBox
	UI.Border = Panels.Border
	UI.ScaleBox = Panels.ScaleBox
	UI.SafeZone = Panels.SafeZone
	UI.WidgetSwitcher = Panels.WidgetSwitcher

	UI.TextBlock = Controls.TextBlock
	UI.Image = Controls.Image
	UI.Spacer = Controls.Spacer
	UI.Button = Controls.Button
	UI.ProgressBar = Controls.ProgressBar
	UI.CheckBox = Controls.CheckBox
	UI.Slider = Controls.Slider
	UI.TextBox = Controls.TextBox

	function UI.CreateWidget(WidgetClass, ...)
		if type(WidgetClass) == 'function' then return WidgetClass(...) end
		if type(WidgetClass) == 'table' and WidgetClass.new then return WidgetClass.new(...) end
		error('CreateWidget requires a widget constructor or class.')
	end

	function UI.AddToViewport(Widget, ZOrder, Layer)
		return UI.Manager:AddToViewport(Widget, ZOrder, Layer)
	end

	function UI.RemoveFromViewport(Widget)
		return UI.Manager:RemoveFromViewport(Widget)
	end

	function UI.GetLayer(Name, ZIndex)
		return UI.Manager:GetLayer(Name, ZIndex)
	end

	function UI.SetInputMode(Mode)
		return UI.Manager:SetInputMode(Mode)
	end

	function UI.SetFocus(Widget)
		return UI.Manager:SetFocusedWidget(Widget)
	end

	function UI.GetFocus()
		return UI.Manager:GetFocusedWidget()
	end

	function UI.Navigate(Direction, From)
		return UI.Manager:Navigate(Direction, From)
	end

	function UI.CreateState(Value)
		return State.new(Value)
	end

	function UI.CreateStyleSet(Name, Parent)
		return StyleSet.new(Name, Parent)
	end

	function UI.CreateAnimation(...)
		return Animation.new(...)
	end

	function UI.Attach(ScreenGui)
		assert(typeof(ScreenGui) == 'Instance' and ScreenGui:IsA('ScreenGui'), 'FORGE.UI.Attach requires a ScreenGui.')

		local Existing = UI.NativeAttachments[ScreenGui]
		if Existing then return Existing end

		local Runtime = NativeRuntime.new(ScreenGui)
		UI.NativeAttachments[ScreenGui] = Runtime
		return Runtime
	end

	function UI.Detach(ScreenGui)
		local Runtime = UI.NativeAttachments[ScreenGui]
		if not Runtime then return false end

		UI.NativeAttachments[ScreenGui] = nil
		Runtime:Destroy()
		return true
	end

	function UI.MountProject(Data, Options)
		assert(type(Data) == 'table' and Data.Schema == 'FORGE.UI.Project', 'MountProject requires a FORGE UI project package.')

		local Runtime = ProjectRuntime.new(UI, Data, Options)
		local Success, Mounted = pcall(function()
			return Runtime:Mount()
		end)
		if not Success or not Mounted then
			Runtime:Destroy()
			error(Success and 'FORGE UI project start screen could not mount.' or tostring(Mounted))
		end

		local Previous = UI.ActiveProject
		UI.ActiveProject = Runtime
		if Previous then Previous:Destroy() end
		return Runtime
	end

	function UI.MountPackage(Package, Options)
		local PackageFolder
		if Package and Package:IsA('Folder') then
			PackageFolder = Package
			Package = Package:FindFirstChild('Runtime') or Package:FindFirstChild('Project')
		elseif Package and Package:IsA('ModuleScript') then
			PackageFolder = Package.Parent
		end
		assert(Package and Package:IsA('ModuleScript'), 'MountPackage requires a generated FORGE project package.')

		local StartedAt = os.clock()
		local Success, Data = pcall(require, Package)
		local RequireSeconds = os.clock() - StartedAt
		assert(Success, 'FORGE UI package failed to load: ' .. tostring(Data))

		Options = table.clone(Options or {})
		Options.Package = PackageFolder

		local MountStartedAt = os.clock()
		local Runtime = UI.MountProject(Data, Options)
		local MountSeconds = os.clock() - MountStartedAt

		if RunService:IsStudio() then
			print(string.format(
				'[FORGE.UI] package require %.3fs | mount %.3fs | total %.3fs',
				RequireSeconds,
				MountSeconds,
				RequireSeconds + MountSeconds
			))
		end
		return Runtime
	end

	function UI.GetProject()
		return UI.ActiveProject
	end

	function UI.UnmountProject()
		local Runtime = UI.ActiveProject
		UI.ActiveProject = nil
		if Runtime then Runtime:Destroy() end
		return Runtime ~= nil
	end

	function UI.Destroy()
		UI.UnmountProject()
		for ScreenGui, Runtime in pairs(UI.NativeAttachments) do
			UI.NativeAttachments[ScreenGui] = nil
			Runtime:Destroy()
		end
		UI.Manager:Destroy()
	end
end

return UI;