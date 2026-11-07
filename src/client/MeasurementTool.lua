--!strict
-- Click two actual world points (manufactured solid or ground) and read
-- straight-line Euclidean distance. No cursor ruler or auto increments.
local UserInputService=game:GetService("UserInputService")
local SurfaceSnap=require(script.Parent.SurfaceSnap)
local MeasurementTool={}
MeasurementTool.__index=MeasurementTool
local function part(parent:Instance,name:string)
	local p=Instance.new("Part")
	p.Name=name
	p.Size=Vector3.one*0.05
	p.Transparency=1
	p.Anchored=true
	p.CanQuery=false
	p.CanTouch=false
	p.CanCollide=false
	p.CastShadow=false
	p.CFrame=CFrame.identity
	p.Parent=parent
	return p
end
local function marker(parent:PlayerGui,origin:Part,name:string):BillboardGui
	local gui=Instance.new("BillboardGui")
	gui.Name=name
	gui.Adornee=origin
	gui.Size=UDim2.fromOffset(9,9)
	gui.AlwaysOnTop=true
	gui.Enabled=false
	gui.Parent=parent
	local dot=Instance.new("Frame")
	dot.Name="Point"
	dot.Size=UDim2.fromScale(1,1)
	dot.BorderSizePixel=0
	dot.BackgroundColor3=Color3.new(1,1,1)
	dot.Parent=gui
	local round=Instance.new("UICorner")
	round.CornerRadius=UDim.new(1,0)
	round.Parent=dot
	return gui
end

function MeasurementTool.new(playerGui:PlayerGui,solidRoot:Instance)
	local folder=Instance.new("Folder")
	folder.Name="FORM_PointMeasurement"
	folder.Parent=workspace
	local start=part(folder,"StartPoint")
	local finish=part(folder,"EndPoint")
	local origin=part(folder,"MeasurementLineOrigin")
	local guide=Instance.new("LineHandleAdornment")
	guide.Name="BetweenPoints"
	guide.Adornee=origin
	guide.Color3=Color3.new(1,1,1)
	guide.Thickness=2.8
	guide.Transparency=0
	guide.AlwaysOnTop=true
	guide.Visible=false
	guide.Parent=folder
	local firstGui=marker(playerGui,start,"MeasurementPointA")
	local secondGui=marker(playerGui,finish,"MeasurementPointB")
	local textGui=Instance.new("BillboardGui")
	textGui.Name="PointDistance"
	textGui.Adornee=origin
	textGui.Size=UDim2.fromOffset(146,30)
	textGui.AlwaysOnTop=true
	textGui.Enabled=false
	textGui.Parent=playerGui
	local label=Instance.new("TextLabel")
	label.Name="Distance"
	label.Size=UDim2.fromScale(1,1)
	label.BackgroundColor3=Color3.fromRGB(26,33,39)
	label.BackgroundTransparency=.08
	label.BorderSizePixel=0
	label.TextColor3=Color3.new(1,1,1)
	label.Font=Enum.Font.Code
	label.TextSize=14
	label.Parent=textGui
	local corner=Instance.new("UICorner")
	corner.CornerRadius=UDim.new(0,5)
	corner.Parent=label
	return setmetatable({
		root=folder,first=start,second=finish,lineOrigin=origin,
		line=guide,firstGui=firstGui,secondGui=secondGui,
		labelGui=textGui,label=label,
		solidRoot=solidRoot,active=false,pointA=nil,
	},MeasurementTool)
end

function MeasurementTool:reset()
	self.pointA=nil
	self.firstGui.Enabled=false
	self.secondGui.Enabled=false
	self.line.Visible=false
	self.labelGui.Enabled=false
end
function MeasurementTool:setActive(active:boolean)
	self.active=active
	self:reset()
end
function MeasurementTool:hitWorld():Vector3?
	local camera=workspace.CurrentCamera
	if not camera then return nil end
	local mouse=UserInputService:GetMouseLocation()
	local ray=camera:ViewportPointToRay(mouse.X,mouse.Y)
	local params=RaycastParams.new()
	params.FilterType=Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances={self.solidRoot}
	local hit=workspace:Raycast(ray.Origin,ray.Direction*1500,params)
	if hit then
		return SurfaceSnap.pointOnPlane(hit.Position,hit.Instance.Position,
			hit.Normal)
	end
	if math.abs(ray.Direction.Y)<0.00001 then return nil end
	local t=-ray.Origin.Y/ray.Direction.Y
	if t<0 then return nil end
	return SurfaceSnap.pointOnPlane(
		ray.Origin+ray.Direction*t,Vector3.zero,Vector3.yAxis)
end
function MeasurementTool:click():number?
	if not self.active then return nil end
	local current=self:hitWorld()
	if not current then return nil end
	if not self.pointA or self.secondGui.Enabled then
		self:reset()
		self.pointA=current
		self.first.CFrame=CFrame.new(current)
		self.firstGui.Enabled=true
		return nil
	end
	local pointA=self.pointA
	if (current-pointA).Magnitude<0.0001 then return nil end
	self.second.CFrame=CFrame.new(current)
	self.secondGui.Enabled=true
	self.line.CFrame=CFrame.lookAt(pointA,current)
	self.line.Length=(current-pointA).Magnitude
	self.line.Visible=true
	self.lineOrigin.CFrame=CFrame.new((pointA+current)/2)
	self.label.Text=string.format("%.1f mm",(current-pointA).Magnitude*280)
	self.labelGui.Enabled=true
	return (current-pointA).Magnitude*280
end
function MeasurementTool:destroy()
	self:reset()
	self.firstGui:Destroy()
	self.secondGui:Destroy()
	self.labelGui:Destroy()
	self.root:Destroy()
end
return MeasurementTool
