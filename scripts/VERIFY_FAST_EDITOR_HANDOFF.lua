--!strict
-- Run in Studio CLIENT Command Bar after syncing dev.
-- The local construction grid MUST use stable adornment Instances and
-- move by one anchor CFrame instead of rewriting their geometry each frame.
local Players=game:GetService("Players")
local player=Players.LocalPlayer
assert(player,"Run on client")
local client=player:WaitForChild("PlayerScripts"):WaitForChild("Openworks")
local GridOverlay=require(client.GridOverlay)
local CharacterMode=require(client.CharacterMode)
local grid=GridOverlay.new(player.PlayerGui)
local size=Vector3.new(1,1000/280,.75)
local first=Vector3.new(4,0,-3)
grid:update(first,size)
grid:setVisible(true)
assert(grid.lineCount>0)
local count=grid.lineCount
local firstLine=grid.lines[1]
local localLine=firstLine.CFrame
local newPos=Vector3.new(9,0,2)
grid:update(newPos,size)
assert(grid.corner==newPos)
assert(grid.lineCount==count)
assert(grid.lines[1]==firstLine)
assert(grid.lines[1].CFrame==localLine,
	"Moving placement grid must never regenerate individual line geometry")
assert(grid.origin.CFrame.Position==newPos,
	"Grid translation should change only the origin CFrame")
grid:setVisible(true)
assert(grid.lines[1]==firstLine,"Redundant visible=true must preserve line identity")
grid:setVisible(false)
grid:clear()
assert(#grid.lines==0)
grid:destroy()
local mode=CharacterMode.new(player)
local previous=mode.editing
local start=os.clock()
mode:setEditing(true)
assert(os.clock()-start<.05,
	"Character-to-CAD handoff must not yield waiting for PlayerModule")
mode:setEditing(false)
assert(not mode.editing)
print("FORM fast handoff: immediate controls transition, one-transform grid motion and no duplicate visuals")
