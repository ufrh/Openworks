--!strict
local Alignment={}
local function rotation(a:Vector3,b:Vector3):CFrame
 local dot=math.clamp(a:Dot(b),-1,1)
 if dot>1-1e-9 then return CFrame.identity end
 local axis=a:Cross(b)
 if axis.Magnitude<1e-8 then
  axis=a:Cross(if math.abs(a.Y)<.9 then Vector3.yAxis else Vector3.xAxis)
 end
 return CFrame.fromAxisAngle(axis.Unit,math.acos(dot))
end
function Alignment.solve(kind:string,pose:CFrame,a:any,b:any,offset:number?):(CFrame?,string?)
 local gap=offset or 0
 if gap~=gap or math.abs(gap)>1000 then return nil,'Invalid offset' end
 if kind=='Concentric' and (a.kind~='Axis' or b.kind~='Axis') then
  return nil,'Concentric requires two cylindrical axes'
 end
 if (kind=='Coincident' or kind=='Distance') and (a.kind~='Plane' or b.kind~='Plane') then
  return nil,'Select two source planes'
 end
 if kind~='Concentric' and kind~='Coincident' and kind~='Parallel' and kind~='Distance' then
  return nil,'Unknown alignment'
 end
 if kind=='Concentric' and a.diameter and b.diameter then
  local shaft=if a.id=='shaft' then a elseif b.id=='shaft' then b else nil
  local bore=if shaft==a then b else a
  if shaft and bore.feature and shaft.diameter+1/280>bore.diameter then
   return nil,'Shaft too large; minimum diametral clearance is 1 mm'
  end
 end
 local target=b.direction
 if kind=='Coincident' or kind=='Distance' then target=-target
 elseif a.direction:Dot(target)<0 then target=-target end
 local turn=rotation(a.direction,target)
 local result=CFrame.new(a.point)*turn*CFrame.new(-a.point)*pose
 if kind=='Parallel' then return result,nil end
 local difference=b.point-a.point
 if kind=='Concentric' then
  return result+(difference-b.direction*difference:Dot(b.direction)),nil
 end
 return result+b.direction*(difference:Dot(b.direction)+gap),nil
end
return Alignment
