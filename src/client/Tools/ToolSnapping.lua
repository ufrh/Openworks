--!strict
local SurfaceSnap=require(script.Parent.Snapping.SurfaceSnap)
local Snapping={}
Snapping.pointOnPlane=SurfaceSnap.pointOnPlane
Snapping.mm=SurfaceSnap.mm
Snapping.Increment=SurfaceSnap.Increment
return Snapping
