--!strict
local Context={}
function Context.new(spec:any)
 assert(spec and spec.document and spec.camera and spec.snapping,
  "Tool context requires document, camera and snapping")
 return table.freeze({
  document=spec.document,camera=spec.camera,snapping=spec.snapping,
  selection=spec.selection,submit=spec.submit,visuals=spec.visuals,
 })
end
return Context
