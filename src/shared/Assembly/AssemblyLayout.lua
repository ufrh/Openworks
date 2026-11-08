--!strict
local Layout={}
Layout.Center=Vector3.new(120,200,0)
function Layout.validFrame(value:any):boolean
 if typeof(value)~='CFrame' then return false end
 for _,n in ipairs({value:GetComponents()}) do
  if n~=n or math.abs(n)>100000 then return false end
 end
 local x,y,z=value.XVector,value.YVector,value.ZVector
 return math.abs(x.Magnitude-1)<1e-4 and math.abs(y.Magnitude-1)<1e-4
  and math.abs(z.Magnitude-1)<1e-4 and math.abs(x:Dot(y))<1e-4
  and (x:Cross(y)-z).Magnitude<1e-4 and (value.Position-Layout.Center).Magnitude<500
end
function Layout.initial(index:number,component:any):CFrame
 local n=component.nodes[1]
 local r=n.rotation
 return CFrame.new(Layout.Center+Vector3.new(((index-1)%3-1)*12,
  n.size.Magnitude*.5+.2,math.floor((index-1)/3)*12))
  *CFrame.fromOrientation(math.rad(r.X),math.rad(r.Y),math.rad(r.Z))
end
return Layout
