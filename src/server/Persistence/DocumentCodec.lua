--!strict
-- DataStore payload codec: Roblox Vector2, Vector3 and CFrame values
-- become finite JSON-safe value types. Never serialize Instances/meshes.
local HttpService=game:GetService("HttpService")
local Codec={}
Codec.MaxBytes=1024*1024
local function finite(n:number):boolean
 return n==n and n~=math.huge and n~=-math.huge
end
local function encode(value:any,depth:number):any
 if depth>16 then error("Document nesting exceeds save limit") end
 local t=typeof(value)
 if t=="nil" or t=="boolean" or t=="string" then return value end
 if t=="number" then
  assert(finite(value),"Cannot persist non-finite number")
  return value
 end
 if t=="Vector2" then return {__ow="v2",x=value.X,y=value.Y} end
 if t=="Vector3" then
  return {__ow="v3",x=value.X,y=value.Y,z=value.Z}
 end
 if t=="CFrame" then return {__ow="cf",values={value:GetComponents()}} end
 if t~="table" then error("Unsupported persisted type: "..t) end
 local allNumeric=true
 local count=0
 for k in pairs(value) do
  count+=1
  if type(k)~="number" or k%1~=0 or k<1 then allNumeric=false end
 end
 assert(count<=2048,"Persistence table entry limit")
 if allNumeric and count==#value then
  local result={}
  for i,v in ipairs(value) do result[i]=encode(v,depth+1) end
  return result
 end
 local result={}
 for key,v in pairs(value) do
  assert(type(key)=="string" and #key<=128,
   "Non-array document keys must be strings")
  result[key]=encode(v,depth+1)
 end
 return result
end
local function decode(value:any,depth:number):any
 if depth>16 then error("Persisted payload too deeply nested") end
 if type(value)~="table" then return value end
 if value.__ow=="v2" then return Vector2.new(value.x,value.y) end
 if value.__ow=="v3" then return Vector3.new(value.x,value.y,value.z) end
 if value.__ow=="cf" then
  assert(type(value.values)=="table" and #value.values==12,
   "Invalid saved CFrame")
  return CFrame.new(table.unpack(value.values))
 end
 local result={}
 for key,v in pairs(value) do
  result[key]=decode(v,depth+1)
 end
 return result
end
function Codec.encode(payload:any):string
 local json=HttpService:JSONEncode(encode(payload,0))
 assert(#json<=Codec.MaxBytes,"Save exceeds 1 MiB document limit")
 return json
end
function Codec.decode(text:string):any
 assert(type(text)=="string" and #text<=Codec.MaxBytes,
  "Invalid persisted document length")
 return decode(HttpService:JSONDecode(text),0)
end
return Codec
