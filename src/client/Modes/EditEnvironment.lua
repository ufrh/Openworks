--!strict
-- Fully enclosed, fixed-size blue CAD room. The *component workspace* is
-- centered at the chamber origin, not resting on its floor. All six faces
-- are opaque and do not cast shadows, collide, or intercept editor raycasts.
local Environment={}
Environment.__index=Environment
Environment.Size=Vector3.new(40,20,40)
Environment.Center=Vector3.new(0,200,0)

local CYAN=Color3.fromRGB(84,229,255)
local WALL=Color3.fromRGB(21,43,72)
local FLOOR=Color3.fromRGB(27,53,79)
local CEILING=Color3.fromRGB(16,33,58)
local BACKDROP=Color3.fromRGB(18,38,67)

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
 local center=Environment.Center
 local size=Environment.Size
 local hx,hy,hz=size.X*0.5,size.Y*0.5,size.Z*0.5
 local slab=0.18

 -- Six completely opaque, overlapping faces. The old walls were 72%
 -- transparent and the ceiling 91% transparent, exposing the actual sky.
 -- Geometry overlaps at the corners to remove light-colored seam gaps.
 visual(root,"ChamberFloor",Vector3.new(size.X+slab*2,slab,size.Z+slab*2),
  center-Vector3.new(0,hy,0),FLOOR,Enum.Material.SmoothPlastic,0)
 visual(root,"BlueCeiling",Vector3.new(size.X+slab*2,slab,size.Z+slab*2),
  center+Vector3.new(0,hy,0),CEILING,Enum.Material.SmoothPlastic,0)
 for _,sign in ipairs({-1,1}) do
  visual(root,"BlueWallX",Vector3.new(slab,size.Y+slab*2,size.Z+slab*2),
   center+Vector3.new(sign*hx,0,0),WALL,Enum.Material.SmoothPlastic,0)
  visual(root,"BlueWallZ",Vector3.new(size.X+slab*2,size.Y+slab*2,slab),
   center+Vector3.new(0,0,sign*hz),WALL,Enum.Material.SmoothPlastic,0)
 end

 -- Soft neon structural edges make the room readable without replacing
 -- its opaque six-sided enclosure. No exterior Lighting/Sky mutation.
 local thickness=0.065
 for _,dx in ipairs({-hx,hx}) do
  for _,dz in ipairs({-hz,hz}) do
   visual(root,"CyanPillar",Vector3.new(thickness,size.Y,thickness),
    center+Vector3.new(dx,0,dz),CYAN,Enum.Material.Neon,0.38)
  end
  for _,dy in ipairs({-hy,hy}) do
   visual(root,"CyanEdgeZ",Vector3.new(thickness,thickness,size.Z),
    center+Vector3.new(dx,dy,0),CYAN,Enum.Material.Neon,0.55)
  end
 end
 for _,dz in ipairs({-hz,hz}) do
  for _,dy in ipairs({-hy,hy}) do
   visual(root,"CyanEdgeX",Vector3.new(size.X,thickness,thickness),
    center+Vector3.new(0,dy,dz),CYAN,Enum.Material.Neon,0.55)
  end
 end

 -- A second, much larger blue shell backs up the enclosure in case
 -- camera settings temporarily put the viewpoint outside the room.
 -- It is not the room itself and never determines construction size.
 local radius=500
 visual(root,"SkyBackdrop_Floor",Vector3.new(radius*2,slab,radius*2),
  center+Vector3.new(0,-radius,0),BACKDROP,Enum.Material.SmoothPlastic,0)
 visual(root,"SkyBackdrop_Ceiling",Vector3.new(radius*2,slab,radius*2),
  center+Vector3.new(0,radius,0),BACKDROP,Enum.Material.SmoothPlastic,0)
 for _,sign in ipairs({-1,1}) do
  visual(root,"SkyBackdrop_X",Vector3.new(slab,radius*2,radius*2),
   center+Vector3.new(sign*radius,0,0),BACKDROP,Enum.Material.SmoothPlastic,0)
  visual(root,"SkyBackdrop_Z",Vector3.new(radius*2,radius*2,slab),
   center+Vector3.new(0,0,sign*radius),BACKDROP,Enum.Material.SmoothPlastic,0)
 end

 -- Lights are inside the closed room, with shadows disabled. These make
 -- metallic manufactured parts readable without an opening in the roof.
 for _,spec in ipairs({
  {Vector3.new(-9,6,-7),Color3.fromRGB(238,247,255),1.15},
  {Vector3.new(11,4,9),Color3.fromRGB(115,204,239),0.85},
 }) do
  local source=visual(root,"StudioLightSource",Vector3.one*0.05,
   center+spec[1],WALL,Enum.Material.SmoothPlastic,1)
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
