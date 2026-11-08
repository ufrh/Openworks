--!strict
-- OpenWorks boots on the original FORGE 4.4.1 server lifecycle.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local FORGE=require(ReplicatedStorage:WaitForChild("FORGE"))
local ServerBridge=require(script.Parent:WaitForChild("FORGE")
 :WaitForChild("Kernel"):WaitForChild("Networking"):WaitForChild("ServerBridge"))
local bridge=ServerBridge.new()
local ok,err=xpcall(function()
 local services=script:WaitForChild("Services")
 FORGE.Start({Bridge=bridge,Roots={services}})
end,debug.traceback)
if not ok then error("[OPENWORKS] FORGE server startup failed: "..tostring(err)) end
print("[OPENWORKS] FORGE "..tostring(FORGE.Version).." SERVER READY")
game:BindToClose(function()
 local docs=FORGE:GetService("OpenWorksDocuments")
 if docs and docs.SaveAll then docs:SaveAll() end
 FORGE.Shutdown()
end)
