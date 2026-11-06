--!strict
-- First-run component creation: named dimensions, then cursor-anchored
-- ground placement. Editor workspace is entered only on the final click.
local UserInputService=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local FORM=ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM")
local Quantize=require(FORM.Quantize)
local MaterialVolume=require(FORM.MaterialVolume)
local ComponentPlacement={}
ComponentPlacement.__index=ComponentPlacement
local MM=280

local function make(kind:string,props,parent:Instance)
	local obj=Instance.new(kind)
	for key,value in pairs(props) do obj[key]=value end
	obj.Parent=parent
	return obj
end
local function label(parent:Instance,text:string,position:UDim2,size:UDim2)
	return make("TextLabel",{
		BackgroundTransparency=1,Font=Enum.Font.Code,Text=text,
		TextSize=14,TextColor3=Color3.fromRGB(229,239,242),
		TextXAlignment=Enum.TextXAlignment.Left,Position=position,Size=size,
	},parent)
end
local function button(parent:Instance,title:string,position:UDim2,size:UDim2)
	local item=make("TextButton",{
		Text=title,Font=Enum.Font.Code,TextSize=13,
		TextColor3=Color3.new(1,1,1),BorderSizePixel=0,
		BackgroundColor3=Color3.fromRGB(56,66,73),
		Position=position,Size=size,
	},parent)
	make("UICorner",{CornerRadius=UDim.new(0,5)},item)
	return item
end

function ComponentPlacement.new(playerGui:PlayerGui,onPlace,onStatus)
	local ui=make("ScreenGui",{
		Name="FORM_CreateComponent",ResetOnSpawn=false,
		ZIndexBehavior=Enum.ZIndexBehavior.Sibling,DisplayOrder=50,
	},playerGui)
	local launch=button(ui,"+ Create Component",UDim2.new(0.5,-92,0.5,-22),
		UDim2.fromOffset(184,44))
	local form=make("Frame",{
		Name="ComponentSpecification",Visible=false,
		BackgroundColor3=Color3.fromRGB(24,30,35),
		BorderSizePixel=0,AnchorPoint=Vector2.new(.5,.5),
		Position=UDim2.fromScale(.5,.5),
		Size=UDim2.fromOffset(330,340),
	},ui)
	make("UICorner",{CornerRadius=UDim.new(0,8)},form)
	label(form,"CREATE COMPONENT",UDim2.fromOffset(16,10),
		UDim2.fromOffset(300,26))
	local inputColor=Color3.fromRGB(46,56,63)
	local function textBox(name:string,default:string,y:number)
		label(form,name,UDim2.fromOffset(16,y),UDim2.fromOffset(72,30))
		local input=make("TextBox",{
			Name=name,Text=default,Font=Enum.Font.Code,TextSize=14,
			TextColor3=Color3.new(1,1,1),BackgroundColor3=inputColor,
			ClearTextOnFocus=false,BorderSizePixel=0,
			Position=UDim2.fromOffset(90,y),Size=UDim2.fromOffset(220,29),
		},form)
		make("UICorner",{CornerRadius=UDim.new(0,4)},input)
		return input
	end
	local nameBox=textBox("Name","",43)
	label(form,"PRIMITIVE",UDim2.fromOffset(16,83),
		UDim2.fromOffset(130,22))
	local choices={}
	local defaults={
		Block={84,56,84},Cylinder={84,56,84},
		RoundedL={70,70,56}
	}
	local selectedKind="Block"
	local kindList={{"Block","Block"},{"Cylinder","Cylinder"},{"Inside L","RoundedL"}}
	for i,entry in ipairs(kindList) do
		choices[entry[2]]=button(form,entry[1],
			UDim2.fromOffset(16+(i-1)*100,108),UDim2.fromOffset(94,31))
	end
	local xBox=textBox("X (mm)","84",149)
	local yBox=textBox("Y (mm)","56",185)
	local zBox=textBox("Z (mm)","84",221)
	local feedback=label(form,"Material budget: "..MaterialVolume.display(Quantize.MaxComponentVolume),
		UDim2.fromOffset(16,258),UDim2.fromOffset(300,20))
	feedback.TextSize=11
	local cancel=button(form,"Cancel",UDim2.fromOffset(16,291),
		UDim2.fromOffset(143,34))
	local nextStep=button(form,"Place on ground",UDim2.fromOffset(167,291),
		UDim2.fromOffset(143,34))
	local placementHint=label(ui,"Move cursor to place • Left click to build • Esc to cancel",
		UDim2.new(0.5,-235,1,-74),UDim2.fromOffset(470,28))
	placementHint.TextXAlignment=Enum.TextXAlignment.Center
	placementHint.Visible=false
	local indicator=make("Part",{
		Name="FORM_PlacementPreview",Anchored=true,CanTouch=false,CanCollide=false,
		CanQuery=false,CastShadow=false,Transparency=1,
		Color=Color3.fromRGB(99,220,239),Material=Enum.Material.SmoothPlastic,
		Size=Vector3.one*0.1,
	},workspace)
	local origin=make("Part",{
		Name="FORM_PlacementGridOrigin",Anchored=true,CanTouch=false,
		CanCollide=false,CanQuery=false,CastShadow=false,Transparency=1,
		Size=Vector3.one*0.05,CFrame=CFrame.identity,
	},workspace)
	local gridLines={}
	for i=1,100 do
		table.insert(gridLines,make("LineHandleAdornment",{
			Name="GroundGrid_"..i,Adornee=origin,Visible=false,
			AlwaysOnTop=false,Color3=Color3.fromRGB(186,242,247),
			Transparency=.17,Thickness=1,
		},origin))
	end
	local self=setmetatable({
		ui=ui,launch=launch,form=form,hint=placementHint,
		indicator=indicator,origin=origin,gridLines=gridLines,
		placing=false,kind="Block",size=Vector3.one,lastOrigin=nil,
		name="",onPlace=onPlace,onStatus=onStatus,showLaunch=true,
	},ComponentPlacement)
	local function refreshChoices()
		for kind,control in pairs(choices) do
			control.BackgroundColor3=if kind==selectedKind
				then Color3.fromRGB(55,140,145) else Color3.fromRGB(56,66,73)
		end
	end
	for _,entry in ipairs(kindList) do
		local kind=entry[2]
		choices[kind].MouseButton1Click:Connect(function()
			selectedKind=kind
			local d=defaults[kind]
			xBox.Text=tostring(d[1])
			yBox.Text=tostring(d[2])
			zBox.Text=tostring(d[3])
			refreshChoices()
		end)
	end
	refreshChoices()
	launch.MouseButton1Click:Connect(function()self:open()end)
	cancel.MouseButton1Click:Connect(function()self:close()end)
	nextStep.MouseButton1Click:Connect(function()
		local x,y,z=tonumber(xBox.Text),tonumber(yBox.Text),tonumber(zBox.Text)
		if not x or not y or not z or
			not Quantize.isFinite(x) or not Quantize.isFinite(y) or
			not Quantize.isFinite(z) then
			feedback.Text="Enter numeric X, Y, Z dimensions in millimeters"
			return
		end
		local size=Quantize.vector(Vector3.new(x,y,z)/MM,Quantize.Size)
		if math.min(size.X,size.Y,size.Z)<Quantize.MinSize
			or math.max(size.X,size.Y,size.Z)>Quantize.MaxSize
			or not MaterialVolume.within(MaterialVolume.primitive(selectedKind,size)) then
			feedback.Text="Material exceeds "..MaterialVolume.display(Quantize.MaxComponentVolume)
			return
		end
		if selectedKind=="Cylinder" and math.abs(size.X-size.Z)>1/MM then
			feedback.Text="Cylinder X and Z must have equal diameters"
			return
		end
		self.name=nameBox.Text
		self.kind=selectedKind
		self.size=size
		self.placing=true
		self.lastOrigin=nil
		form.Visible=false
		launch.Visible=false
		placementHint.Visible=true
		indicator.Size=size
		indicator.Transparency=.68
		onStatus("Move the placement grid over the ground and click")
	end)
	-- The pointer marks the CENTER of the footprint; source component
	-- storage continues using the minimum corner of that footprint.
	local function footprint(cursor:Vector3,size:Vector3):Vector3
		return Vector3.new(
			Quantize.snap(cursor.X-size.X*0.5,Quantize.Grid),0,
			Quantize.snap(cursor.Z-size.Z*0.5,Quantize.Grid))
	end
	local function hideGrid()
		for _,line in ipairs(gridLines) do line.Visible=false end
		indicator.Transparency=1
	end
	function self:close()
		self.placing=false
		self.lastOrigin=nil
		form.Visible=false
		placementHint.Visible=false
		launch.Visible=self.showLaunch
		hideGrid()
	end
	function self:open()
		self:close()
		form.Visible=true
		launch.Visible=false
		feedback.Text="Material budget: "..MaterialVolume.display(Quantize.MaxComponentVolume)
	end
	function self:setLaunchVisible(value:boolean)
		self.showLaunch=value
		if not self.placing and not form.Visible then
			launch.Visible=value
		end
	end
	local function line(index:number,a:Vector3,b:Vector3)
		local guide=gridLines[index]
		if not guide then return end
		guide.CFrame=CFrame.lookAt(a,b)
		guide.Length=(b-a).Magnitude
		guide.Visible=true
	end
	local function pointOnGround():Vector3?
		local camera=workspace.CurrentCamera
		if not camera then return nil end
		local mouse=UserInputService:GetMouseLocation()
		local ray=camera:ViewportPointToRay(mouse.X,mouse.Y)
		if math.abs(ray.Direction.Y)<1e-5 then return nil end
		local t=-ray.Origin.Y/ray.Direction.Y
		if t<0 then return nil end
		local world=ray.Origin+ray.Direction*t
		local x=Quantize.snap(math.clamp(world.X,-Quantize.MaxPosition,
			Quantize.MaxPosition),Quantize.Grid)
		local z=Quantize.snap(math.clamp(world.Z,-Quantize.MaxPosition,
			Quantize.MaxPosition),Quantize.Grid)
		return Vector3.new(x,0,z)
	end
	RunService.RenderStepped:Connect(function()
		if not self.placing then return end
		local at=pointOnGround()
		if not at then
			self.lastOrigin=nil
			hideGrid()
			return
		end
		self.lastPosition=at
		indicator.Size=self.size
		local base=footprint(at,self.size)
		indicator.CFrame=CFrame.new(base+self.size*0.5)
		indicator.Transparency=.68
		if self.lastOrigin and self.lastOrigin==base then return end
		self.lastOrigin=base
		for _,g in ipairs(gridLines) do g.Visible=false end
		local width,depth=self.size.X,self.size.Z
		local spacing=Quantize.Grid
		local index=0
		local stepX=math.max(1,math.ceil(width/spacing/48))
		local stepZ=math.max(1,math.ceil(depth/spacing/48))
		local function add(a:Vector3,b:Vector3)
			index+=1
			line(index,a,b)
		end
		for i=0,math.ceil(width/spacing),stepX do
			local x=math.min(width,i*spacing)
			add(base+Vector3.new(x,.004,0),base+Vector3.new(x,.004,depth))
		end
		for i=0,math.ceil(depth/spacing),stepZ do
			local z=math.min(depth,i*spacing)
			add(base+Vector3.new(0,.004,z),base+Vector3.new(width,.004,z))
		end
	end)
	UserInputService.InputBegan:Connect(function(input,processed)
		if not self.placing then return end
		if input.KeyCode==Enum.KeyCode.Escape then
			self:close()
			return
		end
		if processed or input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
		local at=pointOnGround()
		if not at then return end
		self:close()
		onPlace(self.kind,self.name,self.size,footprint(at,self.size))
	end)
	return self
end
return ComponentPlacement
