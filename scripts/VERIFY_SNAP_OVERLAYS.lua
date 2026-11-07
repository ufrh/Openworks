--!strict
-- Run in Roblox Studio CLIENT Command Bar after syncing dev branch.
-- Tests snap math, temporary wireframe disposal, and sketch dot cleanup.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local player=Players.LocalPlayer
assert(player,"Run during Play in the CLIENT Command Bar")
local client=player:WaitForChild("PlayerScripts"):WaitForChild("Openworks")
local FORM=ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM")
local Quantize=require(FORM.Quantize)
local SurfaceSnap=require(client.SurfaceSnap)
local Visualizer=require(client.ToolVisualizer)
local SketchEditor=require(client.SketchEditor)
local GridOverlay=require(client.GridOverlay)

assert(SurfaceSnap.Increment==Quantize.Grid,"Tools must share the 14mm position grid")
assert(math.abs(SurfaceSnap.mm(14.4/280)-14/280)<1e-7,
	"Typed tool dimensions must snap to 1mm")
assert(math.abs(SurfaceSnap.mm(14.7/280)-15/280)<1e-7)

local normal=Vector3.new(1,2,3).Unit
local anchor=Vector3.new(1.23,-2.45,3.5)
local point=anchor+Vector3.new(.12,.07,-.25)
local snapped=SurfaceSnap.pointOnPlane(point,anchor,normal)
assert(math.abs((snapped-anchor):Dot(normal))<1e-5,
	"Surface snap must stay exactly on the manufactured plane")
local tangent=(Vector3.xAxis-normal*Vector3.xAxis:Dot(normal)).Unit
local near=SurfaceSnap.pointOnPlane(snapped+tangent*.004,anchor,normal)
assert((near-snapped).Magnitude<1e-5,
	"Small pointer drift must keep a stable snapped tool center")
local stepped=SurfaceSnap.pointOnPlane(snapped+tangent*.12,anchor,normal)
assert((stepped-snapped).Magnitude>Quantize.Grid,
	"Tool center must advance to the next visible grid increment")

local visual=Visualizer.new(player.PlayerGui)
assert(#visual.lines==0,"No idle fabrication wireframe pool should be allocated")
visual:guide(Vector3.zero,Vector3.zAxis,Color3.new(1,1,1),1)
assert(visual.lineCount==1 and #visual.lines==1 and visual.lines[1].Visible)
assert(visual.lines[1].Thickness>=2.4 and visual.lines[1].AlwaysOnTop)
local stale=visual.lines[1]
visual:discard()
assert(#visual.lines==0 and visual.lineCount==0 and visual.box==nil)
assert(stale.Parent==nil,"Discarded fabrication guide must be Destroyed")
visual:guide(Vector3.zero,Vector3.xAxis)
assert(visual.lineCount==1,"New preview must recreate only active guides")
visual:stopAnimation()
assert(#visual.lines==0,"Changing tool must actually destroy preview lines")
visual:destroy()

local grid=GridOverlay.new(player.PlayerGui)
grid:update(Vector3.zero,Vector3.new(.5,1,.5))
grid:setVisible(true)
assert(grid.lineCount>0)
local oldGrid=grid.lines[1]
grid:clear()
assert(#grid.lines==0 and grid.lineCount==0
	and oldGrid.Parent==nil,"Temporary construction grid must be released")
grid:destroy()

local viewport={
	setSketchMode=function(self,active) self.sketchMode=active end,
}
local editor=SketchEditor.new(player.PlayerGui,viewport,
	function()return true,nil end,function()end,function()end)
local old=Instance.new("LineHandleAdornment")
old.Parent=editor.visuals
old.Visible=true
table.insert(editor.lines,old)
editor.active=true
editor:stop()
assert(not editor.gui.Enabled and #editor.lines==0 and old.Parent==nil,
	"Closing sketch must destroy its transient wireframe, not hide it")
assert(viewport.sketchMode==false)
editor:destroy()
print("FORM snap + overlays: 14mm face grid, 1mm dimensions, no stale wireframe, preview contrast, sketch cleanup passed")
