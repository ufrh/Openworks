--!strict
-- Q2 client document boundary. FORGE is the transport and the server owns
-- manufacturing history. The CAD UI only handles a local validated mirror.
local DocumentBridge={}
DocumentBridge.__index=DocumentBridge

function DocumentBridge.new(document:any,remote:any)
 local self=setmetatable({document=document,remote=remote},DocumentBridge)
 if remote then self:attach() end
 return self
end

function DocumentBridge:request(action:string,...):(boolean,any)
 local remote=self.remote
 if not remote then return false,"FORGE document service is unavailable" end
 local method=remote[action]
 if type(method)~="function" then
  return false,"Missing FORGE document endpoint: "..action
 end
 local ok,accepted,response=pcall(method,remote,...)
 if not ok then return false,tostring(accepted) end
 return accepted==true,response
end

function DocumentBridge:adopt(ok:boolean,snapshot:any):(boolean,string?)
 if not ok then return false,tostring(snapshot) end
 local component,err=self.document:adoptSnapshot(snapshot)
 return component~=nil,err
end

function DocumentBridge:attach()
 local document=self.document
 local bridge=self
 function document:addOperation(component,kind,data)
  return bridge:adopt(bridge:request("ApplyOperation",
   component.id,component.revision,kind,data))
 end
 function document:setOperationEnabled(component,id,enabled)
  return bridge:adopt(bridge:request("SetOperationEnabled",
   component.id,component.revision,id,enabled))
 end
 function document:removeOperation(component,id)
  return bridge:adopt(bridge:request("RemoveOperation",
   component.id,component.revision,id))
 end
 function document:undoOperation(component)
  return bridge:adopt(bridge:request("UndoOperation",
   component.id,component.revision))
 end
 function document:editNode(component,index,field,axis,value)
  return bridge:adopt(bridge:request("EditNode",
   component.id,component.revision,index,field,axis,value))
 end
 function document:setNotes(component,notes)
  return bridge:adopt(bridge:request("SetNotes",
   component.id,component.revision,notes))
 end
 function document:removeComponent(id)
  local component=self.components[id]
  if not component then return false,"Component not found" end
  local ok,err=bridge:request("DeleteComponent",id,component.revision)
  if not ok then return false,err end
  -- This is the original Document method on the metatable. Its return
  -- value is nil; the client wrapper returns explicit success instead.
  local Document=require(game:GetService("ReplicatedStorage")
   :WaitForChild("Openworks"):WaitForChild("FORM").Document)
  Document.removeComponent(self,id)
  return true,nil
 end
 function document:restoreSnapshot(component,snapshot)
  return bridge:adopt(bridge:request("RestoreRevision",
   component.id,component.revision,snapshot.revision))
 end
end

function DocumentBridge:createSketchBody(name:string,worldOrigin:Vector3,
 editOrigin:Vector3,size:Vector3,points:{Vector2},depth:number)
 if self.remote then
  local ok,snapshot=self:request("CreateSketchBody",
   name,worldOrigin,editOrigin,size,points,depth)
  if not ok then return nil,snapshot end
  return self.document:adoptSnapshot(snapshot)
 end
 local body,reason=self.document:createSketchBody(name,editOrigin,size,points,depth)
 if body then body.worldOrigin=worldOrigin end
 return body,reason
end

function DocumentBridge:commitTransform(component:any,revision:number,
 index:number,mode:string,snap:number):(boolean,string?)
 if not self.remote then return true,nil end
 local node=component.nodes[index]
 if not node then return false,"Transform node no longer exists" end
 local ok,snapshot=self:request("ApplyTransform",component.id,
  revision,index,node.position,node.size,node.rotation,
  mode=="Scale",mode=="Rotate",snap)
 if ok then return self:adopt(true,snapshot) end
 -- Rejected transforms restore the server's current document copy.
 local recovered,authoritative=self:request("GetSnapshot",component.id)
 if recovered then self.document:adoptSnapshot(authoritative) end
 return false,tostring(snapshot)
end

return DocumentBridge
