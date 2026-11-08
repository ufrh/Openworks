--!strict
return function(Alignment,References,Resolver,Layout,Compiler)
 local count=0
 local function check(value,message) assert(value,message) count+=1 end
 local function near(a,b) return (a-b).Magnitude<1e-6 end
 local identity=CFrame.identity
 local a={id='shaft',kind='Axis',point=Vector3.new(3,4,5),direction=Vector3.xAxis,diameter=.1}
 local b={id='hole:1',kind='Axis',point=Vector3.zero,direction=Vector3.yAxis,diameter=.11,feature={}}
 local pose,why=Alignment.solve('Concentric',CFrame.new(a.point),a,b)
 check(pose~=nil,why)
 check(near(pose.Position,Vector3.new(0,4,0)),'Concentric changed insertion depth')
 check(near(pose:VectorToWorldSpace(Vector3.xAxis),Vector3.yAxis),'Axis rotation is incorrect')
 local oversized=table.clone(a) oversized.diameter=.2
 check(Alignment.solve('Concentric',identity,oversized,b)==nil,'Oversized shaft aligned')
 local planeA={kind='Plane',point=Vector3.new(4,5,6),direction=Vector3.xAxis}
 local planeB={kind='Plane',point=Vector3.zero,direction=Vector3.xAxis}
 local coincident=Alignment.solve('Coincident',CFrame.new(planeA.point),planeA,planeB,.25)
 check(near(coincident.Position,Vector3.new(.25,5,6)),'Coincidence offset or in-plane coordinates incorrect')
 check(near(coincident.XVector,-Vector3.xAxis),'Antiparallel face alignment failed')
 local parallel=Alignment.solve('Parallel',CFrame.new(a.point),a,b)
 check(near(parallel.Position,a.point),'Parallel moved reference position')
 local body={id=1,nodes={{kind='Block',size=Vector3.one,rotation=Vector3.zero}},
  operations={{id=1,kind='Drill',x=.5,z=.5,diameter=.11,depth=1,through=true}}}
 local shaft={id=2,nodes={{kind='Cylinder',size=Vector3.new(.1,2,.1)}},operations={}}
 local components={[1]=body,[2]=shaft}
 local poses={['1']=identity,['2']=identity}
 local record={model='BoreSupportV1',bodyId=1,shaftId=2,featureId='hole:1'}
 local relation,reason=Resolver.resolve(record,components,poses)
 check(relation~=nil,reason)
 check(relation.translation==1 and relation.rotation==1 and not relation.retained,'Free shaft acquired axial retention')
 check(Resolver.resolve({kind='Revolute'},components,poses)==nil,'Legacy joint accepted')
 shaft.nodes[1].size=Vector3.new(.12,2,.12)
 check(Resolver.resolve(record,components,poses)==nil,'Oversized support accepted')
 shaft.nodes[1].size=Vector3.new(.1,2,.1)
 poses['2']=CFrame.new(0,4,0)
 check(Resolver.resolve(record,components,poses)==nil,'Disengaged shaft retained')
 poses['2']=identity
 table.insert(body.operations,{kind='Saw',enabled=true})
 check(Resolver.resolve(record,components,poses)==nil,'Modified support wall accepted without validation')
 check(Compiler.compile({},nil,nil,nil,nil)==nil,'Legacy compiler created a joint')
 check(Layout.validFrame(CFrame.new(Layout.Center)),'Valid layout pose rejected')
 check(not Layout.validFrame(CFrame.new(10000,0,0)),'Unbounded pose accepted')
 return count
end
