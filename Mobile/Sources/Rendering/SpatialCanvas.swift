import UIKit
import SceneKit

class SpatialSurface:SCNView {
 let cameraNode=SCNNode()
 override init(frame:CGRect = .zero,options:[String:Any]?=nil){
  super.init(frame:frame,options:options);isUserInteractionEnabled=false;isOpaque=false;backgroundColor = .clear;scene=SCNScene();antialiasingMode = .multisampling4X;preferredFramesPerSecond=60
  cameraNode.camera=SCNCamera();cameraNode.camera?.usesOrthographicProjection=true;cameraNode.camera?.zFar=100;cameraNode.position=SCNVector3(0,0,20);scene!.rootNode.addChildNode(cameraNode);pointOfView=cameraNode
  SpatialMachine.lightStudio(scene!)
  let ambient=SCNNode();ambient.light=SCNLight();ambient.light?.type = .ambient;ambient.light?.intensity=130;scene!.rootNode.addChildNode(ambient)
  let key=SCNNode();key.light=SCNLight();key.light?.type = .directional;key.light?.intensity=460;key.eulerAngles=SCNVector3(-0.45,-0.4,0);scene!.rootNode.addChildNode(key)
  let fill=SCNNode();fill.light=SCNLight();fill.light?.type = .omni;fill.light?.intensity=120;fill.position=SCNVector3(4,-2,8);scene!.rootNode.addChildNode(fill)
 }
 required init?(coder:NSCoder){fatalError()}
}
final class SpatialShowcaseLight:SpatialSurface {
 private let ceremony=SpatialCeremony()
 override init(frame:CGRect = .zero,options:[String:Any]?=nil){super.init(frame:frame,options:options);scene!.rootNode.addChildNode(ceremony.root);cameraNode.camera?.orthographicScale=4.5}
 required init?(coder:NSCoder){fatalError()}
 func show(_ visible:Bool){ceremony.focus(visible);isHidden = !visible;isPlaying=visible;rendersContinuously=visible}
 override func layoutSubviews(){super.layoutSubviews();guard bounds.height>0 else{return};ceremony.fillViewport(width:9*bounds.width/bounds.height,height:9)}
}
final class SpatialCanvas:SpatialSurface {
 private(set) var machine:SpatialMachine?
 private var stateFrame:CGImage?,stateOpen:CGFloat=0,stateLoading:CGFloat=0,stateAxis=CGPoint.zero,stateOperating=false
 private var signature="",flight:SCNNode?,scale:CGFloat=1,held=Set<Int>(),viewport:CGSize = .zero
 var available:Bool{machine != nil}
 func configure(model:DeviceModel,theme:Int){let next=model.rawValue+String(theme);guard signature != next else{return};signature=next;machine?.root.removeFromParentNode();flight?.removeFromParentNode();flight=nil;machine=SpatialMachine(model:model.rawValue,theme:theme);if let machine{scene!.rootNode.addChildNode(machine.root)}}
 func update(layout:MobileLayout,viewport:CGSize,openness:CGFloat,loading:CGFloat,playing:Bool,library:Bool,book:Bool,frame:CGImage?,axis:CGPoint = .zero){
  guard let machine else{return};stateFrame=playing ? frame:nil;stateOpen=openness;stateLoading=loading;stateAxis=axis;stateOperating=playing;self.viewport=viewport;scale=layout.scale;cameraNode.camera?.orthographicScale=Double(viewport.height/(200*scale))
  SCNTransaction.begin();SCNTransaction.disableActions=true
  machine.root.position=world(CGPoint(x:layout.frame.midX,y:layout.frame.midY));machine.root.eulerAngles=SCNVector3(machine.model=="psp" ? Float(0.22*(1-openness)):library ? 0.045:0,machine.model=="psp" ? Float(-0.16*(1-openness)):library ? -0.12:0,book ? Float.pi/2:0)
  machine.update(openness:openness,loading:loading,held:held,frame:playing ? frame:nil,axis:axis,operating:playing);SCNTransaction.commit();let visible=window != nil && !isHidden && superview?.isHidden != true;isPlaying=visible;rendersContinuously=visible;scene?.isPaused = !visible;preferredFramesPerSecond=60
 }
 private func world(_ point:CGPoint)->SCNVector3{SCNVector3(Float((point.x-viewport.width/2)/(100*scale)),Float((viewport.height/2-point.y)/(100*scale)),0)}
 func physicalShoulderRects()->[GameControl:CGRect]{
  guard let machine,machine.model=="psp" || machine.model=="gba" else{return [:]}
  var result=[GameControl:CGRect]()
  for id in [10,11]{guard let n=machine.controlNode(id),let key=GameControl(rawValue:id) else{continue};let b=n.boundingBox
   let points=[b.min.x,b.max.x].flatMap{x in [b.min.y,b.max.y].flatMap{y in [b.min.z,b.max.z].map{z in projectPoint(n.convertPosition(SCNVector3(x,y,z),to:nil))}}}
   let xs=points.map{CGFloat($0.x)},ys=points.map{CGFloat($0.y)};result[key]=CGRect(x:xs.min()!,y:ys.min()!,width:xs.max()!-xs.min()!,height:ys.max()!-ys.min()!).insetBy(dx:-5,dy:-8)
  };return result
 }
 func setHeld(_ value:Set<GameControl>){held=Set(value.map{$0.rawValue});machine?.update(openness:stateOpen,loading:stateLoading,held:held,frame:stateFrame,axis:stateAxis,operating:stateOperating)}
 func updateAxis(_ axis:CGPoint){stateAxis=axis;machine?.update(openness:stateOpen,loading:stateLoading,held:held,frame:stateFrame,axis:stateAxis,operating:stateOperating)}
 func updateFrame(_ frame:CGImage){stateFrame=frame;machine?.update(openness:stateOpen,loading:stateLoading,held:held,frame:frame,axis:stateAxis,operating:stateOperating)}
 private var flightSource:SCNVector3?
 private var flightSourceScale:CGFloat?
 func clearMedia(){flight?.removeFromParentNode();flight=nil;flightSource=nil;flightSourceScale=nil}
 func startMedia(model:DeviceModel,cover:UIImage?,tint:UInt32,title:String?=nil){clearMedia();flight=SpatialMachine.media(model:model.rawValue,cover:cover,tint:Int(tint),title:title);if let flight{scene!.rootNode.addChildNode(flight)}}
 func updateMedia(rect:CGRect,progress:CGFloat){guard let flight,let machine else{return}
  SCNTransaction.begin();SCNTransaction.disableActions=true;defer{SCNTransaction.commit()}
  if flight.parent !== scene!.rootNode{flight.removeFromParentNode();scene!.rootNode.addChildNode(flight)}
  let canonicalWidth:CGFloat=machine.model=="psp" ? 260:CGFloat(SpatialMachine.mediaSpecs[machine.model]?["cardWidth"] ?? 148)
  if flightSourceScale == nil{flightSourceScale=rect.width/(canonicalWidth*scale)}
  if machine.model=="psp" {
   if flightSource == nil{flightSource=world(CGPoint(x:rect.midX,y:rect.midY))}
   machine.placePSPMedia(flight,source:flightSource!,progress:progress,sourceScale:flightSourceScale);return
  }
  if flightSource == nil{flightSource=world(CGPoint(x:rect.midX,y:rect.midY))}
  machine.placeCartridge(flight,source:flightSource!,progress:progress,sourceScale:flightSourceScale ?? 1)

 }
 var mediaDiagnostics:[String:Any]{let p=flight.map{projectPoint($0.worldPosition)};return ["slot":slotPoint().map{[Double($0.x),Double($0.y)]} ?? [],"media":p.map{[Double($0.x),Double($0.y),Double($0.z)]} ?? [],"nativeScale":Double(scale),"doorAngle":Double(machine?.mediaTray?.eulerAngles.x ?? 0),"discRotation":flight?.childNode(withName:"umd-rotor",recursively:true).map{[Double($0.presentation.eulerAngles.x),Double($0.presentation.eulerAngles.y),Double($0.presentation.eulerAngles.z)]} ?? [],"protectedUMD":flight?.childNode(withName:"umd-protective-shell",recursively:true) != nil,"audio":MediaSound.shared.diagnostics]}
 func keepMedia(){guard let flight,let machine else{return}
  if machine.model=="psp"{guard let tray=machine.mediaTray else{return};flight.removeFromParentNode();tray.addChildNode(flight);flight.position=SpatialMachine.pspTraySeat;flight.eulerAngles=SpatialMachine.pspMediaOrientation;flight.scale=SCNVector3(0.90,0.90,0.90);SpatialMachine.spinSeatedDisc(flight);return}
  guard let slot=machine.slot else{return};flight.removeFromParentNode();slot.addChildNode(flight);let spec=CartridgeSlot.load(DeviceModel(rawValue:machine.model)!)!,height=spec.cardWidth*spec.ratio/100;flight.position=SCNVector3(0,SpatialMachine.cartridgeSeatY(machine.model,height:height),0);flight.eulerAngles=SpatialMachine.cartridgeOrientation(machine.model);flight.scale=SCNVector3(1,1,1)}
 func slotPoint()->CGPoint?{guard let machine else{return nil};let world=machine.slot?.worldPosition ?? machine.device.convertPosition(SpatialMachine.pspMediaCenter,to:nil);let p=projectPoint(world);return CGPoint(x:CGFloat(p.x),y:CGFloat(p.y))}
}
final class SpatialPreview:SpatialSurface {
 private var rig:SpatialMachine?,media:SCNNode?,kind:DeviceModel = .gba
 private let group=SCNNode(),halo=SCNNode()
 private var rimKey="",rimPlaceholderClear=false
 private var rimReady=false,rimPending=false,rimAllowed=false,inspectionReported=false
 var inspectionChanged:((Bool)->Void)?
 func setFocusDistance(_ distance:CGFloat){rig?.setDisplayFocus(1-min(0.72,abs(distance)*0.72))}
 func setCardLift(_ value:CGFloat){guard media != nil else{return};targetCardLift=max(0,min(1,value))}
 private var cardLift:CGFloat=0,targetCardLift:CGFloat=0
 var cardLiftOffset:CGFloat{cardLift*0.11*bounds.height/CGFloat(2*(cameraNode.camera?.orthographicScale ?? 1))}
 private var fittedPoints:[SCNVector3]?
 private var physicalComparison=false
 private var fillFraction=CGSize.zero
 private var focusSelected=false,browsing=false,focusWork:DispatchWorkItem?
 func setBrowsing(_ value:Bool){browsing=value;if value{focusWork?.cancel();rimAllowed=false}else{scheduleRim()}}
 private func scheduleRim(){guard focusSelected,!browsing,!rimReady,!rimPending else{return};focusWork?.cancel();let work=DispatchWorkItem{[weak self] in guard let self,self.focusSelected,!self.browsing else{return};self.rimAllowed=true;self.setNeedsLayout()};focusWork=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.28,execute:work)}
 private var orbitYaw:Float=0,orbitPitch:Float=0,orbitOrigin=CGPoint.zero,orbitStart=CGPoint.zero,orbitDragging=false,lastOrbitTime:CGFloat=0
 func inspect(yaw:Float,pitch:Float){orbitDragging=true;halo.opacity=0;inspectionChanged?(true);inspectionReported=true;orbitYaw=max(-Float.pi,min(Float.pi,yaw));orbitPitch=max(-0.65,min(0.65,pitch));setPreviewActive(true)}
 func endInspection(){orbitDragging=false}
 var projectedSolidBounds:CGRect{let w=bounds.width*fillFraction.width,h=bounds.height*fillFraction.height;return CGRect(x:(bounds.width-w)/2,y:(bounds.height-h)/2,width:w,height:h)}
 var inspectionDiagnostics:[String:Any]{let contained=fitCorners.allSatisfy{p in let q=projectPoint(group.convertPosition(p,to:scene!.rootNode));return q.x >= -1 && q.x <= Float(bounds.width)+1 && q.y >= -1 && q.y <= Float(bounds.height)+1};return ["rotationContained":contained,"yaw":Double(orbitYaw),"pitch":Double(orbitPitch),"cameraScale":cameraNode.camera?.orthographicScale ?? 0,"fillFraction":[Double(fillFraction.width),Double(fillFraction.height)],"hasMachine":rig != nil,"hasMedia":media != nil,"rimReady":rimReady,"rimPending":rimPending,"transparentRimPlaceholder":rimPlaceholderClear,"internalParts":rig?.internalParts ?? []]}
 func attachInteraction(to view:UIView){let gesture=UILongPressGestureRecognizer(target:self,action:#selector(rotatePreview(_:)));gesture.minimumPressDuration=0.24;gesture.allowableMovement=12;gesture.cancelsTouchesInView=true;view.addGestureRecognizer(gesture);let two=UIPanGestureRecognizer(target:self,action:#selector(rotateWithTwoFingers(_:)));two.minimumNumberOfTouches=2;two.maximumNumberOfTouches=2;two.cancelsTouchesInView=true;view.addGestureRecognizer(two);view.accessibilityHint="按住或双指拖动旋转模型"}
 @objc private func rotatePreview(_ gesture:UILongPressGestureRecognizer){let p=gesture.location(in:gesture.view)
  switch gesture.state {
  case .began:holdCarousel(gesture);orbitDragging=true;halo.opacity=0;inspectionChanged?(true);inspectionReported=true;orbitOrigin=p;orbitStart=CGPoint(x:CGFloat(orbitYaw),y:CGFloat(orbitPitch));setPreviewActive(true)
  case .changed:inspect(yaw:Float(orbitStart.x+(p.x-orbitOrigin.x)*0.012),pitch:Float(orbitStart.y+(p.y-orbitOrigin.y)*0.008))
  default:orbitDragging=false;releaseCarousel()
  }
 }
 @objc private func rotateWithTwoFingers(_ gesture:UIPanGestureRecognizer){
  let p=gesture.translation(in:gesture.view)
  switch gesture.state{case .began:holdCarousel(gesture);orbitDragging=true;orbitStart=CGPoint(x:CGFloat(orbitYaw),y:CGFloat(orbitPitch));inspectionChanged?(true);inspectionReported=true;setPreviewActive(true)
  case .changed:inspect(yaw:Float(orbitStart.x+p.x*0.012),pitch:Float(orbitStart.y+p.y*0.008))
  default:orbitDragging=false;releaseCarousel()}
 }
 private weak var inspectionScroll:UIScrollView?
 private func holdCarousel(_ gesture:UIGestureRecognizer){var parent=gesture.view?.superview;while let v=parent{if let scroll=v as? UIScrollView{inspectionScroll=scroll;scroll.isScrollEnabled=false;break};parent=v.superview}}
 private func releaseCarousel(){inspectionScroll?.isScrollEnabled=true;inspectionScroll=nil}
 private var swayInstalled=false
 private var fitCorners=[SCNVector3](),restCameraScale=1.0,fitAspect=1.0
 private var previewActive=true
 func setPreviewActive(_ active:Bool){previewActive=active;isPlaying=active;rendersContinuously=active;scene?.isPaused = !active}
 private func installHalo(){let geometry=SCNPlane(width:1,height:1),m=SCNMaterial();m.diffuse.contents=UIColor.clear;rimPlaceholderClear=(m.diffuse.contents as? UIColor)?.cgColor.alpha==0;m.lightingModel = .constant;m.writesToDepthBuffer=false;m.readsFromDepthBuffer=false;m.blendMode = .add;geometry.materials=[m];halo.geometry=geometry;halo.renderingOrder=100;halo.opacity=0;scene!.rootNode.addChildNode(halo)}
 func setFocused(_ value:Bool){guard focusSelected != value else{return};focusSelected=value;focusWork?.cancel();SCNTransaction.begin();SCNTransaction.animationDuration=0.24;halo.opacity=value ? 1:0;SCNTransaction.commit();isPlaying=true;rendersContinuously=true;scheduleRim()}
 init(model:DeviceModel,theme:Int,showOpen:Bool=false,physicalComparison:Bool=false){super.init();self.physicalComparison=physicalComparison;rimKey=model.rawValue+":"+String(theme);installHalo();scene!.rootNode.addChildNode(group);kind=model;rig=SpatialMachine(model:model.rawValue,theme:theme);if let rig{group.addChildNode(rig.root);rig.update(openness:model == .nds || model == .n3ds || model == .psp ? 0:1,loading:0,held:[],frame:nil);rig.root.eulerAngles=SCNVector3(0.06,-0.16,0)

  }}
 init(model:DeviceModel,cover:UIImage?,tint:UInt32,title:String?=nil){super.init();scene!.rootNode.addChildNode(group);kind=model;media=SpatialMachine.media(model:model.rawValue,cover:cover,tint:Int(tint),title:title);if let media{group.addChildNode(media);media.eulerAngles=SCNVector3(-0.08,-0.12,0)}}
 required init?(coder:NSCoder){fatalError()}
 override func layoutSubviews(){super.layoutSubviews();guard bounds.width>0,bounds.height>0 else{return}
  var points=fittedPoints ?? []
  if fittedPoints == nil {group.enumerateChildNodes{node,_ in
   guard let geometry=node.geometry,!(geometry is SCNPlane),!node.isHidden else{return}
   let (low,high)=geometry.boundingBox
   for x in [low.x,high.x]{for y in [low.y,high.y]{for z in [low.z,high.z]{points.append(node.convertPosition(SCNVector3(x,y,z),to:group))}}}
  }
  fittedPoints=points}
  let minX=points.map{$0.x}.min() ?? -3,maxX=points.map{$0.x}.max() ?? 3,minY=points.map{$0.y}.min() ?? -2,maxY=points.map{$0.y}.max() ?? 2
  halo.position=SCNVector3((minX+maxX)/2,(minY+maxY)/2,3);if let plane=halo.geometry as? SCNPlane{plane.width=CGFloat(maxX-minX)+0.24;plane.height=CGFloat(maxY-minY)+0.24;if !rimReady && rimAllowed && !browsing && focusSelected && rig != nil{if !rimPending {rimPending=true;let silhouette=group.clone();SpatialRimWorker.request(key:rimKey,node:silhouette,low:SCNVector3(minX,minY,-1),high:SCNVector3(maxX,maxY,1)){[weak self] image in guard let self else{return};self.rimPending=false;self.rimReady=image != nil;self.halo.geometry?.firstMaterial?.diffuse.contents=image ?? UIImage();self.setNeedsDisplay()}}}}
  cameraNode.position=SCNVector3((minX+maxX)/2,(minY+maxY)/2,20);if physicalComparison {
   let physicalHeight=CGFloat(maxY-minY),physicalWidth=CGFloat(maxX-minX)
   let onPhone=UIDevice.current.userInterfaceIdiom == .phone
   let margin:CGFloat=onPhone && kind == .gbc ? 1.07:1.025
   cameraNode.camera?.orthographicScale=Double(max(physicalHeight/2,physicalWidth*bounds.height/(2*bounds.width))*margin/(onPhone ? 1:0.8))
  }else{cameraNode.camera?.orthographicScale=Double(max(CGFloat(maxY-minY)/2,CGFloat(maxX-minX)*bounds.height/(2*bounds.width))*(media == nil ? 1.12:1.18))}
  restCameraScale=cameraNode.camera?.orthographicScale ?? 1;fitAspect=Double(bounds.height/bounds.width)
  let minZ=points.map{$0.z}.min() ?? -1,maxZ=points.map{$0.z}.max() ?? 1
  fitCorners=[minX,maxX].flatMap{x in [minY,maxY].flatMap{y in [minZ,maxZ].map{z in SCNVector3(x,y,z)}}}
  let halfHeight=CGFloat(cameraNode.camera?.orthographicScale ?? 1);fillFraction=CGSize(width:CGFloat(maxX-minX)/(2*halfHeight*bounds.width/bounds.height),height:CGFloat(maxY-minY)/(2*halfHeight))
  if !swayInstalled {
   swayInstalled=true

   let centre=SCNVector3((minX+maxX)/2,(minY+maxY)/2,0)
   let centeredSway=SCNAction.customAction(duration:8.5){[weak self] node,time in
    guard let self else{return};let now=CGFloat(CACurrentMediaTime()),dt=max(0,now-self.lastOrbitTime);self.lastOrbitTime=now
    self.cardLift += (self.targetCardLift-self.cardLift)*(1-exp(-dt*18))
    if !self.orbitDragging{self.orbitYaw*=Float(exp(-dt*1.6));self.orbitPitch*=Float(exp(-dt*1.6))}
    let a:Float=0.055*sin(Float(time)*2*Float.pi/8.5)+self.orbitPitch,b:Float=0.18*sin(Float(time)*2*Float.pi/8.5)+self.orbitYaw;node.eulerAngles=SCNVector3(a,b,0)
    let rested = !self.orbitDragging && abs(self.orbitYaw)<0.025 && abs(self.orbitPitch)<0.025
    self.halo.eulerAngles=SCNVector3(a,b,0);self.halo.opacity=self.focusSelected && rested ? 1:0
    if self.inspectionReported && rested {self.inspectionReported=false;DispatchQueue.main.async{self.inspectionChanged?(false)}}
    node.position=SCNVector3(centre.x-centre.x*cos(b)-centre.y*sin(a)*sin(b),centre.y*(1-cos(a))+Float(self.cardLift)*0.11,centre.x*sin(b)-centre.y*sin(a)*cos(b))
    // Fit the rotated solid, including thickness. The resting size stays unchanged;
    // the camera reserves extra room only where inspection actually needs it.
    var needed=self.restCameraScale
    for corner in self.fitCorners{let p=node.convertPosition(corner,to:self.scene!.rootNode);needed=max(needed,Double(abs(p.y-self.cameraNode.position.y))*1.06,Double(abs(p.x-self.cameraNode.position.x))*self.fitAspect*1.06)}
    if let camera=self.cameraNode.camera{let old=camera.orthographicScale;camera.orthographicScale=needed>old ? needed:old+(needed-old)*(1-exp(-Double(dt)*8))}

   }
   group.runAction(.repeatForever(centeredSway))
   let lamp=SCNNode();lamp.light=SCNLight();lamp.light?.type = .spot;lamp.light?.intensity=200;lamp.light?.color=UIColor(red:1,green:0.94,blue:0.82,alpha:1);lamp.light?.spotInnerAngle=28;lamp.light?.spotOuterAngle=65;lamp.position=SCNVector3((minX+maxX)/2-1,(minY+maxY)/2+3,7);lamp.look(at:SCNVector3((minX+maxX)/2,(minY+maxY)/2,0));scene!.rootNode.addChildNode(lamp)
  }
  rendersContinuously=previewActive;isPlaying=previewActive;preferredFramesPerSecond=60;setNeedsDisplay()
 }
}

private enum SpatialRimWorker {
 private static let queue=DispatchQueue(label:"local.uncleed.rim",qos:.utility)
 private static let cache:NSCache<NSString,UIImage>={let c=NSCache<NSString,UIImage>();c.countLimit=24;c.totalCostLimit=32*1024*1024;return c}()
 static func request(key:String,node:SCNNode,low:SCNVector3,high:SCNVector3,completion:@escaping(UIImage?)->Void){
  let identity=(key+String(format:":%.2f:%.2f:%.2f:%.2f",low.x,low.y,high.x,high.y)) as NSString
  if let image=cache.object(forKey:identity){DispatchQueue.main.async{completion(image)};return}
  queue.async {
   let image=cache.object(forKey:identity) ?? autoreleasepool{SpatialMachine.rimTexture(node:node,low:low,high:high)}
   if let image{cache.setObject(image,forKey:identity,cost:Int(image.size.width*image.size.height*image.scale*image.scale*4))}
   DispatchQueue.main.async{completion(image)}
  }
 }
}
