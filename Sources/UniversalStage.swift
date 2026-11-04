import Cocoa
import SceneKit
private final class UniversalSurface:SCNView {
 weak var owner:StudioView?
 weak var stage:UniversalStage?
 override var acceptsFirstResponder:Bool{false}
 override func mouseDown(with e:NSEvent){stage?.beginPreviewPress(e);owner?.mouseDown(with:e)}
 override func mouseDragged(with e:NSEvent){if stage?.dragPreview(e)==true{return};owner?.mouseDragged(with:e)}
 override func mouseUp(with e:NSEvent){if stage?.endPreviewPress()==true{return};owner?.mouseUp(with:e)}
 override func scrollWheel(with e:NSEvent){owner?.scrollWheel(with:e)}
 override func mouseMoved(with e:NSEvent){owner?.mouseMoved(with:e)}
}
final class UniversalStage:NSObject,SCNSceneRendererDelegate {
 weak var owner:StudioView?
 private let view=UniversalSurface(),scene=SCNScene(),camera=SCNNode()
 private var rigs:[String:SpatialMachine]=[:],cards:[SCNNode]=[],flight:SCNNode?,signature="",flightID="",mouseKeys=Set<Int>(),touching=false,stickDragging=false
 private(set) var previewRotationGestures=0
 private var frames=0,lock=NSLock()
 private var halos:[ObjectIdentifier:SCNNode]=[:]
 private var orbitPoses:[String:CGPoint]=[:],pressOrigin:CGPoint?,pressBegan:CFTimeInterval=0,pressKey="",orbitDragging=false,orbitInitial=CGPoint.zero,lastOrbitTick=CACurrentMediaTime()
 private func orbitKey(_ node:SCNNode)->String{(owner?.handheld.rawValue ?? "")+(node.name ?? "")}
 func beginPreviewPress(_ event:NSEvent){guard let owner,owner.choosing || owner.phase == .library else{return}
  pressOrigin=nil;pressKey=""
  let hits=view.hitTest(view.convert(event.locationInWindow,from:nil),options:[.searchMode:SCNHitTestSearchMode.all.rawValue,.categoryBitMask:1])
  guard let target=hits.lazy.compactMap({SpatialMachine.previewTarget($0.node)}).first else{return}
  pressKey=orbitKey(target);pressOrigin=owner.point(event);pressBegan=CACurrentMediaTime();orbitInitial=orbitPoses[pressKey] ?? .zero
 }
 func dragPreview(_ event:NSEvent)->Bool{guard let owner,let origin=pressOrigin else{return false};let p=owner.point(event),dx=p.x-origin.x,dy=p.y-origin.y
  guard orbitDragging || hypot(dx,dy)>4 else{return false};if !orbitDragging{previewRotationGestures+=1};orbitDragging=true;owner.gbcThemeDragging=false;owner.shelfDown=nil;owner.dragged=true;orbitPoses[pressKey]=CGPoint(x:max(-CGFloat.pi,min(CGFloat.pi,orbitInitial.x+dx*0.012)),y:max(-0.65,min(0.65,orbitInitial.y+dy*0.008)));return true
 }
 func endPreviewPress()->Bool{let consumed=orbitDragging;pressOrigin=nil;orbitDragging=false;if consumed{owner?.gbcThemeDragging=false;owner?.shelfDown=nil;owner?.dragged=false};return consumed}
 private func previewOrbit(_ node:SCNNode)->CGPoint{orbitPoses[orbitKey(node)] ?? .zero}
 private let focusLight=SCNNode(),ceremony=SpatialCeremony(),lightView=UniversalSurface(),lightScene=SCNScene(),lightCamera=SCNNode()
 private var previousPickerPage=""
 private var previewBounds:[ObjectIdentifier:(SCNVector3,SCNVector3)]=[:]
 init(owner:StudioView){self.owner=owner;super.init();view.owner=owner;view.stage=self;view.scene=scene;view.backgroundColor = .clear;view.wantsLayer=true;view.layer?.backgroundColor=NSColor.clear.cgColor;view.antialiasingMode = .multisampling4X;view.delegate=self
  camera.camera=SCNCamera();camera.camera?.usesOrthographicProjection=true;camera.camera?.zFar=100;camera.position=SCNVector3(0,0,20);scene.rootNode.addChildNode(camera);view.pointOfView=camera
  SpatialMachine.lightStudio(scene)
  lightView.owner=owner;lightView.stage=self;lightView.scene=lightScene;lightView.backgroundColor = .clear;lightView.isPlaying=true;lightView.rendersContinuously=true;lightView.preferredFramesPerSecond=60;lightScene.rootNode.addChildNode(ceremony.root);lightCamera.camera=SCNCamera();lightCamera.camera?.usesOrthographicProjection=true;lightCamera.position=SCNVector3(0,0,20);lightScene.rootNode.addChildNode(lightCamera);lightView.pointOfView=lightCamera;owner.addSubview(lightView)
  let a=SCNNode();a.light=SCNLight();a.light?.type = .ambient;a.light?.intensity=130;scene.rootNode.addChildNode(a)
  let l=SCNNode();l.light=SCNLight();l.light?.type = .directional;l.light?.intensity=460;l.eulerAngles=SCNVector3(-0.45,-0.4,0);scene.rootNode.addChildNode(l)
  let f=SCNNode();f.light=SCNLight();f.light?.type = .omni;f.light?.intensity=120;f.position=SCNVector3(4,-2,8);scene.rootNode.addChildNode(f);owner.addSubview(view)
  focusLight.light=SCNLight();focusLight.light?.type = .spot;focusLight.light?.intensity=200;focusLight.light?.color=NSColor(calibratedRed:1,green:0.94,blue:0.82,alpha:1);focusLight.light?.spotInnerAngle=28;focusLight.light?.spotOuterAngle=65;scene.rootNode.addChildNode(focusLight)
 }
 var renderedFrames:Int{lock.lock();defer{lock.unlock()};return frames}
 func renderer(_ renderer:SCNSceneRenderer,updateAtTime time:TimeInterval){lock.lock();frames+=1;lock.unlock()}
 private func point(_ x:CGFloat,_ y:CGFloat)->SCNVector3{SCNVector3((x-360)/100,((owner?.canvasHeight ?? 780)/2-y)/100,0)}
 private func rig(_ kind:Handheld,_ theme:Int,_ suffix:String="")->SpatialMachine?{let key=kind.rawValue+String(theme)+suffix;if let rig=rigs[key]{return rig};guard let r=SpatialMachine(model:kind.rawValue,theme:theme) else{return nil};rigs[key]=r;scene.rootNode.addChildNode(r.root);return r}
 private func scale(_ root:SCNNode,_ q:CGFloat){root.scale=SCNVector3(q,q,q)}
 // Fit the posed geometry, including folded lids, inside one carousel column.
 private func placePreview(_ r:SpatialMachine,x:CGFloat,y:CGFloat,width:CGFloat,height:CGFloat,delta:CGFloat,physical:Bool=false){
  r.root.position=SCNVector3Zero;r.root.scale=SCNVector3(1,1,1)
  r.root.eulerAngles=SCNVector3(0.06,-0.16,0)
  r.root.opacity=1
  var low=SCNVector3(CGFloat.greatestFiniteMagnitude,CGFloat.greatestFiniteMagnitude,CGFloat.greatestFiniteMagnitude),high=SCNVector3(-CGFloat.greatestFiniteMagnitude,-CGFloat.greatestFiniteMagnitude,-CGFloat.greatestFiniteMagnitude)
  let identity=ObjectIdentifier(r.root)
  if let cached=previewBounds[identity]{low=cached.0;high=cached.1}else{
  r.root.enumerateChildNodes{node,_ in
   guard let geometry=node.geometry,!(geometry is SCNPlane),!node.isHidden else{return}
   let box=geometry.boundingBox
   for a in [box.min.x,box.max.x]{for b in [box.min.y,box.max.y]{for c in [box.min.z,box.max.z]{
    let p=node.convertPosition(SCNVector3(a,b,c),to:self.scene.rootNode)
    low=SCNVector3(min(low.x,p.x),min(low.y,p.y),min(low.z,p.z));high=SCNVector3(max(high.x,p.x),max(high.y,p.y),max(high.z,p.z))
   }}}
  }
  previewBounds[identity]=(low,high)
  }
  let q:CGFloat
  if physical {q=SpatialMachine.physicalWidth(r.model)*SpatialMachine.homePointsPerMillimeter/100/max(0.01,high.x-low.x)}
  else {q=min(width/100/max(0.01,high.x-low.x),height/100/max(0.01,high.y-low.y))*(1-min(0.14,abs(delta)*0.14))}
  scale(r.root,q)
  let target=point(x,y)
  r.root.eulerAngles.x += sin(CACurrentMediaTime()*1.0)*0.055
  r.root.eulerAngles.y += sin(CACurrentMediaTime()*0.78)*0.18
  let orbit=previewOrbit(r.root);r.root.eulerAngles.x+=orbit.y;r.root.eulerAngles.y+=orbit.x
  if abs(delta)<0.03 && !(owner?.gbcThemeDragging ?? false) && CACurrentMediaTime()>(owner?.pickerWheelActiveUntil ?? 0) {
  let glow:SCNNode
  if let existing=halos[identity]{glow=existing}else{let plane=SCNPlane(width:1,height:1),m=SCNMaterial();m.diffuse.contents=NSColor.clear;let silhouette=r.root.clone(),rimLow=low,rimHigh=high;DispatchQueue.main.async{m.diffuse.contents=SpatialMachine.rimTexture(node:silhouette,low:rimLow,high:rimHigh)};m.lightingModel = .constant;m.writesToDepthBuffer=false;m.readsFromDepthBuffer=false;m.blendMode = .add;plane.materials=[m];glow=SCNNode(geometry:plane);glow.categoryBitMask=2;glow.renderingOrder=100;scene.rootNode.addChildNode(glow);halos[identity]=glow}
  if let plane=glow.geometry as? SCNPlane{plane.width=(high.x-low.x+0.24)*q;plane.height=(high.y-low.y+0.24)*q};glow.position=SCNVector3(target.x,target.y,3);glow.isHidden=r.root.isHidden || orbitDragging || abs(orbit.x)>0.025 || abs(orbit.y)>0.025;glow.opacity=pow(max(0,1-abs(delta)),2)

  }

  r.root.position=SCNVector3(target.x-(low.x+high.x)*q/2,target.y-(low.y+high.y)*q/2,-min(0.6,abs(delta)*0.3))
 }
 func sync(){guard let owner else{return};let page=owner.choosing ? (owner.pickerPage == .models ? "models":"themes"):""
  if !page.isEmpty && !previousPickerPage.isEmpty && page != previousPickerPage{view.alphaValue=0;NSAnimationContext.runAnimationGroup{context in context.duration=0.28;view.animator().alphaValue=1}}
  previousPickerPage=page;let now=CACurrentMediaTime(),dt=max(0,now-lastOrbitTick);lastOrbitTick=now;for (key,p) in orbitPoses where !orbitDragging || key != pressKey{orbitPoses[key]=CGPoint(x:p.x*exp(-dt*1.6),y:p.y*exp(-dt*1.6))};let active = !owner.focusActive;view.isHidden = !active;view.isPlaying=active;view.rendersContinuously=active;view.preferredFramesPerSecond=60;if !active{return}
  ceremony.focus(owner.choosing && owner.pickerPage == .models);lightView.frame=owner.bounds;lightCamera.camera?.orthographicScale=4.5;ceremony.fillViewport(width:9*owner.bounds.width/max(1,owner.bounds.height),height:9);lightView.isHidden = !owner.choosing;lightView.isPlaying=owner.choosing;lightView.rendersContinuously=owner.choosing
  focusLight.isHidden = !owner.choosing;let focus=point(360,385);focusLight.position=SCNVector3(focus.x-1.5,focus.y+3.5,7);focusLight.look(at:focus)
  view.frame=CGRect(x:owner.offset.x,y:owner.offset.y,width:720*owner.scale,height:owner.canvasHeight*owner.scale);camera.camera?.orthographicScale=Double(owner.canvasHeight/200)
  SCNTransaction.begin();SCNTransaction.disableActions=true
  for halo in halos.values{halo.isHidden=true};for r in rigs.values{r.root.isHidden=true};for c in cards{c.isHidden=true};flight?.isHidden=true
  if owner.choosing {
   if owner.pickerPage == .models {
    for (i,kind) in Handheld.allCases.enumerated(){let delta=CGFloat(i)-owner.modelPosition;guard abs(delta)<=1.6 else{continue};guard let r=rig(kind,max(0,min(kind.editions.count-1,UserDefaults.standard.integer(forKey:"theme."+kind.rawValue)))) else{continue};r.root.isHidden=abs(delta)>1.6;if r.root.isHidden{continue};r.setDisplayFocus(1-min(0.72,abs(delta)*0.72));r.root.name="model:\(i)";r.update(openness:kind == .nds || kind == .n3ds || kind == .psp ? 0:1,loading:0,held:[],frame:nil)
     placePreview(r,x:360+delta*SpatialMachine.homeColumn,y:385,width:260,height:330,delta:delta,physical:true)
    }
   }else{
    let paired=owner.dual || owner.handheld == .psp
    for t in 0..<owner.handheld.editions.count {
     let delta=CGFloat(t)-owner.gbcThemePosition;guard abs(delta)<=1.6 else{continue}
     guard let r=rig(owner.handheld,t) else{continue}
     r.root.isHidden=abs(delta)>1.6;if r.root.isHidden{continue};r.setDisplayFocus(1-min(0.72,abs(delta)*0.72));r.root.name="theme:\(t)"
     r.update(openness:paired ? 0:1,loading:0,held:[],frame:nil)
     placePreview(r,x:360+delta*SpatialMachine.homeColumn,y:385,width:300,height:330,delta:delta,physical:true)

    }
   }
  }else if let r=rig(owner.handheld,owner.theme){
   r.root.isHidden=owner.phase == .library;r.root.name="machine";r.root.opacity=1;r.setDisplayFocus(1);let t=smooth(owner.lid),gbc=owner.handheld == .gbc,gameY:CGFloat=owner.dual ? 415:gbc ? 400:owner.handheld == .gba ? 300:245
   let start=owner.spatialLoadingFrame,q=mix(owner.spatialLoadingScale,1,t);r.root.position=point(360,mix(start.midY,gameY,t));scale(r.root,q);r.root.eulerAngles=SCNVector3(mix(owner.handheld == .gbc ? 0.18:owner.handheld == .psp ? 0.22:0.12,0,t),mix(owner.handheld == .psp ? -0.16:-0.20,0,t),owner.pose * .pi/2)
   let loading=owner.phase == .inserting ? min(1,CGFloat(CACurrentMediaTime()-owner.stageStart)/SpatialMachine.insertionTime(owner.handheld.rawValue)):0
   r.update(openness:owner.lid,loading:loading,held:owner.held,frame:owner.videoFrame,axis:CGPoint(x:owner.stickX,y:owner.stickY),operating:owner.phase == .playing || owner.phase == .idleOpen)
   let next=owner.handheld.rawValue+owner.games.map{$0.code+":"+(owner.cartridgePalettes[$0.code]?.coverSHA256 ?? "")}.joined(separator:"|")
   if signature != next {for c in cards{c.removeFromParentNode()};cards=owner.games.enumerated().compactMap{i,g in guard let c=SpatialMachine.media(model:owner.handheld.rawValue,cover:g.cover,tint:owner.cartridgeTint(g),title:g.title) else{return nil};c.name="card:\(i)";scene.rootNode.addChildNode(c);return c};signature=next}
   let cardWidth:CGFloat=owner.handheld == .psp ? 260:mediaSlots[owner.handheld.rawValue]?.cardWidth ?? 148
   if owner.phase == .library || owner.phase == .focusing {for (i,c) in cards.enumerated(){let rect=owner.cardRect(i);c.isHidden=false;let focus=pow(max(0,1-abs(CGFloat(i)-owner.carousel)),2);c.position=point(rect.midX,rect.midY-12*focus-sin(CACurrentMediaTime()*1.3+Double(i))*3.5);c.position.z = .init(0.12*focus);scale(c,rect.width/cardWidth);c.eulerAngles=SCNVector3(-0.10,(CGFloat(i)-owner.carousel)*0.08+sin(CACurrentMediaTime()*0.90+Double(i)*0.3)*0.15,0);let orbit=previewOrbit(c);c.eulerAngles.x+=orbit.y;c.eulerAngles.y+=orbit.x;c.opacity=owner.phase == .focusing ? 1-smooth(CGFloat(CACurrentMediaTime()-owner.stageStart)/0.32):1}}
   if owner.phase != .library,let game=owner.selected {
    let code=owner.handheld.rawValue+game.code
    if flightID != code || flight == nil{flight?.removeFromParentNode();flight=SpatialMachine.media(model:owner.handheld.rawValue,cover:game.cover,tint:owner.cartridgeTint(game),title:game.title);flightID=code}
    if let flight {
     flight.isHidden=false
     if owner.phase == .focusing || owner.phase == .inserting {
      if flight.parent !== scene.rootNode{flight.removeFromParentNode();scene.rootNode.addChildNode(flight)}
      let source=owner.cardRect(owner.selectedIndex),age=CGFloat(CACurrentMediaTime()-owner.stageStart),progress=owner.phase == .inserting ? min(1,age/SpatialMachine.insertionTime(owner.handheld.rawValue)):0
      let start=point(source.midX,source.midY-12)
      if owner.handheld == .psp{r.placePSPMedia(flight,source:start,progress:progress,worldScale:q)}else{r.placeCartridge(flight,source:start,progress:progress,sourceScale:source.width/cardWidth,worldScale:q)}
      if owner.phase == .focusing,cards.indices.contains(owner.selectedIndex){cards[owner.selectedIndex].isHidden=true}
     }else if owner.handheld != .psp,let slot=r.slot {
      if flight.parent !== slot {flight.removeFromParentNode();slot.addChildNode(flight)}
      let h=cardWidth*(mediaSlots[owner.handheld.rawValue]?.ratio ?? 1)/100,eject=owner.phase == .closing ? smooth((CGFloat(CACurrentMediaTime()-owner.stageStart)/1.2-0.6)/0.4):0
      flight.position=SCNVector3(0,SpatialMachine.cartridgeSeatY(owner.handheld.rawValue,height:h)+h*eject,0);flight.eulerAngles=SpatialMachine.cartridgeOrientation(owner.handheld.rawValue);scale(flight,1)
     }else{if let tray=r.mediaTray{if flight.parent !== tray{flight.removeFromParentNode();tray.addChildNode(flight)};flight.position=SpatialMachine.pspTraySeat;flight.eulerAngles=SpatialMachine.pspMediaOrientation;scale(flight,0.90);SpatialMachine.spinSeatedDisc(flight)}}
    }
   }
  }
  SCNTransaction.commit();view.needsDisplay=true
 }
 private func hit(_ e:NSEvent)->SCNHitTestResult?{view.hitTest(view.convert(e.locationInWindow,from:nil),options:[.searchMode:SCNHitTestSearchMode.closest.rawValue,.categoryBitMask:1]).first}
 private func index(_ e:NSEvent,_ prefix:String)->Int?{var node=hit(e)?.node;while let n=node{if let name=n.name,name.hasPrefix(prefix){return Int(name.dropFirst(prefix.count))};node=n.parent};return nil}
 func cardIndex(_ e:NSEvent)->Int?{index(e,"card:")}
 func themeIndex(_ e:NSEvent)->Int?{index(e,"theme:")}
 func modelIndex(_ e:NSEvent)->Int?{index(e,"model:")}
 private func apply(_ ids:Set<Int>){guard let owner else{return};for i in mouseKeys.subtracting(ids){owner.set(i,false)};for i in ids.subtracting(mouseKeys){owner.set(i,true)};mouseKeys=ids}
 func press(_ e:NSEvent){guard let owner else{return};let p=owner.point(e),m=owner.machinePoint(p)
  if owner.powerRect.contains(m){owner.handlePower();return}
  if owner.modern && owner.handleModernUtility(p){return}
  if owner.modern && owner.modernStickRect.contains(p){stickDragging=true;owner.updateStick(p);return}
  if let hit=hit(e),hit.node.name=="screen:1"{touching=true;touch(hit,true);return}
  if let rig=rig(owner.handheld,owner.theme){apply(controlHit(e,rig))}
 }
 private func controlHit(_ event:NSEvent,_ rig:SpatialMachine)->Set<Int>{
  // Rear-edge shoulder caps can sit behind the face moulding in projection.
  // Resolve the actual control mesh throughout the ray, just as the mobile
  // projected target does, instead of letting the front decal eat that press.
  let hits=view.hitTest(view.convert(event.locationInWindow,from:nil),options:[.searchMode:SCNHitTestSearchMode.all.rawValue,.categoryBitMask:1])
  return hits.lazy.map{rig.controls(at:$0)}.first(where:{!$0.isEmpty}) ?? []
 }
 private func touch(_ hit:SCNHitTestResult,_ down:Bool){guard let owner else{return};let p=hit.localCoordinates,w=owner.handheld == .n3ds ? 3.2:3.2,h:CGFloat=2.4;let u=0.5+CGFloat(p.x)/w,v=0.5-CGFloat(p.y)/h;owner.touch(CGPoint(x:owner.bottom.minX+u*owner.bottom.width,y:owner.bottom.minY+v*owner.bottom.height),down)}
 func drag(_ e:NSEvent){guard let owner else{return};if stickDragging{owner.updateStick(owner.point(e));return};if touching{if let h=hit(e),h.node.name=="screen:1"{touch(h,true)}else{owner.touch(.zero,false)};return};if let rig=rig(owner.handheld,owner.theme){apply(controlHit(e,rig))}else{apply([])}}
 func release(){apply([]);if touching{owner?.touch(.zero,false)};touching=false;if stickDragging{owner?.stickX=0;owner?.stickY=0;emu_axis(0,0,0);emu_axis(0,1,0)};stickDragging=false}
 func clearInputState(){mouseKeys=[];touching=false;stickDragging=false}
 func updateTooltip(_ e:NSEvent){guard let owner,let h=hit(e),let r=rig(owner.handheld,owner.theme) else{view.toolTip=nil;return};let names=[0:"B / Z",1:"Y / A",2:"SELECT / 右 Shift",3:"START / Return",4:"上 / ↑",5:"下 / ↓",6:"左 / ←",7:"右 / →",8:"A / X",9:"X / S",10:"L / Q",11:"R / W"];view.toolTip=r.controls(at:h).sorted().compactMap{names[$0]}.joined(separator:" + ")}
 func projectedControl(_ id:Int)->CGPoint?{guard let owner,let n=rig(owner.handheld,owner.theme)?.controlNode(id) else{return nil};let p=view.projectPoint(n.worldPosition);return view.convert(CGPoint(x:p.x,y:p.y),to:owner)}
}
extension StudioView {
 func drawSpatialPicker(){
  if pickerPage == .themes{pill("‹  选择机型",CGRect(x:28,y:28,width:160,height:40))}
  if pickerPage == .themes{centered(handheld.name,360,115,25,color(0xF0EAD9),.semibold)}
  if pickerPage == .models {
   for (i,kind) in Handheld.allCases.enumerated(){let alpha=max(0,1-abs(CGFloat(i)-modelPosition)*2);guard i==Int(modelPosition.rounded()),alpha>0 else{continue};NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current?.cgContext.setAlpha(alpha)
    centered(kind == .psp ? "SONY":"NINTENDO",360,122,10,color(0xAAB6A8),.medium);if homeBrandLogos[kind]==nil{homeBrandLogos[kind]=NSImage(contentsOf:bundledAssets.appendingPathComponent("Logos/"+kind.rawValue+"-home.png"))};homeBrandLogos[kind]?.draw(in:CGRect(x:250,y:148,width:220,height:44),from:.zero,operation:.sourceOver,fraction:alpha,respectFlipped:true,hints:nil);NSGraphicsContext.restoreGraphicsState()
   }
  }
  let count=pickerPage == .models ? Handheld.allCases.count:handheld.editions.count,position=pickerPage == .models ? modelPosition:gbcThemePosition
  if pickerPage == .themes {for i in 0..<count{let x=360+(CGFloat(i)-position)*SpatialMachine.homeColumn;if x > -130 && x<850{let name=pickerPage == .models ? Handheld.allCases[i].name:handheld.editions[i];centered(name,x,610,16,color(i==pickerIndex ? 0xDDE8D6:0x7F9085),.semibold)}}}
  drawPageDots(count:count,index:pickerIndex,y:632)
  pill(pickerPage == .models ? "选择这台掌机  →":"确认这个主题  →",CGRect(x:260,y:660,width:200,height:44));centered("双指滑动 / 方向键切换 · 拖动机身旋转 · 点击或回车确认",360,744,11,color(0x96A18F))
 }
}

extension StudioView {
 func showSpatialSwitcher(){
  guard running,phase == .playing,machineSelector?.isShown != true else{return}
  releaseAll();CoreDriver.shared.save();CoreDriver.shared.volume(0)
  let entries=Handheld.allCases.map{kind in SpatialCarouselEntry(model:kind.rawValue,title:kind.name,theme:max(0,min(kind.editions.count-1,UserDefaults.standard.integer(forKey:"theme."+kind.rawValue))))}
  let controller=SpatialSwitchController(entries:entries,selected:Handheld.allCases.firstIndex(of:handheld) ?? 0),popup=NSPopover();machineSelector=popup;popup.behavior = .transient;popup.contentSize=CGSize(width:560,height:380);popup.contentViewController=controller;popup.delegate=controller;controller.popover=popup
  controller.onClose={[weak self] choice in guard let self else{return};self.machineSelector=nil;if let choice{let kind=Handheld.allCases[choice];if kind != self.handheld{self.chooseMachine(kind)}};if self.running{CoreDriver.shared.volume(self.muted ? 0:1)};self.window?.makeFirstResponder(self)}
  popup.show(relativeTo:CGRect(x:offset.x+28*scale,y:offset.y+28*scale,width:160*scale,height:40*scale),of:self,preferredEdge:.maxY)
 }
}

extension StudioView {
 func drawPageDots(count:Int,index:Int,y:CGFloat){
  guard count>1 else{return}
  let visible=min(count,9),start=max(0,min(count-visible,index-visible/2))
  for i in start..<(start+visible){let x=360+CGFloat(i-start)*20-CGFloat(visible-1)*10
   color(i==index ? 0xE1C681:0x59635B).setFill();NSBezierPath(ovalIn:CGRect(x:x-3.5,y:y-3.5,width:7,height:7)).fill()
  }
 }
 func pageDotHit(_ point:CGPoint,count:Int,index:Int,y:CGFloat)->Int?{
  guard count>1,abs(point.y-y)<=16 else{return nil}
  let visible=min(count,9),start=max(0,min(count-visible,index-visible/2)),left=360-CGFloat(visible-1)*10
  guard point.x>=left-10,point.x<=left+CGFloat(visible-1)*20+10 else{return nil}
  return max(start,min(start+visible-1,start+Int(((point.x-left)/20).rounded())))
 }
}
