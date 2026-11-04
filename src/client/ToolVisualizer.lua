--!strict
-- FORM fabrication previews. Adornments render overlays, never physical Parts.
-- One invisible, non-queryable world anchor supplies the local frame used by
-- all LineHandle/BoxHandle/CylinderHandle/SphereHandle adornments.
local Visualizer={}
Visualizer.__index=Visualizer
local CYAN=Color3.fromRGB(95,217,220)
local AMBER=Color3.fromRGB(245,177,105)
local GREEN=Color3.fromRGB(125,223,175)
local MAX_LINES=128

local function adorn(class:string,name:string,anchor:BasePart,parent:Instance)
	local a=Instance.new(class)
	a.Name=name
	a.Adornee=anchor
	a.AlwaysOnTop=false
	a.Color3=CYAN
	a.Transparency=0.06
	a.Visible=false
	a.Parent=parent
	return a
end
local function lineBetween(line:LineHandleAdornment,a:Vector3,b:Vector3,
	color:Color3?,thickness:number?)
	local delta=b-a
	if delta.Magnitude<0.00001 then line.Visible=false return end
	-- CFrame of a LineHandleAdornment points its local -Z axis at the target.
	line.CFrame=CFrame.lookAt(a,b)
	line.Length=delta.Magnitude
	line.Thickness=thickness or 2
	line.Color3=color or CYAN
	line.Visible=true
end

function Visualizer.new(playerGui:PlayerGui)
	local folder=Instance.new("Folder")
	folder.Name="FORM_FabricationAdornments"
	folder.Parent=playerGui
	local anchor=Instance.new("Part")
	anchor.Name="FORM_AdornmentOrigin"
	anchor.Size=Vector3.one*0.05
	anchor.CFrame=CFrame.identity
	anchor.Transparency=1
	anchor.Anchored=true
	anchor.CanCollide=false
	anchor.CanTouch=false
	anchor.CanQuery=false
	anchor.CastShadow=false
	anchor.Parent=workspace

	local lines={}
	for i=1,MAX_LINES do
		table.insert(lines,adorn("LineHandleAdornment","Guide_"..i,anchor,folder))
	end
	local box=adorn("BoxHandleAdornment","RemovalVolume",anchor,folder)
	local cylinder=adorn("CylinderHandleAdornment","CylindricalRemoval",anchor,folder)
	local perimeter=adorn("CylinderHandleAdornment","DrillPerimeter",anchor,folder)
	perimeter.Height=0.004
	perimeter.Angle=360
	perimeter.Color3=CYAN
	perimeter.Transparency=0
	local marker=adorn("SphereHandleAdornment","ToolCenter",anchor,folder)
	marker.Radius=0.014
	marker.Transparency=0.1

	local label=Instance.new("BillboardGui")
	label.Name="ToolDimensionBadge"
	label.Adornee=anchor
	label.AlwaysOnTop=true
	label.Size=UDim2.fromOffset(196,26)
	label.Enabled=false
	label.Parent=playerGui
	local display=Instance.new("TextLabel")
	display.Size=UDim2.fromScale(1,1)
	display.BackgroundColor3=Color3.fromRGB(31,39,46)
	display.BackgroundTransparency=0.1
	display.TextColor3=Color3.fromRGB(233,244,245)
	display.Font=Enum.Font.Code
	display.TextSize=12
	display.Parent=label
	local corner=Instance.new("UICorner")
	corner.CornerRadius=UDim.new(0,5)
	corner.Parent=display
	return setmetatable({root=folder,anchor=anchor,lines=lines,lineCount=0,
		box=box,cylinder=cylinder,perimeter=perimeter,marker=marker,
		label=label,display=display},Visualizer)
end

function Visualizer:hide()
	for _,line in ipairs(self.lines) do line.Visible=false end
	self.lineCount=0
	self.box.Visible=false
	self.cylinder.Visible=false
	self.perimeter.Visible=false
	self.marker.Visible=false
	self.label.Enabled=false
end

function Visualizer:guide(a:Vector3,b:Vector3,color:Color3?,thickness:number?)
	if self.lineCount>=#self.lines then return end
	self.lineCount+=1
	lineBetween(self.lines[self.lineCount],a,b,color,thickness)
end

function Visualizer:caption(position:Vector3,text:string)
	-- BillboardGui follows the one shared anchor through world offset,
	-- allowing all tool guides to remain nonphysical Adornments.
	self.label.StudsOffsetWorldSpace=position+Vector3.new(0,0.32,0)
	self.display.Text=text
	self.label.Enabled=true
end

local function boxCorners(cf:CFrame,size:Vector3)
	local h=size/2
	local result={}
	for _,x in ipairs({-1,1}) do
		for _,y in ipairs({-1,1}) do
			for _,z in ipairs({-1,1}) do
				table.insert(result,cf:PointToWorldSpace(Vector3.new(x*h.X,y*h.Y,z*h.Z)))
			end
		end
	end
	return result
end

function Visualizer:volume(frame:CFrame,size:Vector3,shape:Enum.PartType,
	caption:string,color:Color3?)
	self:hide()
	local tint=color or AMBER
	if shape==Enum.PartType.Cylinder then
		-- CylinderHandleAdornment's axis is local Y; incoming cylinder
		-- frame is from a Roblox Part whose long axis is local X.
		self.cylinder.CFrame=frame*CFrame.Angles(0,0,math.pi/2)
		self.cylinder.Radius=math.max(size.Y,size.Z)*0.5
		self.cylinder.Height=size.X
		self.cylinder.Angle=360
		self.cylinder.Color3=tint
		self.cylinder.Transparency=0.82
		self.cylinder.Visible=true
	else
		self.box.CFrame=frame
		self.box.Size=size
		self.box.Color3=tint
		self.box.Transparency=0.86
		self.box.Visible=true
		-- Twelve crisp boundaries are more legible than filled Parts.
		local corners=boxCorners(frame,size)
		for _,pair in ipairs({
			{1,2},{3,4},{5,6},{7,8},
			{1,3},{2,4},{5,7},{6,8},
			{1,5},{2,6},{3,7},{4,8},
		}) do
			self:guide(corners[pair[1]],corners[pair[2]],tint,1.3)
		end
	end
	self:caption(frame.Position,caption)
end

function Visualizer:drill(pose:CFrame,node,x:number,z:number,
	diameter:number,depth:number,through:boolean)
	local top=node.size.Y/2
	local penetration=if through then node.size.Y+0.08
		else math.min(depth,node.size.Y)+0.04
	local centerY=if through then 0 else top-penetration/2+0.04
	self:volume(pose*CFrame.new(x,centerY,z)*CFrame.Angles(0,0,math.pi/2),
		Vector3.new(penetration,diameter,diameter),Enum.PartType.Cylinder,
		string.format("Ø %.0f mm  ·  %s",diameter*280,
			if through then "THROUGH" else string.format("%.0f mm",depth*280)),CYAN)
	local topPoint=pose:PointToWorldSpace(Vector3.new(x,top+0.02,z))
	self.perimeter.CFrame=pose*CFrame.new(x,top+0.02,z)
	self.perimeter.Radius=diameter/2
	self.perimeter.InnerRadius=math.max(0,diameter/2-math.clamp(diameter*0.08,0.005,0.02))
	self.perimeter.Visible=true
	self:caption(topPoint,self.display.Text)
end

function Visualizer:drillFace(pose:CFrame,origin:Vector3,normal:Vector3,
	diameter:number,depth:number,through:boolean,maxDepth:number)
	local outward=pose:VectorToWorldSpace(normal).Unit
	local start=pose:PointToWorldSpace(origin)
	local penetration=if through then maxDepth*2+0.08 else depth+0.04
	local center=start-outward*(penetration/2-0.04)
	self:volume(CFrame.lookAt(center,center-outward)*CFrame.Angles(0,math.pi/2,0),
		Vector3.new(penetration,diameter,diameter),Enum.PartType.Cylinder,
		string.format("Ø %.0f mm · %s",diameter*280,
			if through then "THROUGH" else string.format("%.0f mm",depth*280)),CYAN)
	-- Ring local Y axis follows the outward face normal.
	self.perimeter.CFrame=CFrame.lookAt(start+outward*0.018,start-outward)
		*CFrame.Angles(math.pi/2,0,0)
	self.perimeter.Radius=diameter/2
	self.perimeter.InnerRadius=math.max(0,diameter/2-math.clamp(diameter*0.08,0.005,0.02))
	self.perimeter.Visible=true
	self:caption(start,self.display.Text)
end

function Visualizer:inset(pose:CFrame,node,margin:number,depth:number)
	local width=node.size.X-margin*2
	local length=node.size.Z-margin*2
	if width<=0 or length<=0 then self:hide() return end
	local penetration=math.min(depth,node.size.Y)+0.04
	self:volume(pose*CFrame.new(0,node.size.Y/2-penetration/2+0.04,0),
		Vector3.new(width,penetration,length),Enum.PartType.Block,
		string.format("INSET %.0f mm · DEPTH %.0f mm",margin*280,depth*280))
end

function Visualizer:grooveFace(pose:CFrame,a:Vector3,b:Vector3,
	normal:Vector3,width:number,depth:number,through:boolean,maxDepth:number)
	local forward=b-a
	if forward.Magnitude<0.02 then self:hide() return end
	local outward=normal.Unit
	local right=outward:Cross(forward.Unit).Unit
	local back=right:Cross(outward).Unit
	local penetration=if through then maxDepth*2+0.08 else depth+0.04
	local center=(a+b)/2-outward*(penetration/2-0.04)
	self:volume(pose*CFrame.fromMatrix(center,right,outward,back),
		Vector3.new(width,penetration,forward.Magnitude+width),Enum.PartType.Block,
		string.format("%s %.0f × %.0f mm",
			if through then "KERF" else "GROOVE",width*280,depth*280))
end

function Visualizer:groove(pose:CFrame,node,a:Vector2,b:Vector2,width:number,depth:number)
	local vector=Vector3.new(b.X-a.X,0,b.Y-a.Y)
	if vector.Magnitude<0.02 then self:hide() return end
	local penetration=math.min(depth,node.size.Y)+0.04
	local center=Vector3.new((a.X+b.X)/2,node.size.Y/2-penetration/2+0.04,
		(a.Y+b.Y)/2)
	self:volume(pose*CFrame.lookAt(center,center+vector),
		Vector3.new(width,penetration,vector.Magnitude+width),Enum.PartType.Block,
		string.format("GROOVE %.0f × %.0f mm",width*280,depth*280))
end

function Visualizer:meshEdge(part:BasePart,edge,width:number,
	interior:boolean?,normalA:Vector3?,normalB:Vector3?,
	_taperA:boolean?,_taperB:boolean?,segments:number?)
	self:hide()
	local a=part.CFrame:PointToWorldSpace(edge.a)
	local b=part.CFrame:PointToWorldSpace(edge.b)
	local tint=if interior then GREEN else CYAN
	self:guide(a,b,tint,2.8)
	if normalA and normalB then
		local n1=part.CFrame:VectorToWorldSpace(normalA).Unit
		local n2=part.CFrame:VectorToWorldSpace(normalB).Unit
		local dot=n1:Dot(n2)
		local count=segments or 1
		if count>1 and math.abs(dot)<0.12 then
			local offset=(n1+n2)*width
			for i=0,count do
				local angle=i/count*math.pi*0.5
				local radial=(n1*math.cos(angle)+n2*math.sin(angle))*width
				local shift=radial-offset
				self:guide(a+shift,b+shift,tint,1.4)
			end
			self:caption((a+b)/2,string.format("ROUND FILE · %.0f mm · %d SEG",
				width*280,count))
			return
		end
		if math.abs(dot)<0.84 then
			local dirA=(n1*dot-n2).Unit
			local dirB=(n2*dot-n1).Unit
			local sign=if interior then -1 else 1
			local p1,p2=a+dirA*width*sign,a+dirB*width*sign
			local q1,q2=b+dirA*width*sign,b+dirB*width*sign
			self:guide(p1,q1,tint,1.6)
			self:guide(p2,q2,tint,1.6)
			self:guide(p1,p2,tint,1)
			self:guide(q1,q2,tint,1)
		end
	end
	self:caption((a+b)/2,string.format("%s · %.0f mm",
		if interior then "INSIDE FILE" else "FILE EDGE",width*280))
end

function Visualizer:meshFace(part:BasePart,loop:{Vector3},margin:number,depth:number)
	self:hide()
	local center=Vector3.zero
	for i,p in ipairs(loop) do
		local q=loop[i%#loop+1]
		local a=part.CFrame:PointToWorldSpace(p)
		local b=part.CFrame:PointToWorldSpace(q)
		self:guide(a,b,CYAN,2)
		center+=a
	end
	self:caption(center/#loop,string.format("FACE INSET · %.0f / %.0f mm",
		margin*280,depth*280))
end

function Visualizer:file(pose:CFrame,node,edge:string,width:number)
	self:hide()
	local hx,hy,hz=node.size.X/2,node.size.Y/2,node.size.Z/2
	local a,b
	if edge=="X+" then a,b=Vector3.new(hx,hy,-hz),Vector3.new(hx,hy,hz)
	elseif edge=="X-" then a,b=Vector3.new(-hx,hy,-hz),Vector3.new(-hx,hy,hz)
	elseif edge=="Z+" then a,b=Vector3.new(-hx,hy,hz),Vector3.new(hx,hy,hz)
	else a,b=Vector3.new(-hx,hy,-hz),Vector3.new(hx,hy,-hz) end
	local worldA,worldB=pose:PointToWorldSpace(a),pose:PointToWorldSpace(b)
	self:guide(worldA,worldB,CYAN,2.8)
	self:caption((worldA+worldB)/2,string.format("FILE %s · %.0f mm",edge,width*280))
end

function Visualizer:destroy()
	self.root:Destroy()
	self.label:Destroy()
	self.anchor:Destroy()
end
return Visualizer
