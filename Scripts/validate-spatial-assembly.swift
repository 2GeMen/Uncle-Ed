import Cocoa
import SceneKit
import simd

var results=[[String:Any]]()
func distance(_ a:SCNVector3,_ b:SCNVector3)->Double{hypot(hypot(Double(a.x-b.x),Double(a.y-b.y)),Double(a.z-b.z))}
for model in ["nds","gba","gbc","psp","3ds"] {
 let scene=SCNScene()
 guard let rig=SpatialMachine(model:model,theme:3),let media=SpatialMachine.media(model:model,cover:nil,tint:0x476A58) else{fatalError("Missing shared geometry: "+model)}
 rig.setDisplayFocus(0.28);rig.setDisplayFocus(1)
 scene.rootNode.addChildNode(rig.root);scene.rootNode.addChildNode(media)
 rig.root.eulerAngles=SCNVector3(0.12,-0.20,0);let source=SCNVector3(0,3.8,0.65)
 func pose(_ t:CGFloat){rig.update(openness:0,loading:t,held:[],frame:nil);if model=="psp"{rig.placePSPMedia(media,source:source,progress:t)}else{rig.placeCartridge(media,source:source,progress:t)}}
 pose(0.579999);let before=media.worldPosition;pose(0.580001);let after=media.worldPosition
 var row:[String:Any]=["model":model,"alignmentContinuous":distance(before,after)<0.0001,"internalParts":rig.internalParts]
 row["screenBindingsSurviveFocus"]=rig.mechanicalState["liveScreenBindings"]
 let dummy=SCNNode();dummy.name="model:0"
 let body=SCNNode(geometry:SCNBox(width:1,height:1,length:0.2,chamferRadius:0.02));dummy.addChildNode(body)
 let halo=SCNNode(geometry:SCNPlane(width:2,height:2));halo.categoryBitMask=2;dummy.addChildNode(halo)
 row["goldOverlayDoesNotOwnPreviewPress"]=SpatialMachine.previewTarget(halo)==nil && SpatialMachine.previewTarget(body)===dummy
 var onAxis=true,orientationAligned=true,monotonic=true,lastY=Double.greatestFiniteMagnitude
 for i in 58...100 {let progress=CGFloat(i)/100;pose(progress)
  if model != "psp",let slot=rig.slot {
   let local=slot.convertPosition(media.worldPosition,from:nil)
   if progress>0.58{onAxis = onAxis && abs(Double(local.x))<0.00001 && abs(Double(local.z))<0.00001;orientationAligned = orientationAligned && abs(simd_dot(media.simdWorldOrientation.vector,simd_mul(slot.simdWorldOrientation,simd_quatf(angle:SpatialMachine.cartridgeFacesBack(model) ? Float.pi:0,axis:SIMD3<Float>(0,1,0))).vector))>0.99999;monotonic = monotonic && Double(local.y)<=lastY+0.00001;lastY=Double(local.y)}
  }
 }
 row["slotAxisAligned"]=onAxis;row["orientationAligned"]=orientationAligned;row["insertionMonotonic"]=monotonic
 func corners(in target:SCNNode)->[SCNVector3]{let b=media.boundingBox;return [b.min.x,b.max.x].flatMap{x in [b.min.y,b.max.y].flatMap{y in [b.min.z,b.max.z].map{z in media.convertPosition(SCNVector3(x,y,z),to:target)}}}}
 if model=="gbc" {
  var floorY = -Double.greatestFiniteMagnitude
  rig.device.enumerateChildNodes{n,_ in if let g=n.geometry as? SCNBox,abs(g.width-2.58)<0.001,abs(g.height-0.06)<0.001{floorY=Double(n.convertPosition(SCNVector3(0,g.height/2,0),to:rig.device).y)}}
  let bottom=corners(in:rig.device).map{Double($0.y)}.min()!
  let top=corners(in:rig.device).map{Double($0.y)}.max()!
  row["cartridgeTopFlushWithCase"]=abs(top-2.90)<0.02
  row["cartridgeTop"]=top
  row["pocketFloorClearance"]=bottom-floorY;row["clearsPocketFloor"]=floorY.isFinite && bottom-floorY>0
 }
 if model=="gba",let pad=rig.device.childNode(withName:"dpad",recursively:true),let b=rig.device.childNode(withName:"key:0",recursively:true),let surround=rig.device.childNode(withName:"gba-lcd-surround",recursively:true) {
  func xExtent(_ n:SCNNode)->(Double,Double){let box=n.boundingBox;let xs=[box.min.x,box.max.x].flatMap{x in [box.min.y,box.max.y].flatMap{y in [box.min.z,box.max.z].map{z in Double(n.convertPosition(SCNVector3(x,y,z),to:rig.device).x)}}};return (xs.min()!,xs.max()!)}
  let frame=xExtent(surround),cross=xExtent(pad),button=xExtent(b)
  row["padToScreenSurround"]=frame.0-cross.1;row["bToScreenSurround"]=button.0-frame.1
  row["controlsClearSurround"]=frame.0-cross.1>0.17 && button.0-frame.1>0.20
  let front=rig.device.childNode(withName:"front-shell",recursively:true)!,rim=rig.device.childNode(withName:"gba-rolled-sidewall",recursively:true)!
  row["portableFrontTriangles"]=(front.geometry?.sources(for:.vertex).first?.vectorCount ?? 0)>50
  if let g=front.geometry,let source=g.sources(for:.vertex).first,let element=g.elements.first {
   func component(_ vertex:Int,_ axis:Int)->Double{let offset=source.dataOffset+vertex*source.dataStride+axis*source.bytesPerComponent;return source.data.withUnsafeBytes{p in source.bytesPerComponent==4 ? Double(p.loadUnaligned(fromByteOffset:offset,as:Float.self)):p.loadUnaligned(fromByteOffset:offset,as:Double.self)}}
   let points=(0..<source.vectorCount).map{CGPoint(x:component($0,0),y:component($0,1))}
   func index(_ i:Int)->Int{element.data.withUnsafeBytes{p in switch element.bytesPerIndex{case 1:return Int(p.loadUnaligned(fromByteOffset:i,as:UInt8.self));case 2:return Int(p.loadUnaligned(fromByteOffset:i*2,as:UInt16.self));default:return Int(p.loadUnaligned(fromByteOffset:i*4,as:UInt32.self))}}}
   func cross(_ a:CGPoint,_ b:CGPoint)->CGFloat{a.x*b.y-a.y*b.x}
   let polygon=abs(points.indices.reduce(CGFloat.zero){$0+cross(points[$1],points[($1+1)%points.count])})/2
   let triangles=(0..<element.primitiveCount).reduce(CGFloat.zero){sum,t in let a=points[index(t*3)],b=points[index(t*3+1)],c=points[index(t*3+2)];return sum+abs(cross(CGPoint(x:b.x-a.x,y:b.y-a.y),CGPoint(x:c.x-a.x,y:c.y-a.y)))/2}
   row["frontTrianglesDoNotOverlap"]=abs(triangles-polygon)<0.00001
  }
  row["smoothRolledRim"]=(rim.geometry?.sources(for:.vertex).first?.vectorCount ?? 0)>400
  row["rimThinnerThanBatteryCradle"]=Double(rim.boundingBox.max.z-rim.boundingBox.min.z)<0.66 && rig.device.childNode(withName:"gba-battery-cradle",recursively:true) != nil
  let mediaProbe=SCNNode();mediaProbe.name="card:0";let label=SCNNode(geometry:SCNPlane(width:1,height:1));mediaProbe.addChildNode(label)
  row["mediaLabelCanStartInspection"]=SpatialMachine.previewTarget(label)===mediaProbe
 }
 if model=="gba" || model=="gbc" {
  let specimen=SpatialMachine.media(model:model,cover:nil,tint:0x446655)!
  let front=specimen.childNode(withName:"cartridge-front",recursively:true)!,rear=specimen.childNode(withName:"cartridge-rear",recursively:true)!
  let pin=specimen.childNode(withName:"edge-contact:1",recursively:true)!
  let bottom=Double(pin.position.y)-Double((pin.geometry as? SCNPlane)?.height ?? 0)/2
  row["frontAndRearShieldContacts"]=Double(front.boundingBox.min.y)<bottom && Double(rear.boundingBox.min.y)<bottom
  let normal=pin.convertVector(SCNVector3(0,0,1),to:specimen)
  row["copperCannotFaceFront"]=Double(normal.z)<(-0.99) && pin.geometry?.firstMaterial?.isDoubleSided==false
  var contacts=0;media.enumerateChildNodes{n,_ in if n.name?.hasPrefix("edge-contact:")==true{contacts+=1}}
  let bounds=media.boundingBox,depth=Double(bounds.max.z-bounds.min.z),width=Double(bounds.max.x-bounds.min.x)
  row["single32ContactEdge"]=contacts==32;row["backFacesOutward"]=SpatialMachine.cartridgeFacesBack(model);row["physicalShellDepth"]=depth/width>0.12 && depth/width<0.16
 }
 if model != "psp" {
  let specimen=SpatialMachine.media(model:model,cover:nil,tint:0x446655)!,pin=SpatialMachine.media(model:model,cover:nil,tint:0x446655)!.childNode(withName:"edge-contact:8",recursively:true)!
  let q=pin.position
  func first(_ a:SCNVector3,_ b:SCNVector3)->String? {specimen.hitTestWithSegment(from:a,to:b,options:[SCNHitTestOption.searchMode.rawValue:SCNHitTestSearchMode.all.rawValue]).first?.node.name}
  row["frontHidesContacts"]=first(SCNVector3(q.x,q.y,5),SCNVector3(q.x,q.y,-5)) != "edge-contact:8"
  let rear=first(SCNVector3(q.x,q.y,-5),SCNVector3(q.x,q.y,5))
  row["rearContactExposureCorrect"]=(model=="gba" || model=="gbc") ? rear=="cartridge-rear":rear=="edge-contact:8"
  if model=="gba" || model=="gbc" {
   let h=CGFloat(specimen.boundingBox.max.y-specimen.boundingBox.min.y)
   row["contactsVisibleThroughBottomMouth"]=first(SCNVector3(q.x,-h*1.50,-0.90),SCNVector3(q.x,q.y,q.z+0.005))=="edge-contact:8"
  }
 }
 if model=="psp",let tray=rig.mediaTray {
  var avoidsDoor=true,opensOutward=true
  for i in 58...100{pose(CGFloat(i)/100);let local=corners(in:tray);avoidsDoor = avoidsDoor && local.map{Double($0.z)}.max()! < -0.025
   if i<68{let top=rig.device.convertPosition(tray.convertPosition(SCNVector3(0,2.66,0),to:nil),from:nil);opensOutward = opensOutward && Double(top.z)<Double(tray.position.z)-0.2}
  }
  let labelNormal=media.convertVector(SCNVector3(0,0,1),to:tray)
  let b=media.boundingBox
  row["labelFacesRearCover"]=Double(labelNormal.z)/sqrt(Double(labelNormal.x*labelNormal.x+labelNormal.y*labelNormal.y+labelNormal.z*labelNormal.z))>0.999
  row["protectedUMDProfile"]=Double(b.max.z-b.min.z)>0.16 && Double(b.max.z-b.min.z)<0.20
  let rotor=media.childNode(withName:"umd-rotor",recursively:true)!,rotorBounds=rotor.boundingBox
  row["thinInternalRotor"]=Double(rotorBounds.max.z-rotorBounds.min.z)<0.03
  SpatialMachine.spinSeatedDisc(media);row["carrierRemainsStationary"]=media.action(forKey:"disc-spin")==nil && rotor.action(forKey:"disc-spin") != nil
  let eyes=rig.device.childNodes.filter{$0.name=="single-metal-strap-eyelet"}
  row["singleLeftStrapEyelet"]=eyes.count==1 && eyes[0].position.x<0
  row["readSideHasDiffraction"]=media.childNode(withName:"disc-read-surface",recursively:true)?.geometry?.firstMaterial?.shaderModifiers?[.surface] != nil
  row["discNeverCrossesDoor"]=avoidsDoor;row["doorOpensOutward"]=opensOutward
  pose(1)
  let points=corners(in:tray),minX=points.map{Double($0.x)}.min()!,maxX=points.map{Double($0.x)}.max()!,minY=points.map{Double($0.y)}.min()!,maxY=points.map{Double($0.y)}.max()!
  var side=Double.greatestFiniteMagnitude,stop=Double.greatestFiniteMagnitude,top=Double.greatestFiniteMagnitude,floorZ = -Double.greatestFiniteMagnitude
  for n in tray.childNodes{guard let g=n.geometry as? SCNBox else{continue}
   if abs(g.width-0.035)<0.001{side=min(side,n.position.x>0 ? Double(n.position.x)-g.width/2-maxX:minX-Double(n.position.x)-g.width/2)}
   if abs(g.height-0.045)<0.001{stop=minY-Double(n.position.y)-g.height/2}
   if abs(g.height-2.66)<0.001{top=Double(n.position.y)+g.height/2-maxY}
  }
  for n in rig.device.childNodes{if let g=n.geometry as? SCNBox,abs(g.width-2.80)<0.001,abs(g.height-2.54)<0.001{floorZ=Double(n.position.z)-g.length/2}}
  let front=corners(in:rig.device).map{Double($0.z)}.max()!,back=floorZ-front
  row["guideSideClearance"]=side;row["guideStopClearance"]=stop;row["doorTopClearance"]=top;row["carrierBackClearance"]=back
  row["clearsGuideCage"]=[side,stop,top,back].allSatisfy{$0.isFinite && $0>0 && $0<1}
  var readerZ=Double.greatestFiniteMagnitude
  rig.device.enumerateChildNodes{n,_ in guard n.name?.hasPrefix("optical-drive")==true || n.parent?.name?.hasPrefix("optical-drive")==true,let g=n.geometry else{return};let b=g.boundingBox
   for x in [b.min.x,b.max.x]{for y in [b.min.y,b.max.y]{for z in [b.min.z,b.max.z]{readerZ=min(readerZ,Double(n.convertPosition(SCNVector3(x,y,z),to:rig.device).z))}}}
  }
  row["discClearsReaderHardware"]=readerZ-front>0.015 && readerZ-front<0.2
  row["readerClearance"]=readerZ-front

 }
 if model != "psp" {
  rig.update(openness:1,loading:0,held:[4,7],frame:nil);let pressed=rig.mechanicalState
  rig.update(openness:1,loading:0,held:[4,5],frame:nil);let opposed=rig.mechanicalState
  rig.update(openness:1,loading:0,held:[],frame:nil);let released=rig.mechanicalState
  let tilt=pressed["cross"] as! [Double],cancelled=opposed["cross"] as! [Double],rest=released["cross"] as! [Double]
  row["rigidPadTilts"]=tilt.count==2 && abs(tilt[0])>0.08 && abs(tilt[1])>0.08
  row["opposingDirectionsCancel"]=cancelled.allSatisfy{abs($0)<0.00001};row["padReturnsToRest"]=rest.allSatisfy{abs($0)<0.00001}
 }
 if model != "gbc" {
  rig.update(openness:0,loading:0,held:[],frame:nil)
  let controls=[10,11].compactMap{rig.device.childNode(withName:"key:"+String($0),recursively:true)}
  row["physicalShouldersExist"]=rig.mechanicalState["physicalShoulders"] as? Int == 2
  row["previewHidesShoulderProxies"]=controls.count==2 && controls.allSatisfy{$0.isHidden}
  rig.update(openness:1,loading:0,held:[10],frame:nil,operating:true)
  row["operationShouldersMatchModel"]=(model=="psp" || model=="gba") ? controls.allSatisfy{$0.isHidden}:controls.allSatisfy{!$0.isHidden}
  if let left=rig.device.childNode(withName:"physical-shoulder:10",recursively:true){row["physicalShoulderPivots"]=model=="gba" ? Double(left.eulerAngles.x)>0.07:Double(left.eulerAngles.x)<(-0.09)}
 }
 if model=="gba" {
  rig.update(openness:1,loading:0,held:[],frame:nil)
  let seats=rig.device.childNodes.filter{$0.name=="gba-shoulder-seat"}
  var attached=seats.count==2,downward=true,clearsShell=true,maxGap = -Double.greatestFiniteMagnitude
  func elevations(_ node:SCNNode,_ x:CGFloat,_ z:CGFloat)->[Double]{
   let a=node.convertPosition(SCNVector3(x,3,z),from:rig.device),b=node.convertPosition(SCNVector3(x,0,z),from:rig.device)
   return node.hitTestWithSegment(from:a,to:b,options:[SCNHitTestOption.searchMode.rawValue:SCNHitTestSearchMode.all.rawValue,SCNHitTestOption.backFaceCulling.rawValue:false]).filter{$0.node===node}.map{Double(node.convertPosition($0.localCoordinates,to:rig.device).y)}
  }
  for id in [10,11]{let sign:CGFloat=id==11 ? 1:-1
   guard let cap=rig.device.childNode(withName:"physical-shoulder:"+String(id),recursively:true),let seat=seats.first(where:{($0.position.x>0)==(id==11)}) else{attached=false;continue}
   for x:CGFloat in [2.30,2.60,2.90]{for z:CGFloat in [-0.64,-0.52,-0.28,-0.10]{let bottom=elevations(cap,sign*x,z).min(),top=elevations(seat,sign*x,z).max();if let bottom,let top{maxGap=max(maxGap,bottom-top);attached=attached && bottom-top<0.004}else{attached=false}
    let shellNames=["front-shell","gba-rolled-sidewall","rear-shell-with-cartridge-pocket"]
    let shellTop=rig.device.childNodes.filter{shellNames.contains($0.name ?? "")}.flatMap{elevations($0,sign*x,z)}.max()
    if let surface=elevations(cap,sign*x,z).max(),let shellTop{clearsShell=clearsShell && surface>shellTop-0.006}}}
   let before=elevations(cap,sign*2.60,-0.10).max() ?? 0
   rig.update(openness:1,loading:0,held:[id],frame:nil,operating:true)
   let after=elevations(cap,sign*2.60,-0.10).max() ?? before
   downward=downward && after<before-0.025
   rig.update(openness:1,loading:0,held:[],frame:nil)
  }
  row["shoulderShellDoesNotCutCap"]=clearsShell;row["shoulderSeatContinuous"]=attached;row["shoulderMaximumSeatGap"]=maxGap;row["shoulderFrontTravelsDown"]=downward
 }
 if model=="nds" || model=="3ds" {
  rig.update(openness:0,loading:0,held:[],frame:nil)
  let carrier=rig.device.childNode(withName:"internal:lid-optical-carrier",recursively:true)!
  func rangeZ(_ n:SCNNode)->(Double,Double){let box=n.boundingBox;let zs=[box.min.x,box.max.x].flatMap{x in [box.min.y,box.max.y].flatMap{y in [box.min.z,box.max.z].map{z in Double(n.convertPosition(SCNVector3(x,y,z),to:rig.device).z)}}};return(zs.min()!,zs.max()!)}
  let ceiling=rangeZ(carrier).0,floor=(0..<10).compactMap{rig.controlNode($0)}.map{rangeZ($0).1}.max()!
  row["closedLidClearsLowerControls"]=ceiling>floor+0.025
  row["lidHasStereoAssembly"]=rig.internalParts.filter{$0=="internal:lid-stereo-speaker"}.count==2
 }
 if model=="psp" {
  rig.update(openness:1,loading:0,held:[],frame:nil,axis:.zero,operating:true);let rest=rig.mechanicalState["stickPose"] as! [Double]
  rig.update(openness:1,loading:0,held:[],frame:nil,axis:CGPoint(x:1,y:-1),operating:true);let moved=rig.mechanicalState["stickPose"] as! [Double]
  row["nubHasDirectionalThrow"]=moved[0]-rest[0]>0.10 && moved[1]-rest[1]>0.10 && abs(moved[2]-rest[2])>0.05
  rig.update(openness:1,loading:0,held:[],frame:nil,axis:.zero,operating:true);let released=rig.mechanicalState["stickPose"] as! [Double]
  row["nubReturnsToCentre"]=zip(rest,released).allSatisfy{abs($0.0-$0.1)<0.00001}
 }
 if model=="psp" {
  rig.placePSPMedia(media,source:source,progress:0,sourceScale:1.8);let start=Double(media.scale.x)
  rig.placePSPMedia(media,source:source,progress:0.499999,sourceScale:1.8);let before=Double(media.scale.x)
  rig.placePSPMedia(media,source:source,progress:0.500001,sourceScale:1.8);let after=Double(media.scale.x)
  row["enlargedPreviewConvergesToTray"]=abs(start-1.8)<0.00001 && abs(after-0.9)<0.00001 && abs(before-after)<0.00001
 }else{
  rig.placeCartridge(media,source:source,progress:0,sourceScale:2);let start=Double(media.scale.x)
  rig.placeCartridge(media,source:source,progress:0.58,sourceScale:2)
  row["enlargedPreviewConvergesToSlot"]=abs(start-2)<0.00001 && abs(Double(media.scale.x)-1)<0.00001
  rig.update(openness:0,loading:0,held:[],frame:nil)
  let box=rig.root.boundingBox
  let front=[box.min.x,box.max.x].flatMap{x in [box.min.y,box.max.y].flatMap{y in [box.min.z,box.max.z].map{z in Double(rig.root.convertPosition(SCNVector3(x,y,z),to:nil).z)}}}.max()!
  var clears=true
  for step in 0...44{rig.placeCartridge(media,source:source,progress:CGFloat(step)/100,sourceScale:2);let b=media.boundingBox;let back=[b.min.x,b.max.x].flatMap{x in [b.min.y,b.max.y].flatMap{y in [b.min.z,b.max.z].map{z in Double(media.convertPosition(SCNVector3(x,y,z),to:nil).z)}}}.min()!;clears = clears && back>front+0.02}
  row["enlargedRotationClearsMachine"]=clears
 }
 let flags=row.filter{ $0.value is Bool }.map{ $0.value as! Bool };row["passed"]=flags.allSatisfy{$0};results.append(row)
}
let json=try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys])
if CommandLine.arguments.count>1{try json.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))}
print(String(decoding:json,as:UTF8.self))
exit(results.allSatisfy{$0["passed"] as? Bool == true} ? 0:1)
