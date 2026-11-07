--!strict
-- Run on the Studio CLIENT command bar. No existing components are needed.
local Players=game:GetService("Players")
local client=Players.LocalPlayer.PlayerScripts:WaitForChild("Openworks")
local Grid=require(client.Experience.Visuals.GridOverlay)
local Sketch=require(client.Tools.Sketch.SketchEditor)
local playerGui=Players.LocalPlayer.PlayerGui
local grid=Grid.new(playerGui)
local corner=Vector3.new(0,200,0)
local size=Vector3.new(2,1,2)
grid:update(corner,size)
grid:setVisible(true)
local camera={
 setSketchMode=function()end,setView=function()end,
 frameBounds=function()end,snapNow=function()end,
}
local sketch=Sketch.new(playerGui,camera,function() return false,"test only" end,
 function()end,function()end)
sketch:start(nil,"First",{corner=corner,size=size})
sketch.points={Vector2.new(-0.4,-0.3),Vector2.new(0.4,-0.3)}
sketch:render()
local gridY=grid.origin.Position.Y+grid.lines[1].CFrame.Position.Y
local stroke=sketch.lines[1]
local dot=sketch.dots[1]
assert(stroke and dot,"Sketch path / vertices were not rendered")
assert(math.abs(stroke.CFrame.Position.Y-gridY)<0.0005,
 "Sketch line is floating above the construction grid")
assert(math.abs(dot.CFrame.Position.Y-gridY)<0.0005,
 "Sketch vertex is floating above the construction grid")
assert(dot.Radius<=0.013,
 "Vertex marker is too large for precision grid drawing")
sketch:destroy()
grid:destroy()
print("OPENWORKS SKETCH GRID PASS: drawn path and small vertices are flush with workspace grid")
