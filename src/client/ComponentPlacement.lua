--!strict
-- WALK -> SPECIFY -> PLACE GRID -> SKETCH. No primitive picker or
-- translucent block; the only placement geometry is the bounded grid.
local UserInputService=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local FORM=ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM")
local Quantize=require(FORM.Quantize)
local ComponentPlacement={}
ComponentPlacement.__index=ComponentPlacement
local MM=280

local function make(kind:string,properties,parent:Instance)
	local obj=Instance.new(kind)
	for key,value in pairs(properties) do obj[key]=value end
	obj.Parent=parent
	return obj
end
local function label(parent:Instance,value:string,y:number,height:number):TextLabel
	return make("TextLabel",{
		BackgroundTransparency=1,
		Text=value,TextWrapped=true,
		TextColor3=Color3.fromRGB(226,238,242),
		TextSize=13,Font=Enum.Font.Code,
		TextXAlignment=Enum.TextXAlignment.Left,
		Position=UDim2.fromOffset(16,y),
		Size=UDim2.new(1,-32,0,height),
	},parent)
end
local function button(parent:Instance,value:string,pos:UDim2,size:UDim2):TextButton
	local control=make("TextButton",{
		BackgroundColor3=Color3.fromRGB(52,65,72),
		BorderSizePixel=0,
		Text=value,Font=Enum.Font.Code,TextSize=13,
		TextColor3=Color3.new(1,1,1),
		Position=pos,Size=size,
	},parent)
	make("UICorner",{CornerRadius=UDim.new(0,5)},control)
	return control
end

function ComponentPlacement.new(playerGui:PlayerGui,grid,onPlace,onStatus,onCancel)
	local ui=make("ScreenGui",{
		Name="FORM_CreateComponent",ResetOnSpawn=false,
		ZIndexBehavior=Enum.ZIndexBehavior.Sibling,DisplayOrder=50,
	},playerGui)
	local launch=button(ui,"+ Create Component",
		UDim2.fromOffset(20,20),UDim2.fromOffset(190,42))
	local form=make("Frame",{
		Name="ComponentSpecification",Visible=false,
		BackgroundColor3=Color3.fromRGB(24,30,35),
		BorderSizePixel=0,AnchorPoint=Vector2.new(.5,.5),
		Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(346,325),
	},ui)
	make("UICorner",{CornerRadius=UDim.new(0,8)},form)
	label(form,"CREATE COMPONENT",12,24)
	label(form,"Name",48,20)
	local function box(name:string,default:string,y:number):TextBox
		local input=make("TextBox",{
			Name=name,Text=default,ClearTextOnFocus=false,
			BackgroundColor3=Color3.fromRGB(45,54,61),
			BorderSizePixel=0,TextColor3=Color3.new(1,1,1),
			Font=Enum.Font.Code,TextSize=13,
			Position=UDim2.fromOffset(16,y),Size=UDim2.new(1,-32,0,29),
		},form)
		if name~="ComponentName" then
			local axis=string.sub(name,1,1)
			local axisLabel=label(form,axis.." (mm)",y+4,20)
			axisLabel.Size=UDim2.fromOffset(80,20)
			input.Position=UDim2.fromOffset(105,y)
			input.Size=UDim2.new(1,-121,0,29)
		end
		make("UICorner",{CornerRadius=UDim.new(0,4)},input)
		return input
	end
	local nameBox=box("ComponentName","",70)
	label(form,"SKETCH WORKSPACE SIZE (mm)",108,19)
	local xBox=box("X_mm","280",132)
	local yBox=box("Y_mm","140",169)
	local zBox=box("Z_mm","280",206)
	local feedback=label(form,"X/Z = grid size · Y = first extrusion height",243,24)
	feedback.TextSize=11
	local cancel=button(form,"Cancel",UDim2.fromOffset(16,280),
		UDim2.fromOffset(150,32))
	local nextStep=button(form,"Place Sketch Grid",UDim2.fromOffset(172,280),
		UDim2.fromOffset(158,32))
	local hint=label(ui,"Place sketch grid • Left click to confirm • Esc to cancel",
		0,30)
	hint.AnchorPoint=Vector2.new(.5,1)
	hint.Position=UDim2.new(.5,0,1,-48)
	hint.Size=UDim2.fromOffset(500,30)
	hint.TextXAlignment=Enum.TextXAlignment.Center
	hint.Visible=false

	local self=setmetatable({
		ui=ui,launch=launch,form=form,hint=hint,
		grid=grid,placing=false,showLaunch=true,
		size=Vector3.new(1,.5,1),name="",
		lastPosition=nil,onPlace=onPlace,onStatus=onStatus,onCancel=onCancel,
	},ComponentPlacement)
	local function groundPoint():Vector3?
		local camera=workspace.CurrentCamera
		if not camera then return nil end
		local m=UserInputService:GetMouseLocation()
		local ray=camera:ViewportPointToRay(m.X,m.Y)
		local excludes={}
		local char=Players.LocalPlayer.Character
		if char then table.insert(excludes,char) end
		for _,name in ipairs({"FORM_LocalPreview","FORM_TransformGrips"}) do
			local root=workspace:FindFirstChild(name)
			if root then table.insert(excludes,root) end
		end
		local params=RaycastParams.new()
		params.FilterType=Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances=excludes
		local hit=workspace:Raycast(ray.Origin,ray.Direction*1000,params)
		local point:Vector3?
		if hit and hit.Normal.Y>0.65 then
			point=hit.Position
		else
			-- Ground-plane fallback for empty test worlds.
			if math.abs(ray.Direction.Y)<1e-6 then return nil end
			local t=-ray.Origin.Y/ray.Direction.Y
			if t<0 then return nil end
			point=ray.Origin+ray.Direction*t
		end
		return Vector3.new(
			Quantize.snap(point.X-self.size.X*.5,Quantize.Grid),
			Quantize.snap(point.Y,Quantize.Grid),
			Quantize.snap(point.Z-self.size.Z*.5,Quantize.Grid))
	end
	local function close(keepGrid:boolean)
		self.placing=false
		self.lastPosition=nil
		form.Visible=false
		hint.Visible=false
		launch.Visible=self.showLaunch
		if not keepGrid then grid:setVisible(false) end
	end
	function self:close()
		close(false)
		if onCancel then onCancel() end
	end
	function self:open()
		close(false)
		form.Visible=true
		launch.Visible=false
		feedback.Text="X/Z = grid size · Y = first extrusion height"
	end
	function self:setLaunchVisible(value:boolean)
		self.showLaunch=value
		if not self.placing and not form.Visible then launch.Visible=value end
	end
	launch.MouseButton1Click:Connect(function()self:open()end)
	cancel.MouseButton1Click:Connect(function()self:close()end)
	nextStep.MouseButton1Click:Connect(function()
		local x,y,z=tonumber(xBox.Text),tonumber(yBox.Text),tonumber(zBox.Text)
		if not x or not y or not z or not Quantize.isFinite(x)
			or not Quantize.isFinite(y) or not Quantize.isFinite(z) then
			feedback.Text="Enter valid numeric dimensions in mm"
			return
		end
		local size=Quantize.vector(Vector3.new(x,y,z)/MM,Quantize.Size)
		if math.min(size.X,size.Y,size.Z)<Quantize.MinSize
			or math.max(size.X,size.Y,size.Z)>Quantize.MaxSize then
			feedback.Text="Dimensions must be 14–35,840 mm"
			return
		end
		if not nameBox.Text:match("%S") then
			feedback.Text="Name your component before placing it"
			return
		end
		self.size=size
		self.name=string.sub(nameBox.Text,1,64)
		self.placing=true
		self.lastPosition=nil
		form.Visible=false
		launch.Visible=false
		hint.Visible=true
		grid:setVisible(false)
		onStatus("Position the sketch grid over the ground and click")
	end)
	RunService:BindToRenderStep("FORM_PlaceSketchGrid",
		Enum.RenderPriority.Camera.Value+3,function()
		if not self.placing then return end
		local at=groundPoint()
		if not at then
			self.lastPosition=nil
			grid:setVisible(false)
			return
		end
		if at~=self.lastPosition then
			grid:update(at,self.size)
			self.lastPosition=at
		end
		grid:setVisible(true)
	end)
	UserInputService.InputBegan:Connect(function(input,processed)
		if not self.placing then return end
		if input.KeyCode==Enum.KeyCode.Escape then
			self:close()
			return
		end
		if processed or input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
		local at=groundPoint()
		if not at then return end
		grid:update(at,self.size)
		grid:setVisible(true)
		close(true)
		onPlace(self.name,self.size,at)
	end)
	return self
end

return ComponentPlacement
