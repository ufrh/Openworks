--!strict
-- Q4 persistent manufacturing documents. Real DataStore access belongs
-- exclusively to the server, with bounded JSON and explicit error reporting.
local DataStoreService=game:GetService("DataStoreService")
local RunService=game:GetService("RunService")
local Codec=require(script.Parent.DocumentCodec)
local Store={}
Store.__index=Store
local NAME="OPENWORKS_MANUFACTURING_V1"
local RETRIES=3
function Store.new()
 local ok,result=pcall(function()
  return DataStoreService:GetDataStore(NAME)
 end)
 return setmetatable({
  dataStore=if ok then result else nil,
  lastError=if ok then nil else tostring(result),
 },Store)
end
function Store:load(userId:number):(any?,string?)
 if not self.dataStore then return nil,self.lastError or "DataStore unavailable" end
 local key="u:"..userId
 for attempt=1,RETRIES do
  local ok,raw=pcall(function()return self.dataStore:GetAsync(key)end)
  if ok then
   if raw==nil then return nil,nil end
   if type(raw)~="string" then return nil,"Unsupported saved document format" end
   local decoded,payload=pcall(Codec.decode,raw)
   if decoded and type(payload)=="table" and payload.version==1 then
    return payload,nil
   end
   return nil,"Saved payload failed integrity/format validation"
  end
  self.lastError=tostring(raw)
  if attempt<RETRIES then task.wait(attempt*.25) end
 end
 return nil,self.lastError
end
function Store:save(userId:number,payload:any):(boolean,string?)
 if not self.dataStore then
  return false,self.lastError or "DataStore unavailable"
 end
 local ok,json=pcall(Codec.encode,payload)
 if not ok then return false,tostring(json) end
 local key="u:"..userId
 for attempt=1,RETRIES do
  local success,result=pcall(function()
   return self.dataStore:UpdateAsync(key,function(old)
    -- Atomic update avoids clobbering a revision with an older timestamp
    -- from a delayed save within the same server session.
    if type(old)=="string" then
     local parsed,oldPayload=pcall(Codec.decode,old)
     if parsed and type(oldPayload)=="table"
      and oldPayload.sessionId==payload.sessionId
      and type(oldPayload.sequence)=="number"
      and oldPayload.sequence>payload.sequence then
      return nil
     end
    end
    return json
   end)
  end)
  if success then
   if result==nil then return false,"Save superseded by newer session revision" end
   self.lastError=nil
   return true,nil
  end
  self.lastError=tostring(result)
  if attempt<RETRIES then task.wait(attempt*.4) end
 end
 return false,self.lastError
end
return Store
