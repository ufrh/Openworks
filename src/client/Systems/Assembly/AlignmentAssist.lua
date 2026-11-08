--!strict
-- Force-limited, temporary alignment. Matching does NOT install hardware,
-- retain two bodies, or create a persistent mechanical relationship.
local Matcher=require(game:GetService("ReplicatedStorage")
 :WaitForChild("Openworks"):WaitForChild("Assembly").FeatureMatcher)
local Assist={}
Assist.__index=Assist
local function featureFrame(part:BasePart,component:any,
 feature:any,primaryAxis:boolean):CFrame
 local source=part:GetAttribute("OWSourceLocalFrame")
 if typeof(source)~="CFrame" then source=CFrame.identity end
 local frame=Matcher.frame(feature) -- Z is the bore axis for lateral force
 if primaryAxis then
  local axis=feature.componentLocalAxis.Unit
  local y=axis:Cross(Vector3.yAxis)
  if y.Magnitude<.02 then y=axis:Cross(Vector3.zAxis) end
  y=y.Unit
  frame=CFrame.fromMatrix(feature.componentLocalCenter,axis,y,
   axis:Cross(y).Unit)
 end
 return source:Inverse()*frame
end
function Assist.new()
 return setmetatable({objects={},active=nil,enabled=true,force=450},Assist)
end
function Assist:release()
 for _,obj in ipairs(self.objects) do
  if obj.Parent then obj:Destroy() end
 end
 table.clear(self.objects)
 self.active=nil
end
function Assist:guide(partA:BasePart,partB:BasePart,
 componentA:any,componentB:any,
 featuresA:{any},featuresB:{any}):(any?,string?)
 if not self.enabled then self:release() return nil,"Disabled" end
 if partA==partB or partA.Anchored or partB.Anchored then
  self:release() return nil,"Both components must be freely simulated"
 end
 -- The world poses used by Matcher are local-component poses, not
 -- the manufactured Part's source-local CSG offset.
 local sourceA=partA:GetAttribute("OWSourceLocalFrame")
 local sourceB=partB:GetAttribute("OWSourceLocalFrame")
 if typeof(sourceA)~="CFrame" then sourceA=CFrame.identity end
 if typeof(sourceB)~="CFrame" then sourceB=CFrame.identity end
 local poseA=partA.CFrame*sourceA:Inverse()
 local poseB=partB.CFrame*sourceB:Inverse()
 local result=Matcher.pattern(featuresA,featuresB,poseA,poseB,1.25)
 if not result then self:release() return nil,"No compatible nearby holes" end
 local match=result.pairs[1]
 if self.active and self.active.a==partA and self.active.b==partB
  and self.active.fa==match.a.id and self.active.fb==match.b.id then
  return result,nil
 end
 self:release()
 local a=Instance.new("Attachment")
 a.Name="OW_AlignmentProbe"
 a.CFrame=featureFrame(partA,componentA,match.a,false)
 a.Parent=partA
 local b=Instance.new("Attachment")
 b.Name="OW_AlignmentTarget"
 b.CFrame=featureFrame(partB,componentB,match.b,false)
 b.Parent=partB
 local translate=Instance.new("AlignPosition")
 translate.Name="OW_TemporaryLateralAlignment"
 translate.Attachment0=a
 translate.Attachment1=b
 translate.RigidityEnabled=false
 translate.ForceLimitMode=Enum.ForceLimitMode.PerAxis
 translate.ForceRelativeTo=Enum.ActuatorRelativeTo.Attachment0
 -- The local Z axis is the bore axis: zero axial force leaves insertion
 -- and seating entirely to collision and the user's applied movement.
 translate.MaxAxesForce=Vector3.new(self.force,self.force,0)
 translate.MaxVelocity=2
 translate.Responsiveness=10
 translate.ReactionForceEnabled=false
 translate.Parent=partA
 -- The orientation aligner has its own X-axis-aligned attachment pair.
 -- AlignPosition needs bore=Z for zero axial force; AlignOrientation
 -- PrimaryAxisOnly needs bore=X to leave twist physically unconstrained.
 local ra=Instance.new("Attachment")
 ra.Name="OW_BoreAxisGuideA"
 ra.CFrame=featureFrame(partA,componentA,match.a,true)
 ra.Parent=partA
 local rb=Instance.new("Attachment")
 rb.Name="OW_BoreAxisGuideB"
 rb.CFrame=featureFrame(partB,componentB,match.b,true)
 rb.Parent=partB
 local orient=Instance.new("AlignOrientation")
 orient.Name="OW_TemporaryAxisAlignment"
 orient.Attachment0=ra
 orient.Attachment1=rb
 orient.RigidityEnabled=false
 orient.PrimaryAxisOnly=true -- Never force twist for a single hole pair
 orient.MaxTorque=math.max(80,self.force*.6)
 orient.MaxAngularVelocity=4
 orient.Responsiveness=10
 orient.Parent=partA
 self.objects={a,b,ra,rb,translate,orient}
 self.active={a=partA,b=partB,fa=match.a.id,fb=match.b.id}
 return result,nil
end
function Assist:Destroy()self:release()end
return Assist
