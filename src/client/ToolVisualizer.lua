--!strict
-- FORM fabrication previews. Adornments render overlays, never physical Parts.
-- One invisible, non-queryable world anchor supplies the local frame used by
-- all LineHandle/BoxHandle/CylinderHandle/SphereHandle adornments.
local Visualizer={}
Visualizer.__index=Visualizer
local CYAN=Color3.fromRGB(45,255,247)
local AMBER=Color3.fromRGB(255,203,71)
local GREEN=Color3.fromRGB(119,255,166)
local MAX_LINES=128

local function adorn(class:string,name:string,anchor:BasePart,parent:Instance)
	local a=Instance.new(class)
	a.Name=name
	a.Adornee=anchor
	a.AlwaysOnTop=class=="LineHandleAdornment"
	a.Color3=CYAN
	a.Transparency=0
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
	line.Thickness=math.max(2.4,thickness or 2.7)
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

	local lines={} -- allocated only while the tool is actually visible
	local box=adorn("BoxHandleAdornment","RemovalVolume",anchor,folder)

	-- A dedicated attachment keeps the badge at the actual tool point.
	-- An absolute-world vector used as a StudsOffset on an origin Part
	-- could appear detached from the hit location at certain camera views.
	local labelPoint=Instance.new("Attachment")
	labelPoint.Name="FORM_DimensionPoint"
	labelPoint.Position=Vector3.zero
	labelPoint.Parent=anchor
	local label=Instance.new("BillboardGui")
	label.Name="ToolDimensionBadge"
	label.Adornee=labelPoint
	label.AlwaysOnTop=true
	label.Size=UDim2.fromOffset(196,26)
	label.Enabled=false
	label.Parent=playerGui
	local display=Instance.new("TextLabel")
	display.Size=UDim2.fromScale(1,1)
	display.BackgroundColor3=Color3.fromRGB(31,39,46)
	display.BackgroundTransparency=0
	display.TextColor3=Color3.new(1,1,1)
	display.Font=Enum.Font.Code
	display.TextSize=14
	display.Parent=label
	local corner=Instance.new("UICorner")
	corner.CornerRadius=UDim.new(0,5)
	corner.Parent=display
	return setmetatable({root=folder,anchor=anchor,lines=lines,lineCount=0,
		box=box,
		label=label,labelPoint=labelPoint,display=display,animation=nil},Visualizer)
end

function Visualizer:hide()
	for _,line in ipairs(self.lines) do line.Visible=false end
	self.lineCount=0
	if self.box then self.box.Visible=false end
	self.label.Enabled=false
end

-- Release actual temporary wireframe Instances at tool/mode boundaries.
-- Idle hovering reuses a small pool; finished effects do not leave any.
function Visualizer:discard()
	self:hide()
	for _,line in ipairs(self.lines) do line:Destroy() end
	table.clear(self.lines)
	if self.box then self.box:Destroy() self.box=nil end
end

function Visualizer:guide(a:Vector3,b:Vector3,color:Color3?,thickness:number?)
	if self.lineCount>=MAX_LINES then return end
	self.lineCount+=1
	local line=self.lines[self.lineCount]
	if not line then
		line=adorn("LineHandleAdornment","Guide_"..self.lineCount,
			self.anchor,self.root)
		self.lines[self.lineCount]=line
	end
	lineBetween(line,a,b,color,thickness)
end

function Visualizer:caption(position:Vector3,text:string)
	-- BillboardGui follows the one shared anchor through world offset,
	-- allowing all tool guides to remain nonphysical Adornments.
	self.labelPoint.Position=position+Vector3.new(0,0.14,0)
	self.label.StudsOffsetWorldSpace=Vector3.zero
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
	-- Tool volume overlays are wireframe-only. Cylinder guides are
	-- drawn by drillWireframe() with actual circles perpendicular to the
	-- drilling axis; a filled CylinderHandleAdornment is never used.
	if shape==Enum.PartType.Block then
		if not self.box then
			self.box=adorn("BoxHandleAdornment","RemovalVolume",
				self.anchor,self.root)
		end
		self.box.CFrame=frame
		self.box.Size=size
		self.box.Color3=tint
		self.box.Transparency=0.63
		self.box.Visible=true
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

-- The idle drill cursor is only a face-aligned ring. The whole bore
-- is revealed during drilling animation so it never leaves long wireframe
-- shafts hanging off the workpiece when hovering.
local CIRCLE_SEGMENTS=40
local function drillBasis(normal:Vector3)
	local axis=normal.Unit
	local reference=if math.abs(axis.Y)<0.9 then Vector3.yAxis else Vector3.xAxis
	local tangent=axis:Cross(reference).Unit
	return tangent,axis:Cross(tangent).Unit
end

local function throughSpan(origin:Vector3,normal:Vector3,
	stockSize:Vector3?,fallback:number):number
	if not stockSize then return fallback end
	local inward=-normal.Unit
	local half=stockSize/2
	local result=math.huge
	for _,axis in ipairs({"X","Y","Z"}) do
		local d=inward[axis]
		if math.abs(d)>1e-6 then
			local limit=if d>0 then half[axis] else -half[axis]
			local distance=(limit-origin[axis])/d
			if distance>0.001 then result=math.min(result,distance) end
		end
	end
	return if result<math.huge then result else fallback
end

function Visualizer:drillWireframe(origin:Vector3,normal:Vector3,
	diameter:number,penetration:number,through:boolean,progress:number?)
	self:hide()
	if normal.Magnitude<0.001 or diameter<=0 then return end
	local axis=normal.Unit
	local u,v=drillBasis(axis)
	local radius=diameter*0.5
	local surface=origin+axis*0.007
	local function circle(center:Vector3,color:Color3,thickness:number)
		for i=0,CIRCLE_SEGMENTS-1 do
			local a=i*2*math.pi/CIRCLE_SEGMENTS
			local b=(i+1)*2*math.pi/CIRCLE_SEGMENTS
			self:guide(center+(u*math.cos(a)+v*math.sin(a))*radius,
				center+(u*math.cos(b)+v*math.sin(b))*radius,color,thickness)
		end
	end
	circle(surface,CYAN,1.65)
	if progress~=nil then
		local amount=math.clamp(progress,0,1)
		local feed=origin-axis*(penetration*amount)
		circle(feed,CYAN:Lerp(AMBER,0.35),1.3)
		-- The four rails show drilling depth only during the action.
		for i=0,3 do
			local angle=i*math.pi/2
			local radial=(u*math.cos(angle)+v*math.sin(angle))*radius
			self:guide(surface+radial,feed+radial,CYAN,0.85)
		end
		-- Two short revolving flutes make the feed/spin visible without
		-- adding any physics tool or interfering with hover raycasts.
		local rotation=amount*math.pi*12
		for _,phi in ipairs({rotation,rotation+math.pi}) do
			local radial=u*math.cos(phi)+v*math.sin(phi)
			self:guide(feed+radial*radius*0.15,feed+radial*radius*0.85,
				AMBER,2.0)
		end
	end
	local status=if through then "THROUGH"
		else string.format("%.0f mm DEEP",penetration*280)
	self:caption(surface,string.format("Ø %.0f mm · %s%s",
		diameter*280,status,if progress then "  ·  DRILLING" else ""))
end

function Visualizer:drill(pose:CFrame,node,x:number,z:number,
	diameter:number,depth:number,through:boolean)
	local origin=pose:PointToWorldSpace(Vector3.new(x,node.size.Y/2,z))
	local penetration=if through then node.size.Y else math.min(depth,node.size.Y)
	self:drillWireframe(origin,pose.UpVector,diameter,penetration,through)
end

function Visualizer:drillFace(pose:CFrame,origin:Vector3,normal:Vector3,
	diameter:number,depth:number,through:boolean,maxDepth:number,stockSize:Vector3?)
	local outward=pose:VectorToWorldSpace(normal).Unit
	local start=pose:PointToWorldSpace(origin)
	local penetration=if through then throughSpan(origin,normal,stockSize,maxDepth)
		else depth
	self:drillWireframe(start,outward,diameter,penetration,through)
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

-- Preview the ACTUAL additive interior fillet arc, not the exterior
-- rounded File profile which cuts in the opposite direction.
function Visualizer:smoothInside(part:BasePart,edge,radius:number,segments:number,
	normalA:Vector3,normalB:Vector3)
	self:hide()
	local cf=part.CFrame
	local a,b=cf:PointToWorldSpace(edge.a),cf:PointToWorldSpace(edge.b)
	local n1=cf:VectorToWorldSpace(normalA).Unit
	local n2=cf:VectorToWorldSpace(normalB).Unit
	self:guide(a,b,GREEN,2.3)
	local previous=nil
	for i=0,segments do
		local t=i/segments*math.pi*0.5
		local offset=n1*radius*(1-math.sin(t))
			+n2*radius*(1-math.cos(t))
		local p,q=a+offset,b+offset
		self:guide(p,q,GREEN,1.4)
		if previous then
			self:guide(previous,p,GREEN,1)
		end
		previous=p
	end
	self:caption((a+b)*0.5,
		string.format("SMOOTH INTERIOR · %.0f mm",radius*280))
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

-- Transient client-only fabrication animation. The actual document
-- operation is already committed; these frames depict tool travel while
-- the asynchronous CSG result is being generated. No physics or meshes.
function Visualizer:isAnimating():boolean
	return self.animation~=nil
end

function Visualizer:stopAnimation()
	self.animation=nil
	self:discard()
end

function Visualizer:animateDrill(pose:CFrame,origin:Vector3,normal:Vector3,
	diameter:number,depth:number,through:boolean,stockSize:Vector3)
	local worldOrigin=pose:PointToWorldSpace(origin)
	local worldNormal=pose:VectorToWorldSpace(normal).Unit
	local penetration=if through then throughSpan(origin,normal,stockSize,stockSize.Magnitude)
		else depth
	self.animation={kind="Drill",elapsed=0,duration=0.85,
		origin=worldOrigin,normal=worldNormal,diameter=diameter,
		penetration=penetration,through=through}
end

function Visualizer:animateFile(pose:CFrame,operation)
	self.animation={kind="File",elapsed=0,duration=0.90,
		a=pose:PointToWorldSpace(operation.a),
		b=pose:PointToWorldSpace(operation.b),
		n1=pose:VectorToWorldSpace(operation.normalA).Unit,
		n2=pose:VectorToWorldSpace(operation.normalB).Unit,
		width=operation.width,segments=operation.segments or 1}
end

function Visualizer:animateInset(pose:CFrame,points:{Vector3},
	normal:Vector3,depth:number)
	local loop={}
	for _,point in ipairs(points) do
		table.insert(loop,pose:PointToWorldSpace(point))
	end
	self.animation={kind="Inset",elapsed=0,duration=0.65,
		loop=loop,normal=pose:VectorToWorldSpace(normal).Unit,depth=depth}
end

function Visualizer:animateSketch(pose:CFrame,node,operation)
	local loop={}
	for _,point in ipairs(operation.points or {}) do
		table.insert(loop,pose:PointToWorldSpace(Vector3.new(
			point.X,node.size.Y/2,point.Y)))
	end
	if #loop<3 then return end
	self.animation={kind="Sketch",elapsed=0,duration=0.80,
		loop=loop,mode=operation.mode,
		depth=operation.depth}
end

function Visualizer:update(dt:number):boolean
	local effect=self.animation
	if not effect then return false end
	effect.elapsed+=math.max(0,dt)
	local t=math.clamp(effect.elapsed/effect.duration,0,1)
	-- Every effect recreates only its visible adornments from the pool.
	-- No additional Parts, Tweens or render connections are allocated.
	if effect.kind=="Drill" then
		local feed=1-(1-t)^3
		self:drillWireframe(effect.origin,effect.normal,
			effect.diameter,effect.penetration,effect.through,feed)
	elseif effect.kind=="File" then
		self:hide()
		local axis=effect.b-effect.a
		if axis.Magnitude>0.001 then
			local direction=axis.Unit
			local width=effect.width
			local n1,n2=effect.n1,effect.n2
			self:guide(effect.a,effect.b,CYAN,1.15)
			-- Four back-and-forth passes across the full selected edge.
			local cycle=(t*4)%1
			local moving=if math.floor(t*4)%2==0 then cycle else 1-cycle
			local position=effect.a+axis*moving
			local previous=nil
			local segments=if effect.segments==1 then 1 else effect.segments
			for i=0,segments do
				local p
				if segments==1 then
					p=position-n1*width
				else
					local theta=i/segments*math.pi*0.5
					p=position-(n1+n2)*width+
						(n1*math.cos(theta)+n2*math.sin(theta))*width
				end
				if previous then self:guide(previous,p,AMBER,2.6) end
				previous=p
				if segments==1 and i==0 then
					self:guide(position-n1*width,position-n2*width,AMBER,2.6)
				end
			end
			self:guide(position-direction*math.min(width*0.6,axis.Magnitude*0.12),
				position+direction*math.min(width*0.6,axis.Magnitude*0.12),AMBER,3)
			self:caption(position,string.format("FILING · %d SEG · %d%%",
				effect.segments,math.round(t*100)))
		end
	elseif effect.kind=="Inset" then
		self:hide()
		local amount=1-(1-t)^2
		local offset=-effect.normal*effect.depth*amount
		local center=Vector3.zero
		for i,a in ipairs(effect.loop) do
			local b=effect.loop[i%#effect.loop+1]
			self:guide(a+offset,b+offset,AMBER,1.9)
			center+=a
		end
		if #effect.loop>0 then
			self:caption(center/#effect.loop+offset,
				string.format("INSET · %.0f mm · %d%%",
					effect.depth*280,math.round(t*100)))
		end
	elseif effect.kind=="Sketch" then
		self:hide()
		local count=#effect.loop
		local completed=t*count
		local middle=Vector3.zero
		for i,a in ipairs(effect.loop) do
			local b=effect.loop[i%count+1]
			local portion=math.clamp(completed-(i-1),0,1)
			if portion>0 then
				self:guide(a,a:Lerp(b,portion),AMBER,2)
			end
			middle+=a
		end
		self:caption(middle/count,string.format("%s PROFILE · %d%%",
			if effect.mode=="Remove" then "SAW" else "EXTRUDE",
			math.round(t*100)))
	end
	if t>=1 then
		self.animation=nil
		-- Destroy the entire transient display, not just its visibility.
		self:discard()
	end
	return true
end

function Visualizer:destroy()
	self.animation=nil
	self:discard()
	self.root:Destroy()
	self.label:Destroy()
	self.anchor:Destroy()
end
return Visualizer
