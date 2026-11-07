--!strict
-- Client-side authoring precision, independent of FORM's fixed manufacturing
-- precision (1 mm) and from other players' snap preferences.
local Quantize=require(game:GetService("ReplicatedStorage")
 :WaitForChild("Openworks"):WaitForChild("FORM").Quantize)
local Snapping={}
Snapping.Default=0.05
Snapping.Min=0.01
Snapping.Max=2
Snapping.Presets={0.01,0.025,0.05,0.1,0.25,0.5,1,2}
local increment=Snapping.Default
local changed=Instance.new("BindableEvent")
function Snapping.get():number return increment end
function Snapping.set(value:number):(boolean,string?)
 if typeof(value)~="number" or not Quantize.isFinite(value)
  or value<Snapping.Min or value>Snapping.Max then
  return false,"Snap must be between 2.8 mm and 560 mm"
 end
 local rounded=math.round(value*280)/280
 -- Retain common 0.05/0.1 increments exactly to preserve existing
 -- grid positions; arbitrary typed millimeter values use 1 mm precision.
 increment=if math.abs(value-rounded)<0.001 then rounded else value
 changed:Fire(increment)
 return true,nil
end
function Snapping.connect(callback:(number)->())
 return changed.Event:Connect(callback)
end
function Snapping.snap(value:number):number
 return Quantize.snap(value,increment)
end
function Snapping.snapVector(value:Vector3):Vector3
 return Quantize.vector(value,increment)
end
return Snapping
