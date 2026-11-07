--!strict
-- Fixed-size Edit Chamber plus a much larger client-only blue backdrop.
-- The backdrop is visual ONLY: it neither resizes component workspaces
-- nor casts shadows/blocks sunlight or physical collision.
local Environment={}
Environment.__index=Environment
Environment.Size=Vector3.new(40,20,40)
Environment.Center=Vector3.new(0,200,0)

local CYAN=Color3.fromRGB(84,229,255)
local DEEP=Color3.fromRGB(14,27,48)
local STEEL=Color3.fromRGB(24,47,76)
local SKY=Color3.fromRGB(19,39,67)

local function visual(parent:Instance,name:string,size:Vector3,position:Vector3,
 color:Color3,material:Enum.Material,transparency:number):BasePart
 local part=Instance.new("Part")
 part.Name=name
 part.Size=size
 part.Position=position
 part.Anchored=true
 part.CanCollide=false
 part.CanQuery=false
 part.CanTouch=false
 part.CastShadow=false
 part.Material=material
 part.Color=color
 part.Transparency=transparency
 part.Parent=parent
 return part
end

function Environment.new()
 return setmetatable({root=nil},Environment)
end

function Environment:show()
 if self.root then return end
 local root=Instance.new("Folder")
 root.Name="OPENWORKS_LocalEditChamber"
 root.Parent=workspace
 local c=Environment.Center
 local size=Environment.Size
 local x,z,y=size.X/2,size.Z/2,size.Y
 local slab=0.1

 -- A huge ambient-blue visual box behaves like a local skybox without
 -- changing Lighting.Sky or the appearance of the player's Free world.
 -- Cameras can zoom outside the 40x40x20 decorative chamber and still
 -- see blue, rather than a disconnected outside world.
 local radius=500
 visual(root,"SkyBackdrop_Floor",Vector3.new(radius*2,slab,radius*2),
  c+Vector3.new(0,-radius,0),SKY,Enum.Material.SmoothPlastic,0)
 visual(root,"SkyBackdrop_Ceiling",Vector3.new(radius*2,slab,radius*2),
  c+Vector3.new(0,radius,0),DEEP,Enum.Material.SmoothPlastic,0)
 for _,sign in ipairs({-1,1}) do
  visual(root,"SkyBackdrop_X",Vector3.new(slab,radius*2,radius*2),
   c+Vector3.new(sign*radius,0,0),SKY,Enum.Material.SmoothPlastic,0)
  visual(root,"SkyBackdrop_Z",Vector3.new(radius*2,radius*2,slab),
   c+Vector3.new(0,0,sign*radius),DEEP,Enum.Material.SmoothPlastic,0)
 end

 -- Fixed construction room. Every surface is blue, but walls and roof are
 -- translucent so the CAD camera never hides a manufactured component.
 visual(root,"ChamberFloor",Vector3.new(size.X,slab,size.Z),
  c-Vector3.new(0,slab,0),STEEL,Enum.Material.SmoothPlastic,0.08)
 for _,sign in ipairs({-1,1}) do
  visual(root,"BlueWallX",Vector3.new(slab,y,size.Z),
   c+Vector3.new(sign*x,y/2,0),STEEL,Enum.Material.SmoothPlastic,0.72)
  visual(root,"BlueWallZ",Vector3.new(size.X,y,slab),
   c+Vector3.new(0,y/2,sign*z),STEEL,Enum.Material.SmoothPlastic,0.72)
 end
 visual(root,"BlueCeiling",Vector3.new(size.X,slab,size.Z),
  c+Vector3.new(0,y,0),DEEP,Enum.Material.SmoothPlastic,0.91)

 local thickness=0.065
 for _,dx in ipairs({-x,x}) do
  for _,dz in ipairs({-z,z}) do
   visual(root,"CyanPillar",Vector3.new(thickness,y,thickness),
    c+Vector3.new(dx,y/2,dz),CYAN,Enum.Material.Neon,0.38)
  end
  for _,height in ipairs({0,y}) do
   visual(root,"CyanEdgeZ",Vector3.new(thickness,thickness,size.Z),
    c+Vector3.new(dx,height,0),CYAN,Enum.Material.Neon,0.55)
  end
 end
 for _,dz in ipairs({-z,z}) do
  for _,height in ipairs({0,y}) do
   visual(root,"CyanEdgeX",Vector3.new(size.X,thickness,thickness),
    c+Vector3.new(0,height,dz),CYAN,Enum.Material.Neon,0.55)
  end
 end

 -- Neutral local fill means metallic parts keep their form and highlights
 -- without relying on the outside scene's ambient lighting.
 for _,spec in ipairs({
  {Vector3.new(-9,13,-7),Color3.fromRGB(238,247,255),1.0},
  {Vector3.new(11,10,9),Color3.fromRGB(115,204,239),0.55},
 }) do
  local source=visual(root,"StudioLightSource",Vector3.one*0.05,
   c+spec[1],DEEP,Enum.Material.SmoothPlastic,1)
  local light=Instance.new("PointLight")
  light.Color=spec[2]
  light.Brightness=spec[3]
  light.Range=55
  light.Shadows=false
  light.Parent=source
 end
 self.root=root
end
function Environment:hide()
 if self.root then self.root:Destroy() self.root=nil end
end
function Environment:Destroy() self:hide() end
return Environment
