--!strict
-- Client Studio Command Bar smoke test for FORM's adornment-only previews.
-- Run in a Play Solo CLIENT after the newest dev branch has synced.
-- This does not test GeometryService, only visualizer construction,
-- correct attachment placement, and safe animation cleanup.
local Players=game:GetService("Players")
local player=Players.LocalPlayer
assert(player,"Run in Roblox Studio's client Command Bar (Play Solo)")
local client=player:WaitForChild("PlayerScripts"):WaitForChild("Openworks")
local Visualizer=require(client:WaitForChild("ToolVisualizer"))
local visualizer=Visualizer.new(player:WaitForChild("PlayerGui"))
local pose=CFrame.identity
local top=Vector3.new(0,0.5,0)
local size=Vector3.new(1,1,1)

visualizer:drillFace(pose,top,Vector3.yAxis,0.15,0.20,false,
	size.Magnitude,size)
assert(visualizer.lineCount==40,
	"Idle drill must draw ONLY the 40-segment entrance ring")
assert((visualizer.labelPoint.Position-(top+Vector3.new(0,0.147,0))).Magnitude<0.001,
	"Dimension badge is not anchored beside the drill position")
visualizer:animateDrill(pose,top,Vector3.yAxis,0.15,0.20,false,size)
assert(visualizer:isAnimating(),"Drill animation did not begin")
visualizer:update(0.25)
assert(visualizer.lineCount>40,"Animated drill depth rails are missing")
visualizer:update(1)
assert(not visualizer:isAnimating(),"Drill animation was not cleaned up")

local file={
	a=Vector3.new(-0.5,0.5,-0.5),b=Vector3.new(0.5,0.5,-0.5),
	normalA=Vector3.yAxis,normalB=-Vector3.zAxis,
	width=0.06,segments=4,
}
visualizer:animateFile(pose,file)
visualizer:update(0.2)
assert(visualizer:isAnimating() and visualizer.lineCount>=3,
	"File animation did not render a scraping stroke")
visualizer:update(1)
assert(not visualizer:isAnimating(),"File animation did not finish")

local polygon={
	Vector3.new(-0.25,0.5,-0.25),Vector3.new(0.25,0.5,-0.25),
	Vector3.new(0.25,0.5,0.25),Vector3.new(-0.25,0.5,0.25),
}
visualizer:animateInset(pose,polygon,Vector3.yAxis,0.18)
visualizer:update(0.2)
assert(visualizer.lineCount==4,"Inset did not render its four moving edges")
visualizer:stopAnimation()
assert(not visualizer:isAnimating() and visualizer.lineCount==0,
	"Changing tools must immediately clear adornments")

visualizer:animateSketch(pose,{size=size},{
	points={Vector2.new(-0.2,-0.2),Vector2.new(0.2,-0.2),
		Vector2.new(0.2,0.2),Vector2.new(-0.2,0.2)},
	mode="Remove",depth=0.25,
})
visualizer:update(0.4)
assert(visualizer.lineCount>0,"Sketch path animation missing")
visualizer:destroy()
print("FORM ToolVisualizer: drill, file, inset, sketch and cleanup smoke checks passed")
