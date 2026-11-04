import SceneKit
#if canImport(UIKit)
import UIKit
typealias CarouselHost = UIView
#else
import Cocoa
typealias CarouselHost = NSView
#endif

struct SpatialCarouselEntry {
 let model:String,title:String,theme:Int
}

/// The in-game selector is shared geometry and motion, with native input only
/// at the edges. Browsing never stops a game or commits a machine change.
final class SpatialCarouselView:CarouselHost {
 let entries:[SpatialCarouselEntry]
 private(set) var selectedIndex:Int
 var selectionDidChange:((Int)->Void)?
 var confirm:(()->Void)?
 private let surface=SCNView(),stage=SCNScene(),camera=SCNNode(),lamp=SCNNode()
 private var rigs:[SpatialMachine?]=[],centres:[SCNVector3]=[],scales:[CGFloat]=[]
 private var position:CGFloat,dragOrigin:CGFloat=0,dragStart:CGFloat=0,dragging=false,lastTime:TimeInterval=0
 private let lock=NSLock()
 init(entries:[SpatialCarouselEntry],selected:Int){
  self.entries=entries;selectedIndex=max(0,min(entries.count-1,selected));position=CGFloat(selectedIndex)
  super.init(frame:.zero)
  surface.scene=stage;surface.antialiasingMode = .multisampling4X;surface.preferredFramesPerSecond=60
  #if canImport(UIKit)
  surface.isOpaque=false;surface.backgroundColor = .clear;surface.isUserInteractionEnabled=false
  let pan=UIPanGestureRecognizer(target:self,action:#selector(pan(_:)));addGestureRecognizer(pan)
  let tap=UITapGestureRecognizer(target:self,action:#selector(tap(_:)));tap.require(toFail:pan);addGestureRecognizer(tap)
  #else
  surface.wantsLayer=true;surface.backgroundColor = .clear;surface.layer?.backgroundColor=NSColor.clear.cgColor
  #endif
  addSubview(surface);camera.camera=SCNCamera();camera.camera?.usesOrthographicProjection=true;camera.camera?.zFar=100;camera.position=SCNVector3(0,0,20);stage.rootNode.addChildNode(camera);surface.pointOfView=camera
  SpatialMachine.lightStudio(stage)
  let ambient=SCNNode();ambient.light=SCNLight();ambient.light?.type = .ambient;ambient.light?.intensity=100;stage.rootNode.addChildNode(ambient)
  let key=SCNNode();key.light=SCNLight();key.light?.type = .directional;key.light?.intensity=420;key.eulerAngles=SCNVector3(-0.45,-0.35,0);stage.rootNode.addChildNode(key)
  lamp.light=SCNLight();lamp.light?.type = .spot;lamp.light?.intensity=300;lamp.light?.spotInnerAngle=30;lamp.light?.spotOuterAngle=65;lamp.position=SCNVector3(-1,3,7);lamp.look(at:SCNVector3Zero);stage.rootNode.addChildNode(lamp)
  for (index,entry) in entries.enumerated(){
   guard let rig=SpatialMachine(model:entry.model,theme:entry.theme) else{rigs.append(nil);centres.append(SCNVector3Zero);scales.append(1);continue}
   stage.rootNode.addChildNode(rig.root);rig.root.name="switch:\(index)";rig.update(openness:entry.model=="psp" || entry.model=="nds" || entry.model=="3ds" ? 0:1,loading:0,held:[],frame:nil)
   var low=SCNVector3(Float.greatestFiniteMagnitude,Float.greatestFiniteMagnitude,Float.greatestFiniteMagnitude),high=SCNVector3(-Float.greatestFiniteMagnitude,-Float.greatestFiniteMagnitude,-Float.greatestFiniteMagnitude)
   rig.root.enumerateChildNodes{n,_ in guard let g=n.geometry,!(g is SCNPlane),!n.isHidden else{return};let box=g.boundingBox
    for x in [box.min.x,box.max.x]{for y in [box.min.y,box.max.y]{for z in [box.min.z,box.max.z]{let p=n.convertPosition(SCNVector3(x,y,z),to:rig.root);low=SCNVector3(min(low.x,p.x),min(low.y,p.y),min(low.z,p.z));high=SCNVector3(max(high.x,p.x),max(high.y,p.y),max(high.z,p.z))}}}
   }
   let centre=SCNVector3((low.x+high.x)/2,(low.y+high.y)/2,0);rig.root.pivot=SCNMatrix4MakeTranslation(centre.x,centre.y,centre.z);centres.append(centre);scales.append(min(3.2/CGFloat(high.x-low.x),2.65/CGFloat(high.y-low.y)));rigs.append(rig)
  }
  stage.rootNode.runAction(.repeatForever(.customAction(duration:60){[weak self] _,_ in self?.updateMotion(CACurrentMediaTime())}))
  surface.isPlaying=true;surface.rendersContinuously=true
 }
 required init?(coder:NSCoder){fatalError()}
 #if canImport(UIKit)
 override func layoutSubviews(){super.layoutSubviews();layoutScene()}
 @objc private func pan(_ g:UIPanGestureRecognizer){switch g.state{case .began:begin(CGFloat(g.location(in:self).x));case .changed:move(CGFloat(g.location(in:self).x));default:end()}}
 @objc private func tap(_ g:UITapGestureRecognizer){pick(g.location(in:self))}
 #else
 override func hitTest(_ point:NSPoint)->NSView?{bounds.contains(convert(point,from:superview)) ? self:nil}
 override var acceptsFirstResponder:Bool{true}
 override func layout(){super.layout();layoutScene()}
 override func mouseDown(with e:NSEvent){window?.makeFirstResponder(self);begin(convert(e.locationInWindow,from:nil).x)}
 override func mouseDragged(with e:NSEvent){move(convert(e.locationInWindow,from:nil).x)}
 override func mouseUp(with e:NSEvent){let p=convert(e.locationInWindow,from:nil);if abs(p.x-dragOrigin)<5{pick(p)};end()}
 override func keyDown(with e:NSEvent){switch e.keyCode{case 123,126:select(selectedIndex-1);case 124,125:select(selectedIndex+1);case 36:confirm?();default:super.keyDown(with:e)}}
 override func scrollWheel(with e:NSEvent){if abs(e.scrollingDeltaX)+abs(e.scrollingDeltaY)>2{select(selectedIndex+((abs(e.scrollingDeltaX)>abs(e.scrollingDeltaY) ? e.scrollingDeltaX:e.scrollingDeltaY)>0 ? -1:1))}}
 #endif
 func sceneSnapshot()->SpatialImage{surface.snapshot()}
 var diagnostics:[String:Any]{
  lock.lock();let index=selectedIndex,p=position;lock.unlock()
  return ["count":entries.count,"selected":index,"position":Double(p),"allGeometryAvailable":rigs.allSatisfy{$0 != nil},"focusedModel":entries[index].model,"width":Double(bounds.width),"height":Double(bounds.height),"inWindow":window != nil]
 }
 private func layoutScene(){surface.frame=bounds;camera.camera?.orthographicScale=Double(max(1.7,4.1*bounds.height/max(1,bounds.width)));updateMotion(CACurrentMediaTime());surface.isPlaying=true;surface.rendersContinuously=true
  #if canImport(UIKit)
  surface.setNeedsDisplay()
  #else
  surface.needsDisplay=true
  #endif
 }
 func select(_ index:Int){let next=max(0,min(entries.count-1,index));lock.lock();selectedIndex=next;lock.unlock();selectionDidChange?(next)}
 private func begin(_ x:CGFloat){lock.lock();dragOrigin=x;dragStart=position;dragging=true;lock.unlock()}
 private func move(_ x:CGFloat){lock.lock();position=max(-0.15,min(CGFloat(entries.count-1)+0.15,dragStart-(x-dragOrigin)/max(100,bounds.width*0.45)));let next=max(0,min(entries.count-1,Int(position.rounded())));let changed=next != selectedIndex;selectedIndex=next;lock.unlock();if changed{selectionDidChange?(next)}}
 private func end(){lock.lock();dragging=false;lock.unlock()}
 private func pick(_ p:CGPoint){var node=surface.hitTest(p,options:[.searchMode:SCNHitTestSearchMode.closest.rawValue]).first?.node
  while let n=node{if let name=n.name,name.hasPrefix("switch:"),let i=Int(name.dropFirst(7)){select(i);return};node=n.parent}
 }
 private func updateMotion(_ time:TimeInterval){
  lock.lock();let dt=max(0,time-lastTime);lastTime=time;if !dragging{position += (CGFloat(selectedIndex)-position)*(1-exp(-dt*14))};let offset=position;lock.unlock()
  SCNTransaction.begin();SCNTransaction.disableActions=true
  for (i,rig) in rigs.enumerated(){guard let rig else{continue};let d=CGFloat(i)-offset,q=scales[i]*(1-min(0.20,abs(d)*0.13))
   rig.root.isHidden=abs(d)>1.8;rig.root.scale=SCNVector3(q,q,q);rig.root.eulerAngles=SCNVector3(0.07,Float(-d*0.24+sin(time*0.7)*0.10),0);rig.root.position=SCNVector3(d*3.8,0,-min(0.8,abs(d)*0.35))
  };SCNTransaction.commit()
 }
 func stop(){stage.rootNode.removeAllActions();surface.isPlaying=false;surface.rendersContinuously=false}
 deinit{surface.delegate=nil}
}

#if canImport(UIKit)
final class SpatialSwitchController:UIViewController,UIAdaptivePresentationControllerDelegate {
 let wheel:SpatialCarouselView
 private let caption=UILabel()
 var onClose:((Int?)->Void)?
 private var choice:Int?,closed=false
 init(entries:[SpatialCarouselEntry],selected:Int){wheel=SpatialCarouselView(entries:entries,selected:selected);super.init(nibName:nil,bundle:nil);modalPresentationStyle = .pageSheet;preferredContentSize=CGSize(width:560,height:380)}
 required init?(coder:NSCoder){fatalError()}
 override func viewDidLoad(){super.viewDidLoad();view.backgroundColor=UIColor(red:0.10,green:0.13,blue:0.12,alpha:1);wheel.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(wheel)
  caption.textColor=UIColor(red:0.91,green:0.90,blue:0.84,alpha:1);caption.font = .systemFont(ofSize:17,weight:.semibold);caption.textAlignment = .center;caption.numberOfLines=2;caption.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(caption)
  let cancel=UIButton(type:.system);cancel.setTitle("继续游戏",for:.normal);cancel.addAction(UIAction{[weak self] _ in self?.cancelSelection()},for:.touchUpInside)
  let confirm=UIButton(type:.system);var config=UIButton.Configuration.filled();config.title="确认选择";config.baseBackgroundColor=UIColor(red:0.44,green:0.39,blue:0.23,alpha:1);confirm.configuration=config;confirm.addAction(UIAction{[weak self] _ in guard let self else{return};self.commitSelection()},for:.touchUpInside)
  let buttons=UIStackView(arrangedSubviews:[cancel,confirm]);buttons.axis = .horizontal;buttons.spacing=20;buttons.distribution = .fillEqually;buttons.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(buttons)
  NSLayoutConstraint.activate([wheel.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:10),wheel.leadingAnchor.constraint(equalTo:view.leadingAnchor),wheel.trailingAnchor.constraint(equalTo:view.trailingAnchor),wheel.bottomAnchor.constraint(equalTo:caption.topAnchor,constant:-4),caption.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:20),caption.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-20),caption.heightAnchor.constraint(equalToConstant:44),caption.bottomAnchor.constraint(equalTo:buttons.topAnchor,constant:-8),buttons.leadingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.leadingAnchor,constant:24),buttons.trailingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.trailingAnchor,constant:-24),buttons.heightAnchor.constraint(equalToConstant:46),buttons.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor,constant:-16)])
  wheel.selectionDidChange={[weak self] index in self?.caption.text=self?.wheel.entries[index].title};caption.text=wheel.entries[wheel.selectedIndex].title
  if let sheet=sheetPresentationController{sheet.detents=[.custom{_ in 380}];sheet.prefersGrabberVisible=true;sheet.prefersEdgeAttachedInCompactHeight=true}
 }
 override func viewDidAppear(_ animated:Bool){super.viewDidAppear(animated);presentationController?.delegate=self}
 private func deliver(){guard !closed else{return};closed=true;wheel.stop();onClose?(choice)}
 func cancelSelection(completion:(()->Void)?=nil){choice=nil;dismiss(animated:true){self.deliver();completion?()}}
 func commitSelection(){choice=wheel.selectedIndex;dismiss(animated:true){self.deliver()}}
 func presentationControllerDidDismiss(_ presentationController:UIPresentationController){deliver()}
 override func viewDidDisappear(_ animated:Bool){super.viewDidDisappear(animated);wheel.stop()}
}
#else
final class SpatialSwitchController:NSViewController,NSPopoverDelegate {
 let wheel:SpatialCarouselView
 private let caption=NSTextField(labelWithString:"")
 weak var popover:NSPopover?
 var onClose:((Int?)->Void)?
 private var choice:Int?
 init(entries:[SpatialCarouselEntry],selected:Int){wheel=SpatialCarouselView(entries:entries,selected:selected);super.init(nibName:nil,bundle:nil)}
 required init?(coder:NSCoder){fatalError()}
 override func loadView(){view=NSView(frame:CGRect(x:0,y:0,width:560,height:380));view.wantsLayer=true;view.layer?.backgroundColor=NSColor(calibratedRed:0.10,green:0.13,blue:0.12,alpha:1).cgColor
  wheel.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(wheel);caption.alignment = .center;caption.textColor=NSColor(calibratedRed:0.91,green:0.90,blue:0.84,alpha:1);caption.font = .systemFont(ofSize:17,weight:.semibold);caption.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(caption)
  let cancel=NSButton(title:"继续游戏",target:self,action:#selector(cancelChoice));cancel.bezelStyle = .rounded;let confirm=NSButton(title:"确认选择",target:self,action:#selector(confirmChoice));confirm.bezelStyle = .rounded;confirm.keyEquivalent="\r"
  let buttons=NSStackView(views:[cancel,confirm]);buttons.orientation = .horizontal;buttons.spacing=32;buttons.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(buttons)
  NSLayoutConstraint.activate([wheel.topAnchor.constraint(equalTo:view.topAnchor,constant:12),wheel.leadingAnchor.constraint(equalTo:view.leadingAnchor),wheel.trailingAnchor.constraint(equalTo:view.trailingAnchor),wheel.bottomAnchor.constraint(equalTo:caption.topAnchor,constant:-8),caption.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:16),caption.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-16),caption.heightAnchor.constraint(equalToConstant:34),caption.bottomAnchor.constraint(equalTo:buttons.topAnchor,constant:-12),buttons.centerXAnchor.constraint(equalTo:view.centerXAnchor),buttons.heightAnchor.constraint(equalToConstant:36),buttons.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant:-16)])
  wheel.selectionDidChange={[weak self] index in guard let self else{return};self.caption.stringValue=self.wheel.entries[index].title};caption.stringValue=wheel.entries[wheel.selectedIndex].title;wheel.confirm={[weak self] in self?.confirmChoice()}
 }
 override func viewDidAppear(){super.viewDidAppear();view.window?.makeFirstResponder(wheel)}
 @objc private func cancelChoice(){popover?.performClose(nil)}
 @objc private func confirmChoice(){choice=wheel.selectedIndex;popover?.performClose(nil)}
 override func cancelOperation(_ sender:Any?){popover?.performClose(nil)}
 func popoverDidClose(_ notification:Notification){wheel.stop();onClose?(choice)}
}
#endif
