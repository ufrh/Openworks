--!strict
-- Versioned transport envelope, shared by client/server.
local Protocol={}
Protocol.Version=1
Protocol.Events={
	ModeChanged="ModeChanged",
	ComponentOperation="ComponentOperation",
	ComponentSnapshot="ComponentSnapshot",
}
function Protocol.isEnvelope(value:any):boolean
	return type(value)=="table" and value.version==Protocol.Version
		and type(value.action)=="string"
		and type(value.requestId)=="string"
end
return Protocol
