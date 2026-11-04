import SceneKit
import CoreImage
import AVFAudio
import simd
#if canImport(UIKit)
import UIKit
typealias SpatialImage = UIImage
#else
import Cocoa
typealias SpatialImage = NSImage
#endif

/// A single baked geometry/texture package is loaded by both platforms.
final class SpatialMachine {
 let root=SCNNode(),device:SCNNode,model:String,theme:Int
 private(set) var size:CGSize = .zero
 private(set) var screens:[CGRect]=[]
 private var keys:[Int:SCNNode]=[:],rest:[Int:SCNVector3]=[:],cross:SCNNode?,lid:SCNNode?,hatch:SCNNode?,stick:SCNNode?
 private var physicalShoulders:[Int:SCNNode]=[:]
 private var previous=Set<Int>(),lastFrame:CGImage?,stickRest:SCNVector3?
 private var screenMaterials:[SCNMaterial]=[]
 private var powerSlider:SCNNode?,powerRest=SCNVector3Zero
 static let pspMediaCenter=SCNVector3(0,0.11,-0.30)
 static func mediaScale(_ model:String)->CGFloat{model=="psp" ? 0.90:1}
 /// Shared physical width reference (mm); homepage uses one scale across machines.
 static func physicalWidth(_ model:String)->CGFloat {
  switch model {case "gbc":return 78;case "gba":return 144.5;case "psp":return 169.4;case "nds":return 133;case "3ds":return 160;default:return 160}
 }
 static func screenScale(_ model:String)->CGFloat{model=="psp" ? 1.18:1.12}
 static let homeColumn:CGFloat=480
 static let homePointsPerMillimeter:CGFloat=2.6
 static var directory:URL {Bundle.main.resourceURL!.appendingPathComponent("Assets/Skins/Spatial")}
 /// Fit one physical scene: closed body plus clearance for its real media.
 static func loadingFrame(model:String,size:CGSize,available:CGRect,maxScale:CGFloat,mediaHeight:CGFloat)->CGRect {
  let body:CGRect
  switch model{case "gbc":body=CGRect(x:15,y:25,width:350,height:570);case "gba":body=CGRect(x:40,y:25,width:640,height:330);case "psp":body=CGRect(x:30,y:30,width:660,height:290);default:body=CGRect(x:40,y:360,width:640,height:330)}
  let clearance:CGFloat=model=="psp" ? 0:mediaHeight+20
  let q=min(maxScale,available.width/body.width,available.height/(body.height+clearance))
  let y=available.minY+(available.height-(body.height+clearance)*q)/2+clearance*q-body.minY*q
  return CGRect(x:available.midX-size.width*q/2,y:y,width:size.width*q,height:size.height*q)
 }
 /// A cached alpha rim from the posed solid silhouette; transparent texture
 /// rectangles never contribute. Only a narrow line and a three-point falloff remain.
 static func rimTexture(node:SCNNode,low:SCNVector3,high:SCNVector3)->SpatialImage? {
  let padding:CGFloat=0.12,width=CGFloat(high.x-low.x)+padding*2,height=CGFloat(high.y-low.y)+padding*2
  let stage=SCNScene(),silhouette=node.clone();stage.background.contents=CGColor(gray:0,alpha:1);silhouette.isHidden=false;silhouette.opacity=1;silhouette.removeAllActions();silhouette.scale=SCNVector3(1,1,1);silhouette.position=SCNVector3Zero
  silhouette.enumerateChildNodes{n,_ in
   n.removeAllActions()
   guard let geometry=n.geometry else{return}
   if geometry is SCNPlane{n.removeFromParentNode();return}
   let solid=geometry.copy() as! SCNGeometry,white=SCNMaterial();white.diffuse.contents=CGColor(gray:1,alpha:1);white.lightingModel = .constant;white.isDoubleSided=true;solid.materials=geometry.materials.map{_ in white};n.geometry=solid;n.opacity=1
  }
  stage.rootNode.addChildNode(silhouette)
  let camera=SCNNode();camera.camera=SCNCamera();camera.camera?.usesOrthographicProjection=true;camera.camera?.orthographicScale=Double(height/2);camera.camera?.zFar=100;camera.position=SCNVector3((low.x+high.x)/2,(low.y+high.y)/2,20);stage.rootNode.addChildNode(camera)
  let renderer=SCNRenderer(device:nil,options:nil);renderer.scene=stage;renderer.pointOfView=camera
  let snapshot=renderer.snapshot(atTime:0,with:CGSize(width:ceil(width*200),height:ceil(height*200)),antialiasingMode:.multisampling4X)
  #if canImport(UIKit)
  guard let cg=snapshot.cgImage else{return nil}
  #else
  guard let cg=snapshot.cgImage(forProposedRect:nil,context:nil,hints:nil) else{return nil}
  #endif
  // Snapshot alpha can be opaque on macOS. Derive coverage from the
  // white solid pass instead of treating its black background as geometry.
  let mask=CIImage(cgImage:cg).applyingFilter("CIColorMatrix",parameters:[
   "inputRVector":CIVector(x:0,y:0,z:0,w:0),"inputGVector":CIVector(x:0,y:0,z:0,w:0),
   "inputBVector":CIVector(x:0,y:0,z:0,w:0),"inputAVector":CIVector(x:1,y:0,z:0,w:0)]),extent=CIImage(cgImage:cg).extent
  let edge=mask.applyingFilter("CIMorphologyMaximum",parameters:["inputRadius":2.5]).applyingFilter("CISourceOutCompositing",parameters:[kCIInputBackgroundImageKey:mask]).cropped(to:extent)
  let spill=mask.applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:8.0]).applyingFilter("CISourceOutCompositing",parameters:[kCIInputBackgroundImageKey:mask]).cropped(to:extent)
  func tint(_ source:CIImage,_ alpha:CGFloat)->CIImage{CIImage(color:CIColor(red:1,green:0.84,blue:0.52,alpha:alpha)).cropped(to:extent).applyingFilter("CISourceInCompositing",parameters:[kCIInputBackgroundImageKey:source])}
  let ink=tint(edge,0.58).composited(over:tint(spill,0.45))
  guard let image=CIContext(options:[.cacheIntermediates:false]).createCGImage(ink,from:extent) else{return nil}
  #if canImport(UIKit)
  return UIImage(cgImage:image)
  #else
  return NSImage(cgImage:image,size:CGSize(width:image.width,height:image.height))
  #endif
 }
 /// Shared soft-box reflection map, so matte resin has a surface highlight
 /// rather than looking like a flat alpha overlay on every platform.
 static let studioEnvironment:CGImage={
  let c=CGContext(data:nil,width:512,height:256,bitsPerComponent:8,bytesPerRow:2048,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
  c.setFillColor(CGColor(gray:0.16,alpha:1));c.fill(CGRect(x:0,y:0,width:512,height:256))
  for (r,gray) in [(CGRect(x:75,y:35,width:90,height:170),0.92),(CGRect(x:340,y:55,width:55,height:135),0.68),(CGRect(x:0,y:215,width:512,height:41),0.34)]{c.setFillColor(CGColor(gray:gray,alpha:1));c.fill(r)}
  let image=CIImage(cgImage:c.makeImage()!).applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:12]);return CIContext().createCGImage(image,from:CGRect(x:0,y:0,width:512,height:256))!
 }()
 static func lightStudio(_ scene:SCNScene){scene.lightingEnvironment.contents=studioEnvironment;scene.lightingEnvironment.intensity=0.40}
 static let insertionDuration:CGFloat=1.65
 static func insertionTime(_ model:String)->CGFloat{CGFloat(MediaLoadingMotion.duration(model))}
 static let mediaSpecs:[String:[String:Double]]={
  guard let root=Bundle.main.resourceURL,let bytes=try? Data(contentsOf:root.appendingPathComponent("Assets/media-slots.json")),let specs=(try? JSONSerialization.jsonObject(with:bytes)) as? [String:[String:Double]] else{return [:]};return specs
 }()
 /// One slot-space path on all platforms: pick up, align fully above the
 /// throat, then translate along its axis. Orientation follows the real slot.
 func placeCartridge(_ media:SCNNode,source:SCNVector3,progress:CGFloat,sourceScale:CGFloat=1,worldScale:CGFloat=1){
  guard let slot else{return}
  guard let spec=Self.mediaSpecs[model],let width=spec["cardWidth"],let ratio=spec["ratio"] else{return}
  let h=CGFloat(width*ratio/100),gap:CGFloat=0.12
  func ease(_ x:CGFloat)->CGFloat{let t=max(0,min(1,x));return t*t*t*(t*(t*6-15)+10)}
  let pickup=ease(progress/0.14),travel=ease((progress-0.14)/0.30),depthAlign=ease((progress-0.44)/0.14),push=ease((progress-0.58)/0.26)
  let aligned=simd_mul(slot.simdWorldOrientation,simd_quatf(angle:Self.cartridgeFacesBack(model) ? Float.pi:0,axis:SIMD3<Float>(0,1,0)))
  let above=slot.convertPosition(SCNVector3(0,h/2+gap,0),to:nil)
  let lifted=SCNVector3(CGFloat(source.x),CGFloat(source.y)+0.25*worldScale*pickup,4.0*worldScale)
  if progress<=0.58 {
   media.position=SCNVector3(CGFloat(lifted.x)+(CGFloat(above.x)-CGFloat(lifted.x))*travel,CGFloat(lifted.y)+(CGFloat(above.y)-CGFloat(lifted.y))*travel,CGFloat(lifted.z)+(CGFloat(above.z)-CGFloat(lifted.z))*depthAlign)
   media.simdOrientation=simd_slerp(simd_quatf(angle:-0.10,axis:SIMD3<Float>(1,0,0)),aligned,Float(travel))
   let q=sourceScale+(worldScale-sourceScale)*travel;media.scale=SCNVector3(q,q,q)
  }else{
   media.position=slot.convertPosition(SCNVector3(0,(h/2+gap)*(1-push)+Self.cartridgeSeatY(model,height:h)*push,0),to:nil);media.simdOrientation=aligned;media.scale=SCNVector3(worldScale,worldScale,worldScale)
  }
 }
 static let pspTraySeat=SCNVector3(0,1.39,-0.12)
 static let pspMediaOrientation=SCNVector3Zero
 static func spinSeatedDisc(_ media:SCNNode){guard let disc=media.childNode(withName:"umd-rotor",recursively:true),disc.action(forKey:"disc-spin")==nil else{return};disc.runAction(.repeatForever(.rotateBy(x:0,y:0,z:2 * .pi,duration:0.20)),forKey:"disc-spin")}
 static func cartridgeFacesBack(_ model:String)->Bool{["gba","gbc","nds","3ds"].contains(model)}
 static func cartridgeOrientation(_ model:String)->SCNVector3{SCNVector3(0,cartridgeFacesBack(model) ? CGFloat.pi:0,0)}
 static func cartridgeSeatY(_ model:String,height:CGFloat)->CGFloat{model=="gbc" ? -height*0.5:-height*0.49}
 var mediaTray:SCNNode?{hatch}
 /// UMD travels into the open door's guide cage, then rotates with that door.
 /// It never passes through a closed door or the rear casing.
 func placePSPMedia(_ media:SCNNode,source:SCNVector3,progress:CGFloat,worldScale:CGFloat=1,sourceScale:CGFloat?=nil){
  guard let tray=hatch else{return}
  func ease(_ x:CGFloat)->CGFloat{let t=max(0,min(1,x));return t*t*(3-2*t)}
  let travel=ease((progress-0.18)/0.32),push=ease((progress-0.50)/0.15)
  let above=tray.convertPosition(SCNVector3(0,1.39,-1.10),to:nil)
  if progress<=0.50 {
   let x=CGFloat(source.x)+(CGFloat(above.x)-CGFloat(source.x))*travel,y=CGFloat(source.y)+(CGFloat(above.y)-CGFloat(source.y))*travel,z=3.2*worldScale*(1-travel)+CGFloat(above.z)*travel
   media.position=SCNVector3(x,y,z)
   media.simdOrientation=simd_slerp(simd_quatf(angle:0,axis:SIMD3<Float>(0,1,0)),tray.simdWorldOrientation,Float(travel))
  }else{
   media.position=tray.convertPosition(SCNVector3(0,1.39,-1.10+(CGFloat(Self.pspTraySeat.z)+1.10)*push),to:nil);media.simdOrientation=tray.simdWorldOrientation;media.childNode(withName:"umd-rotor",recursively:true)?.eulerAngles.z = .init(MediaLoadingMotion.spinAngle(Double(progress)))
  }
  let initial=sourceScale ?? 0.90*worldScale,q=initial+(0.90*worldScale-initial)*travel;media.scale=SCNVector3(q,q,q)
 }
 static func exists(_ model:String,_ theme:Int)->Bool{FileManager.default.fileExists(atPath:directory.appendingPathComponent(model+"-"+String(theme==3 && model != "gba" ? 0:theme)+".scn").path)}
 init?(model:String,theme:Int){
  self.model=model;self.theme=theme
  guard let scene=try? SCNScene(url:Self.directory.appendingPathComponent(model+"-"+String(theme==3 && model != "gba" ? 0:theme)+".scn"),options:nil),let loaded=scene.rootNode.childNode(withName:"device",recursively:false) else{return nil}
  device=loaded;root.addChildNode(device)
  if let bytes=try? Data(contentsOf:Self.directory.appendingPathComponent("geometry.json")),let all=(try? JSONSerialization.jsonObject(with:bytes)) as? [String:[String:Any]],let data=all[model],let xy=data["size"] as? [Double]{size=CGSize(width:xy[0],height:xy[1]);screens=(data["screens"] as? [[Double]] ?? []).map{CGRect(x:$0[0],y:$0[1],width:$0[2],height:$0[3])}}
  // Allow clearance for the carrier plus its raised label/brand surfaces.
  if let slot=device.childNode(withName:"slot",recursively:true){if model=="gba"{slot.position.z = -0.54}else if model=="gbc"{slot.position.z = -0.80}else if model=="nds" || model=="3ds"{slot.position.z = -0.32}}
  var materials:[SCNMaterial]=[]
  device.enumerateChildNodes{node,_ in
   if let name=node.name,name.hasPrefix("key:"),let id=Int(name.dropFirst(4)){self.keys[id]=node;self.rest[id]=node.position}
   if node.name=="power-slider"{self.powerSlider=node;self.powerRest=node.position}
   if node.name=="dpad"{self.cross=node}
   if node.name=="lid"{self.lid=node}
   if node.name=="hatch"{self.hatch=node}
   if node.name=="stick"{self.stick=node;self.stickRest=node.position}
   if let name=node.name,name.hasPrefix("screen:"),let material=node.geometry?.firstMaterial{material.name=name;materials.append(material)}
  }
  device.enumerateChildNodes{node,_ in
   guard node.name?.hasPrefix("screen:") == true,let panel=node.geometry as? SCNPlane else{return}
   let magnification=Self.screenScale(model);node.scale=SCNVector3(magnification,magnification,1)
   let surround=SCNPlane(width:panel.width+0.075,height:panel.height+0.075),ink=SCNMaterial();ink.diffuse.contents=CGColor(gray:0.025,alpha:1);ink.lightingModel = .constant;surround.materials=[ink]
   let border=SCNNode(geometry:surround);border.position.z = -0.003;node.addChildNode(border)
  }
  if model=="gba" {
   // Board-facing contacts follow the GBA board photo, not a repeated chip grid.
   for node in device.childNodes {
    if let box=node.geometry as? SCNBox,abs(CGFloat(node.position.z)+0.13)<0.002 && abs(box.width-0.46)<0.002{node.removeFromParentNode()}
    if let box=node.geometry as? SCNBox,abs(box.width-0.018)<0.002 && abs(box.height-0.36)<0.002{node.removeFromParentNode()}
   }
   func boardPoint(_ x:CGFloat,_ y:CGFloat,_ z:CGFloat)->SCNVector3{SCNVector3((x-size.width/2)/100,(size.height/2-y)/100,z)}
   // Remove the obsolete parallel trace strips from earlier baked boards.
   for node in device.childNodes{if let box=node.geometry as? SCNBox,abs(box.width-1.30)<0.002,abs(box.height-0.012)<0.002{node.removeFromParentNode()}}
   // A single board wraps the controls, with the lower battery cut-out visible
   // through the case. It is a form study of the original AGB board, not two blocks.
   for node in device.childNodes{if let box=node.geometry as? SCNBox,abs(box.width-1.65)<0.002 && abs(box.height-2.35)<0.002{node.removeFromParentNode()}}
   #if canImport(UIKit)
   let outline=UIBezierPath()
   #else
   let outline=NSBezierPath()
   #endif
   let outlinePoints:[CGPoint]=[CGPoint(x:98,y:72),CGPoint(x:250,y:58),CGPoint(x:468,y:58),CGPoint(x:616,y:72),CGPoint(x:645,y:115),CGPoint(x:638,y:302),CGPoint(x:604,y:328),CGPoint(x:472,y:325),CGPoint(x:470,y:238),CGPoint(x:278,y:238),CGPoint(x:278,y:326),CGPoint(x:116,y:326),CGPoint(x:80,y:300),CGPoint(x:76,y:120)]
   for (index,p) in outlinePoints.enumerated(){let q=CGPoint(x:(p.x-size.width/2)/100,y:(size.height/2-p.y)/100)
    if index==0{outline.move(to:q)}else{
     #if canImport(UIKit)
     outline.addLine(to:q)
     #else
     outline.line(to:q)
     #endif
    }
   };outline.close()
   let pcbMaterial=SCNMaterial();pcbMaterial.diffuse.contents=CGColor(red:0.16,green:theme==2 ? 0.34:0.29,blue:0.22,alpha:1);pcbMaterial.lightingModel = .physicallyBased;pcbMaterial.roughness.contents=0.86
   let board=SCNShape(path:outline,extrusionDepth:0.025);board.chamferRadius=0.006;board.materials=[pcbMaterial];let pcbNode=SCNNode(geometry:board);pcbNode.name="pcb-form";pcbNode.position.z = -0.18;device.addChildNode(pcbNode)
   let silicon=SCNMaterial();silicon.diffuse.contents=CGColor(gray:0.075,alpha:1);silicon.lightingModel = .physicallyBased;silicon.roughness.contents=0.82
   for (x,y,w,h) in [(350.0,130.0,70.0,62.0),(448,115,42,48),(223,136,14,38)]{let g=SCNBox(width:w/100,height:h/100,length:0.04,chamferRadius:0.01);g.materials=[silicon];let n=SCNNode(geometry:g);n.position=boardPoint(x,y,-0.14);device.addChildNode(n)}
   let copper=SCNMaterial();copper.diffuse.contents=CGColor(red:0.43,green:0.51,blue:0.34,alpha:1);copper.lightingModel = .physicallyBased;copper.roughness.contents=0.85
   let routes:[[(CGFloat,CGFloat)]]=[[(87,196),(71,196),(71,118),(177,118),(177,104),(265,104)],[(115,168),(115,130),(153,130),(153,88),(282,88)],[(115,224),(153,224),(153,260),(211,260)],[(130,315),(190,315),(190,290),(260,290)],[(632,161),(650,161),(650,104),(510,104)],[(588,201),(553,201),(553,267),(485,267)],[(600,286),(547,286),(547,310),(480,310)]]
   for route in routes {for (a,b) in zip(route,route.dropFirst()){let line=SCNBox(width:max(0.008,abs(b.0-a.0)/100),height:max(0.008,abs(b.1-a.1)/100),length:0.004,chamferRadius:0.001);line.materials=[copper];let n=SCNNode(geometry:line);n.name="internal:agb-trace";n.position=boardPoint((a.0+b.0)/2,(a.1+b.1)/2,-0.151);device.addChildNode(n)}}
   let contact=SCNMaterial();contact.diffuse.contents=CGColor(gray:0.16,alpha:1);contact.lightingModel = .physicallyBased;contact.roughness.contents=0.65
   for (x,y) in [(115.0,168.0),(115,224),(87,196),(143,196),(588,201),(632,161)]{
    let disc=SCNCylinder(radius:0.14,height:0.016);disc.materials=[contact];let n=SCNNode(geometry:disc);n.eulerAngles.x = .pi/2;n.position=boardPoint(x,y,-0.12);device.addChildNode(n)
   }
   let speaker=SCNMaterial();speaker.diffuse.contents=CGColor(gray:0.25,alpha:1);speaker.metalness.contents=0.6;speaker.roughness.contents=0.55
   for radius:CGFloat in [0.17,0.23,0.30]{let ring=SCNTorus(ringRadius:radius,pipeRadius:0.022);ring.materials=[speaker];let n=SCNNode(geometry:ring);n.eulerAngles.x = .pi/2;n.position=boardPoint(600,286,-0.12);device.addChildNode(n)}
   let noise=CIFilter(name:"CIRandomGenerator")!.outputImage!.cropped(to:CGRect(x:0,y:0,width:256,height:256)).applyingFilter("CIColorMatrix",parameters:["inputRVector":CIVector(x:0.08,y:0,z:0,w:0),"inputGVector":CIVector(x:0,y:0.08,z:0,w:0),"inputBVector":CIVector(x:0,y:0,z:0,w:0),"inputBiasVector":CIVector(x:0.46,y:0.46,z:1,w:1)])
   let grain=CIContext().createCGImage(noise,from:noise.extent)
   device.enumerateChildNodes{node,_ in if let plane=node.geometry as? SCNPlane,plane.width>7,node.parent === device{node.isHidden=true}
    guard node.name=="front-shell",let material=node.geometry?.firstMaterial else{return};node.opacity=self.theme==1 ? 0.86:self.theme==3 ? 0.88:1;node.renderingOrder=10;material.transparency=1;material.isDoubleSided=false;material.writesToDepthBuffer=false;material.transparencyMode = .aOne;material.normal.contents=grain;material.normal.intensity=0.32;material.roughness.contents=self.theme==1 || self.theme==3 ? 0.60:0.40}
  }
  if model=="psp",let stick{for node in stick.childNodes{if let box=node.geometry as? SCNBox,box.height<0.01{node.position.y=0.048}}}
  if model=="psp",let tray=hatch {
   let metal=SCNMaterial();metal.diffuse.contents=CGColor(gray:0.52,alpha:1);metal.lightingModel = .physicallyBased;metal.metalness.contents=0.8;metal.roughness.contents=0.38
   for x:CGFloat in [-1.285,1.285]{let guide=SCNBox(width:0.035,height:2.42,length:0.12,chamferRadius:0.01);guide.materials=[metal];let n=SCNNode(geometry:guide);n.position=SCNVector3(x,1.33,-0.20);tray.addChildNode(n)}
   let stop=SCNBox(width:2.60,height:0.045,length:0.12,chamferRadius:0.01);stop.materials=[metal];let n=SCNNode(geometry:stop);n.position=SCNVector3(0,0.10,-0.20);tray.addChildNode(n)
  }
  if let cross,let shape=cross.geometry as? SCNShape {
   shape.extrusionDepth=model=="gbc" ? 0.16:13;shape.chamferRadius=model=="gbc" ? 0.03:1.8
   if model=="gbc"{cross.position.z -= 0.035}
   for groove in cross.childNodes{if model=="gbc"{groove.position.z=0.084}else{groove.position.z+=3.3}}
  }
  buildPhysicalShoulders()
  buildKeyWells()
  applySurfaceFinish()
  buildRearDetails()
  buildEdgeDetails()
  if model=="psp"{buildPSPPhysicalDetails();configurePSPFinish();buildPSPStick()}
  if theme==3 && model != "gba"{configureBlackFrost()}
  if theme==3 || model=="gba"{buildPassiveComponents();softenTransmittedDetail()}
  if model=="gba"{configureGBAFinish();buildGBAFrontDetails()}
  screenMaterials=materials.sorted{($0.name ?? "")<($1.name ?? "")}
 }
 private var focusMaterials:[SCNMaterial]?,focusWeight:CGFloat = -1
 func setDisplayFocus(_ weight:CGFloat){
  let value=(max(0.24,min(1,weight))*40).rounded()/40
  guard abs(value-focusWeight)>0.01 else{return};focusWeight=value
  if focusMaterials==nil {var copied=[SCNMaterial]();device.enumerateChildNodes{node,_ in guard let g=node.geometry else{return};let own=g.copy() as! SCNGeometry;own.materials=g.materials.map{let m=$0.copy() as! SCNMaterial;copied.append(m);return m};node.geometry=own};focusMaterials=copied;var live=[SCNMaterial]();device.enumerateChildNodes{n,_ in if n.name?.hasPrefix("screen:")==true,let m=n.geometry?.firstMaterial{live.append(m)}};screenMaterials=live.sorted{($0.name ?? "")<($1.name ?? "")}}
  for m in focusMaterials ?? []{m.multiply.contents=CGColor(gray:value,alpha:1)}
 }
 var slot:SCNNode?{device.childNode(withName:"slot",recursively:true)}
 /// Dedicated neutral black-frost edition. Case, electronics and controls are
 /// separate geometry; theme artwork is not painted black and reused as a shell.
 private func configureBlackFrost(){
  let plastic=SCNMaterial();plastic.lightingModel = .physicallyBased;plastic.diffuse.contents=model=="psp" ? CGColor(red:0.055,green:0.065,blue:0.078,alpha:1):CGColor(red:0.20,green:0.22,blue:0.24,alpha:1);plastic.roughness.contents=0.68;plastic.fresnelExponent=1.5;plastic.specular.contents=CGColor(gray:0.65,alpha:1);plastic.writesToDepthBuffer=false
  var shellNodes:[SCNNode]=[]
  device.enumerateChildNodes{node,_ in
   guard let geometry=node.geometry else{return}
   if node.name=="curved-grip-print"{node.isHidden=true;return}
   if node.name=="pcb-form" || node.name=="psp-metal-perimeter" || node.name=="umd-brushed-metal-annulus" || node.name?.hasPrefix("internal:")==true{return}
   let bounds=geometry.boundingBox,low=node.convertPosition(bounds.min,to:device),high=node.convertPosition(bounds.max,to:device),w=abs(CGFloat(high.x-low.x)),h=abs(CGFloat(high.y-low.y))
   if geometry is SCNPlane,w>2.5,h>2.5,node.name?.hasPrefix("screen:") != true,node.parent?.name?.hasPrefix("screen:") != true{node.isHidden=true;return}
   let shell=node.name=="curved-rear-grip" || node.name=="battery-door" || node.name=="front-shell-sidewall" || (geometry is SCNShape && w>3 && h>2.5) || (geometry is SCNBox && ((w>5 && h>3) || (node.parent?.name=="hatch" && w>2.5 && h>2.5)))
   if shell {shellNodes.append(node);let m=plastic.copy() as! SCNMaterial;geometry.materials=geometry.materials.map{_ in m};node.opacity=model=="psp" ? 0.89:(model=="nds" || model=="3ds" ? 0.83:0.78);node.renderingOrder=10;m.transparencyMode = .aOne;m.isDoubleSided=false}
   var ancestor:SCNNode?=node,isControl=false;while let n=ancestor{if n.name?.hasPrefix("key:")==true || n.name=="dpad" || n.name=="stick"{isControl=true;break};ancestor=n.parent}
   if model=="gbc",let shape=geometry as? SCNShape,shape.extrusionDepth<0.03,w<2.5,h<0.5 {let neutral=plastic.copy() as! SCNMaterial;neutral.writesToDepthBuffer=true;geometry.materials=geometry.materials.map{_ in neutral}}
   if isControl && !(geometry is SCNPlane){let ink=SCNMaterial();ink.diffuse.contents=CGColor(gray:0.10,alpha:1);ink.lightingModel = .physicallyBased;ink.roughness.contents=0.4;geometry.materials=geometry.materials.map{_ in ink}}
  }
  if model != "gba" {buildInternalAssembly()}
  if model=="psp" {
   device.enumerateChildNodes{n,_ in if n.name?.hasPrefix("internal:")==true{n.opacity=0.24;n.geometry?.materials.forEach{$0.roughness.contents=0.95}}}
   // Keep the optical surround opaque and the rear door legible through resin.
   device.enumerateChildNodes{n,_ in if n.name=="psp-lcd-surround"{n.opacity=1;n.geometry?.materials.forEach{$0.diffuse.contents=CGColor(gray:0.025,alpha:1)}};if n.parent?.name=="hatch",n.geometry is SCNTorus{n.geometry?.materials.forEach{$0.diffuse.contents=CGColor(gray:0.52,alpha:1)}}}
   let g=SCNPlane(width:1.05,height:0.24),m=SCNMaterial();m.diffuse.contents=SpatialImage(contentsOfFile:Self.directory.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Logos/psp-home.png").path);m.lightingModel = .constant;g.materials=[m];let mark=SCNNode(geometry:g);mark.name="psp-frost-logo";mark.position=SCNVector3(0,-1.15,0.047);device.addChildNode(mark)
   let backMark=mark.clone();backMark.name="psp-frost-rear-logo";backMark.position=SCNVector3(0,1.33,0.025);hatch?.addChildNode(backMark)
  }
  if model=="gbc" {
   let imageSize=CGSize(width:350,height:570)
   func paint(){
    #if canImport(UIKit)
    let font=UIFont.italicSystemFont(ofSize:15),ink=UIColor(white:0.74,alpha:1)
    #else
    let font=NSFont.systemFont(ofSize:15,weight:.bold),ink=NSColor(white:0.74,alpha:1)
    #endif
    ("GAME BOY COLOR" as NSString).draw(at:CGPoint(x:94,y:269),withAttributes:[.font:font,.foregroundColor:ink])
   }
   #if canImport(UIKit)
   let legend=UIGraphicsImageRenderer(size:imageSize).image{_ in paint()}
   #else
   let legend=NSImage(size:imageSize);legend.lockFocusFlipped(true);paint();legend.unlockFocus()
   #endif
   let g=SCNPlane(width:3.5,height:5.7),m=SCNMaterial();m.diffuse.contents=legend;m.lightingModel = .constant;m.writesToDepthBuffer=false;g.materials=[m];let ink=SCNNode(geometry:g);ink.name="frost-bezel-legend";ink.position=SCNVector3(0,0.05,0.132);device.addChildNode(ink)
  }
  // Fine normal grain breaks up the surface highlight while keeping the interior legible.
  let noise=CIFilter(name:"CIRandomGenerator")!.outputImage!.cropped(to:CGRect(x:0,y:0,width:128,height:128)).applyingFilter("CIColorMatrix",parameters:["inputRVector":CIVector(x:0.08,y:0,z:0,w:0),"inputGVector":CIVector(x:0,y:0.08,z:0,w:0),"inputBVector":CIVector(x:0,y:0,z:0,w:0),"inputBiasVector":CIVector(x:0.46,y:0.46,z:1,w:1)])
  let grain=CIContext().createCGImage(noise,from:noise.extent)
  for node in shellNodes{for material in node.geometry!.materials{material.normal.contents=grain;material.normal.intensity=0.18}}
 }
 /// Distinct board silhouettes and functional assemblies, kept separate from
 /// the translucent casing. Dimensions are a structural study, not OEM CAD.
 private func buildInternalAssembly(){
  let boardInk=SCNMaterial();boardInk.diffuse.contents=CGColor(red:model=="gbc" ? 0.53:0.15,green:model=="gbc" ? 0.57:0.30,blue:model=="gbc" ? 0.52:0.22,alpha:1);boardInk.lightingModel = .physicallyBased;boardInk.roughness.contents=0.82
  let chipInk=SCNMaterial();chipInk.diffuse.contents=CGColor(gray:0.105,alpha:1);chipInk.lightingModel = .physicallyBased;chipInk.roughness.contents=0.7
  let metal=SCNMaterial();metal.diffuse.contents=CGColor(gray:0.38,alpha:1);metal.lightingModel = .physicallyBased;metal.metalness.contents=0.7;metal.roughness.contents=0.6
  let gold=SCNMaterial();gold.diffuse.contents=CGColor(red:0.47,green:0.40,blue:0.23,alpha:1);gold.lightingModel = .physicallyBased;gold.metalness.contents=0.65;gold.roughness.contents=0.7
  func point(_ x:CGFloat,_ y:CGFloat,_ z:CGFloat)->SCNVector3{SCNVector3((x-size.width/2)/100,(size.height/2-y)/100,z)}
  let z:CGFloat=model=="gbc" ? -0.34:-0.12
  func block(_ name:String,_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat,_ depth:CGFloat,_ ink:SCNMaterial,_ offset:CGFloat=0){let box=SCNBox(width:w/100,height:h/100,length:depth,chamferRadius:min(0.018,depth/3));box.materials=[ink];let n=SCNNode(geometry:box);n.name="internal:"+name;n.position=point(x,y,z+offset);device.addChildNode(n)}
  func board(_ name:String,_ points:[CGPoint]){
   #if canImport(UIKit)
   let path=UIBezierPath()
   #else
   let path=NSBezierPath()
   #endif
   for (i,p) in points.enumerated(){let q=CGPoint(x:(p.x-size.width/2)/100,y:(size.height/2-p.y)/100);if i==0{path.move(to:q)}else{
    #if canImport(UIKit)
    path.addLine(to:q)
    #else
    path.line(to:q)
    #endif
   }};path.close();let shape=SCNShape(path:path,extrusionDepth:0.026);shape.chamferRadius=0.004;shape.materials=[boardInk];let n=SCNNode(geometry:shape);n.name="internal:"+name;n.position=SCNVector3(0,0,z);device.addChildNode(n)
  }
  func contact(_ x:CGFloat,_ y:CGFloat,_ radius:CGFloat){let g=SCNCylinder(radius:radius/100,height:0.012);g.materials=[chipInk];let n=SCNNode(geometry:g);n.name="internal:contact";n.eulerAngles.x = .pi/2;n.position=point(x,y,z+0.035);device.addChildNode(n)}
  func speaker(_ x:CGFloat,_ y:CGFloat,_ radius:CGFloat){
   let cone=SCNCylinder(radius:radius/100,height:0.055);cone.materials=[metal];let n=SCNNode(geometry:cone);n.name="internal:speaker-diaphragm";n.eulerAngles.x = .pi/2;n.position=point(x,y,z+0.035);device.addChildNode(n)
   for r in [radius*0.93,radius*0.72,radius*0.35]{let g=SCNTorus(ringRadius:r/100,pipeRadius:0.012);g.materials=[chipInk];let n=SCNNode(geometry:g);n.name="internal:speaker-surround";n.eulerAngles.x = .pi/2;n.position=point(x,y,z+0.07);device.addChildNode(n)}
  }
  func connector(_ x:CGFloat,_ y:CGFloat,_ width:CGFloat){block("cartridge-connector",x,y,width,18,0.065,chipInk,-0.035);for i in 0..<16{block("connector-pin",x-width*0.45+CGFloat(i)*width*0.06,y,width*0.025,11,0.014,gold,0.005)}}
  switch model {
  case "gbc":
   board("cgb-mainboard",[CGPoint(x:47,y:54),CGPoint(x:330,y:54),CGPoint(x:341,y:91),CGPoint(x:333,y:350),CGPoint(x:345,y:384),CGPoint(x:335,y:460),CGPoint(x:312,y:555),CGPoint(x:50,y:555),CGPoint(x:44,y:440),CGPoint(x:39,y:360)])
   block("cpu-cgb",167,294,55,55,0.045,chipInk,0.04);block("work-ram",232,291,25,45,0.04,chipInk,0.04);block("audio-amplifier",288,461,24,17,0.035,chipInk,0.04)
   for (x,y) in [(92.0,374.0),(92,430),(64,402),(120,402),(244,420),(300,394)]{contact(x,y,10)}
   connector(190,61,200);speaker(285,521,30)
   // Matte solder-mask, dense SMD power/audio areas, and silicone key membranes.
   let silicone=SCNMaterial();silicone.diffuse.contents=CGColor(gray:0.46,alpha:1);silicone.lightingModel = .physicallyBased;silicone.roughness.contents=0.92
   for (x,y,r) in [(92.0,407.0,51.0),(244,425,30),(300,399,30)]{let pad=SCNCylinder(radius:r/100,height:0.026);pad.materials=[silicone];let n=SCNNode(geometry:pad);n.name="internal:silicone-key-membrane";n.eulerAngles.x = .pi/2;n.position=point(x,y,z+0.08);device.addChildNode(n)}
   for (x,y) in [(51.0,354.0),(168,355),(337,351),(51,458),(172,457),(337,455),(50,568),(333,568)]{
    let post=SCNTube(innerRadius:0.024,outerRadius:0.055,height:0.20);let resin=SCNMaterial();resin.diffuse.contents=CGColor(gray:0.5,alpha:0.6);resin.lightingModel = .physicallyBased;resin.roughness.contents=0.5;post.materials=[resin];let n=SCNNode(geometry:post);n.name="internal:screw-boss";n.eulerAngles.x = .pi/2;n.position=point(x,y,-0.15);device.addChildNode(n)
   }
   // Two AA cells belong behind the lower board, with separate end contacts.
   for y:CGFloat in [492,548]{let cell=SCNCylinder(radius:0.29,height:1.8);cell.materials=[metal];let n=SCNNode(geometry:cell);n.name="internal:aa-cell";n.eulerAngles.z = .pi/2;n.position=point(190,y,-0.65);device.addChildNode(n)}
   for x:CGFloat in [95,285]{for y:CGFloat in [492,548]{block("battery-terminal",x,y,8,48,0.025,gold,-0.30)}}
  case "psp":
   board("psp-mainboard",[CGPoint(x:445,y:61),CGPoint(x:605,y:61),CGPoint(x:650,y:88),CGPoint(x:662,y:226),CGPoint(x:633,y:264),CGPoint(x:558,y:267),CGPoint(x:548,y:240),CGPoint(x:445,y:240)])
   board("psp-dpad-board",[CGPoint(x:62,y:85),CGPoint(x:168,y:85),CGPoint(x:168,y:194),CGPoint(x:146,y:220),CGPoint(x:70,y:215)])
   block("lcd-metal-back",360,160,329,184,0.035,metal,-0.045);block("battery-pack",120,236,101,75,0.15,chipInk,-0.10)
   block("allegrex",484,154,47,47,0.045,chipInk,0.045);block("memory",487,210,35,24,0.04,chipInk,0.045);block("power-management",634,219,20,25,0.03,chipInk,0.045)
   for (x,y) in [(609.0,112.0),(579,143),(639,143),(609,174),(106,118),(106,166),(82,142),(130,142)]{contact(x,y,7)}
   speaker(173,252,13);speaker(547,252,13)
  default:
   let three=model=="3ds"
   board(three ? "ctr-mainboard":"usg-mainboard",[CGPoint(x:76,y:395),CGPoint(x:199,y:391),CGPoint(x:199,y:408),CGPoint(x:528,y:408),CGPoint(x:528,y:391),CGPoint(x:640,y:397),CGPoint(x:651,y:619),CGPoint(x:623,y:666),CGPoint(x:470,y:668),CGPoint(x:470,y:643),CGPoint(x:268,y:643),CGPoint(x:268,y:669),CGPoint(x:89,y:664),CGPoint(x:68,y:631)])
   block(three ? "soc":"arm9-arm7",166,593,48,47,0.045,chipInk,0.04);block("work-ram",168,636,29,19,0.03,chipInk,0.04);block("wireless-module",567,648,40,24,0.05,metal,0.03)
   block("battery-pack",148,535,95,129,0.11,chipInk,-0.12);connector(360,391,178)
   let controls=model=="3ds" ? [(119.0,536.0),(119,582),(96,559),(142,559),(606,520),(572,487),(640,487),(606,454)]:[(122.0,473.0),(122,534),(92,504),(153,504),(605,518),(569,483),(641,483),(605,448)]
   for (x,y) in controls{contact(x,y,8)}
   if let lid {buildUpperAssembly(lid)}
  }
 }
 /// Frosted shells transmit low-contrast forms, not a debug view of every
 /// solder joint. Keep the assemblies volumetric while suppressing fine noise.
 private func applySurfaceFinish(){
  guard ["nds","3ds","psp"].contains(model) else{return}
  device.enumerateChildNodes{n,_ in guard let g=n.geometry else{return}
   if let plane=g as? SCNPlane {if plane.width>5.5,plane.height>2.5,n.name?.hasPrefix("screen:") != true{g.materials.forEach{$0.roughness.contents=0.11;$0.specular.contents=CGColor(gray:0.65,alpha:1)}};return}
   let box=g.boundingBox,w=CGFloat(box.max.x-box.min.x),h=CGFloat(box.max.y-box.min.y)
   let housing=n.name=="front-shell" || n.name=="rear-shell-with-bay" || n.name=="curved-rear-grip" || n.name=="rear-shell-with-cartridge-pocket" || n.name=="rear-pocket-cover" || (g is SCNBox && w>5 && h>3) || (n.parent?.name=="hatch" && w>2.5 && h>2.5)
   guard housing else{return}
   for m in g.materials {m.lightingModel = .physicallyBased;m.roughness.contents=self.model=="psp" && self.theme==0 ? 0.26:0.11;m.metalness.contents=self.model=="psp" && self.theme==0 ? 0.20:0;m.specular.contents=CGColor(gray:0.72,alpha:1);m.fresnelExponent=2.4}
  }
 }
 /// A continuous injection-moulded case shares one albedo and finish. Artwork
 /// remains a shallow print, never a second reflective shell.
 private func configurePSPFinish(){
  guard theme != 3,let tint=device.childNode(withName:"front-shell",recursively:true)?.geometry?.firstMaterial?.diffuse.contents else{return}
  device.enumerateChildNodes{n,_ in guard let g=n.geometry else{return}
   if ["front-shell","rear-shell-with-bay","curved-rear-grip","umd-door-shell"].contains(n.name ?? "") {
    n.opacity=1
    for m in g.materials{m.diffuse.contents=tint;m.transparency=1;m.writesToDepthBuffer=true;m.lightingModel = .physicallyBased;m.roughness.contents=self.theme==0 ? 0.28:0.19;m.metalness.contents=0;m.specular.contents=CGColor(gray:0.55,alpha:1)}
   }
   if n.name=="curved-grip-print" || n.name=="umd-door-print" {
    for m in g.materials{m.lightingModel = .physicallyBased;m.roughness.contents=self.theme==0 ? 0.64:0.80;m.metalness.contents=0;m.specular.contents=CGColor(gray:0.12,alpha:1);m.normal.intensity=self.theme==0 ? 0.16:0;m.writesToDepthBuffer=false;m.shaderModifiers=[.fragment:"#pragma body\nif (_surface.diffuse.a < 0.04) discard_fragment();\n_output.color.a = _surface.diffuse.a;"]}
   }
  }
 }
 private func buildKeyWells(){
  for (id,key) in keys where id != 10 && id != 11 {
   guard let g=key.geometry,let parent=key.parent else{continue}
   let unit:CGFloat=model=="gbc" ? 0.01:1,well:SCNGeometry
   if let round=g as? SCNCylinder{well=SCNCylinder(radius:round.radius+unit,height:unit*0.75)}
   else{let b=g.boundingBox,w=CGFloat(b.max.x-b.min.x)+unit*1.5,h=CGFloat(b.max.y-b.min.y)+unit*1.5,rect=CGRect(x:-w/2,y:-h/2,width:w,height:h),radius=g is SCNShape ? min(w,h)/2:unit*3
    #if canImport(UIKit)
    let path=UIBezierPath(roundedRect:rect,cornerRadius:radius)
    #else
    let path=NSBezierPath(roundedRect:rect,xRadius:radius,yRadius:radius)
    #endif
    well=SCNShape(path:path,extrusionDepth:unit*0.75)
   }
   let m=SCNMaterial();m.lightingModel = .physicallyBased;m.diffuse.contents=CGColor(gray:0.035,alpha:1);m.roughness.contents=0.74;well.materials=[m]
   let n=SCNNode(geometry:well);n.name="key-well:"+String(id);n.position=SCNVector3(CGFloat(key.position.x),CGFloat(key.position.y),CGFloat(key.position.z)-unit*3.5);if g is SCNCylinder{n.eulerAngles.x = .pi/2};parent.addChildNode(n)
  }
 }
 private func buildPhysicalShoulders(){
  guard model != "gbc" else{return}
  for id in [10,11]{
   keys[id]?.isHidden=true
   if model=="gba"{buildGBAShoulder(id);continue}
   let right=id==11,dual=model=="nds" || model=="3ds"
   let x:CGFloat=right ? (model=="psp" ? 601:dual ? 631:626):(model=="psp" ? 119:dual ? 89:94)
   let y:CGFloat=dual ? 365:model=="psp" ? 47:46
   let width:CGFloat=dual ? 0.72:model=="psp" ? 0.95:0.84,depth:CGFloat=model=="gba" ? 0.60:model=="psp" ? 0.42:0.34
   #if canImport(UIKit)
   let path=UIBezierPath(roundedRect:CGRect(x:-width/2,y:-0.08,width:width,height:0.16),cornerRadius:0.07)
   #else
   let path=NSBezierPath(roundedRect:CGRect(x:-width/2,y:-0.08,width:width,height:0.16),xRadius:0.07,yRadius:0.07)
   #endif
   if model=="psp"{
    path.removeAllPoints()
    let points=[CGPoint(x:-0.48,y:-0.07),CGPoint(x:-0.48,y:0.00),CGPoint(x:-0.29,y:0.16),CGPoint(x:0.42,y:0.16),CGPoint(x:0.48,y:-0.07)]
    for (i,p) in points.enumerated(){let q=CGPoint(x:right ? -p.x:p.x,y:p.y);if i==0{path.move(to:q)}else{
     #if canImport(UIKit)
     path.addLine(to:q)
     #else
     path.line(to:q)
     #endif
    }};path.close()
   }
   path.flatness=0.002
   let g=SCNShape(path:path,extrusionDepth:depth);g.chamferRadius=0.025
   let resin=SCNMaterial();resin.lightingModel = .physicallyBased;resin.diffuse.contents=CGColor(gray:model=="psp" && theme==0 ? 0.72:0.33,alpha:1);resin.roughness.contents=model=="psp" ? 0.21:0.36;if model=="psp",theme==1{resin.diffuse.contents=CGColor(red:0.64,green:0.55,blue:0.29,alpha:1);resin.metalness.contents=0.25};if model=="gba"{resin.diffuse.contents=self.gbaButtonColor};resin.specular.contents=CGColor(gray:0.70,alpha:1);g.materials=[resin]
   let key=SCNNode(geometry:g);key.name="physical-shoulder:"+String(id);key.position=SCNVector3((x-size.width/2)/100,(size.height/2-y)/100,model=="gba" ? -0.27:model=="psp" ? -0.29:-0.26);device.addChildNode(key);physicalShoulders[id]=key
   // A hinge pin and end seam sit inside the shoulder cap, not on the LCD face.
   let pin=SCNCylinder(radius:0.035,height:width*0.76);let metal=SCNMaterial();metal.diffuse.contents=CGColor(gray:0.30,alpha:1);metal.metalness.contents=0.65;metal.roughness.contents=0.34;pin.materials=[metal];let axle=SCNNode(geometry:pin);axle.eulerAngles.z = .pi/2;axle.position.z = .init(-depth/2+0.025);key.addChildNode(axle)
  }
 }
 /// The AGB shoulder is a curved top-edge paddle, not a bar extruded off the face.
 /// Sample the same top contour as the rolled shell; its outside end drops with
 /// the corner. A fixed saddle joins the case, while the cap pivots at the rear.
 private func buildGBAShoulder(_ id:Int){
  let side:CGFloat=id==11 ? 1:-1
  func top(_ x:CGFloat)->CGFloat{
   func cubic(_ a:CGFloat,_ b:CGFloat,_ c:CGFloat,_ d:CGFloat,_ t:CGFloat)->CGFloat{let u=1-t;return u*u*u*a+3*u*u*t*b+3*u*t*t*c+t*t*t*d}
   var lo:CGFloat=0,hi:CGFloat=1
   if x<=2.98{for _ in 0..<24{let t=(lo+hi)/2;if cubic(1.36,1.88,2.82,2.98,t)<x{lo=t}else{hi=t}};return cubic(1.58,1.62,1.66,1.36,(lo+hi)/2)}
   hi=0.25;for _ in 0..<24{let t=(lo+hi)/2;if cubic(2.98,3.24,3.27,3.10,t)<x{lo=t}else{hi=t}};return cubic(1.36,0.95,-0.76,-1.20,(lo+hi)/2)
  }
  let pivot=SCNVector3(side*2.60,top(2.60)-0.085,-0.60)
  func paddle(_ seat:Bool)->SCNGeometry{
   let cols=32,rows=16,stride=cols+1,layer=(cols+1)*(rows+1)
   var vertices=[SCNVector3](),indices=[Int32]()
   for surface in 0...1{for row in 0...rows{let v=CGFloat(row)/CGFloat(rows),z:CGFloat = seat ? -0.643+v*0.581:-0.655+v*0.605
    let rounded=(seat ? 0.012:0)+0.055*(1-sqrt(max(0,1-pow((v-0.5)*2,2))))
    for col in 0...cols{let u=CGFloat(col)/CGFloat(cols),x=2.13+rounded+u*(0.93-2*rounded)
     let crown=0.025*sin(.pi*v)*sin(.pi*u),y=top(x)+(seat ? -0.12:-0.005)+(surface==1 ? crown+(seat ? 0:0.025):seat ? -0.14:-0.13)
     vertices.append(SCNVector3(side*x-CGFloat(pivot.x),y-CGFloat(pivot.y),z-CGFloat(pivot.z)))
    }
   }}
   func quad(_ a:Int,_ b:Int,_ c:Int,_ d:Int){indices += [Int32(a),Int32(b),Int32(c),Int32(b),Int32(d),Int32(c)]}
   for row in 0..<rows{for col in 0..<cols{let a=row*stride+col;quad(a,a+stride,a+1,a+stride+1);quad(layer+a,layer+a+1,layer+a+stride,layer+a+stride+1)}}
   for col in 0..<cols{quad(col,col+1,layer+col,layer+col+1);let a=rows*stride+col;quad(a,layer+a,a+1,layer+a+1)}
   for row in 0..<rows{let a=row*stride,b=a+cols;quad(a,layer+a,a+stride,layer+a+stride);quad(b,b+stride,layer+b,layer+b+stride)}
   if side>0{for i in Swift.stride(from:0,to:indices.count,by:3){indices.swapAt(i+1,i+2)}}
   var normals=[SIMD3<Float>](repeating:.zero,count:vertices.count)
   for i in Swift.stride(from:0,to:indices.count,by:3){let a=Int(indices[i]),b=Int(indices[i+1]),c=Int(indices[i+2]);let v=simd_cross(SIMD3<Float>(Float(vertices[b].x-vertices[a].x),Float(vertices[b].y-vertices[a].y),Float(vertices[b].z-vertices[a].z)),SIMD3<Float>(Float(vertices[c].x-vertices[a].x),Float(vertices[c].y-vertices[a].y),Float(vertices[c].z-vertices[a].z)));normals[a]+=v;normals[b]+=v;normals[c]+=v}
   let smooth=normals.map{n->SCNVector3 in let v=simd_length(n)>0.000001 ? simd_normalize(n):SIMD3<Float>(0,1,0);return SCNVector3(v.x,v.y,v.z)}
   return SCNGeometry(sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:smooth)],elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
  }
  let plastic=SCNMaterial();plastic.lightingModel = .physicallyBased;plastic.diffuse.contents=gbaButtonColor;plastic.roughness.contents=0.38;plastic.specular.contents=CGColor(gray:0.55,alpha:1)
  let key=SCNNode(geometry:paddle(false));key.geometry?.materials=[plastic];key.name="physical-shoulder:"+String(id);key.position=pivot;device.addChildNode(key);physicalShoulders[id]=key
  let resin=SCNMaterial();resin.lightingModel = .physicallyBased;let tint=[0xFFC02C,0x2363AD,0x6026A0,0xEFF2F1][theme];resin.diffuse.contents=CGColor(red:CGFloat((tint>>16)&255)/255,green:CGFloat((tint>>8)&255)/255,blue:CGFloat(tint&255)/255,alpha:1);resin.roughness.contents=0.52
  let seat=SCNNode(geometry:paddle(true));seat.geometry?.materials=[resin];seat.name="gba-shoulder-seat";seat.position=pivot;device.addChildNode(seat)
  // Pivot and actuator are inside the saddle, with no exposed metal bar.
  let axle=SCNCylinder(radius:0.026,height:0.62);axle.radialSegmentCount=16;axle.materials=[resin];let pin=SCNNode(geometry:axle);pin.eulerAngles.z = .pi/2;key.addChildNode(pin)
 }
 private func buildUpperAssembly(_ lid:SCNNode){
  func material(_ value:CGFloat,_ rough:CGFloat,_ metal:CGFloat=0)->SCNMaterial{let m=SCNMaterial();m.diffuse.contents=CGColor(gray:value,alpha:1);m.lightingModel = .physicallyBased;m.roughness.contents=rough;m.metalness.contents=metal;return m}
  let silver=material(0.40,0.46,0.72),graphite=material(0.055,0.86),orange=SCNMaterial();orange.diffuse.contents=CGColor(red:0.47,green:0.25,blue:0.07,alpha:1);orange.roughness.contents=0.70
  func plate(_ name:String,_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat,_ d:CGFloat,_ z:CGFloat,_ m:SCNMaterial){let g=SCNBox(width:w,height:h,length:d,chamferRadius:min(0.025,d/3));g.materials=[m];let n=SCNNode(geometry:g);n.name="internal:lid-"+name;n.position=SCNVector3(x,y,z);lid.addChildNode(n)}
  // The opaque optical carrier prevents the lower deck showing through a closed lid.
  plate("optical-carrier",0,1.65,6.17,3.10,0.018,-0.015,graphite)
  plate("lcd-metal-shield",0,1.65,4.12,2.72,0.032,-0.105,silver)
  for x:CGFloat in [-2.07,2.07]{plate("shield-fold",x,1.65,0.045,2.65,0.045,-0.12,silver)}
  for y:CGFloat in [0.30,3.0]{plate("shield-fold",0,y,4.10,0.045,0.045,-0.12,silver)}
  for x:CGFloat in [-1.46,-0.5,0.48,1.44]{plate("shield-stamping",x,2.82,0.14,0.19,0.008,-0.126,silver);plate("shield-tab",x,0.39,0.13,0.17,0.012,-0.128,silver)}
  for y:CGFloat in [1.46,1.80]{
   #if canImport(UIKit)
   let stamp=UIBezierPath(roundedRect:CGRect(x:-0.21,y:y,width:0.42,height:0.26),cornerRadius:0.045),inside=UIBezierPath(roundedRect:CGRect(x:-0.19,y:y+0.02,width:0.38,height:0.22),cornerRadius:0.03)
   stamp.append(inside.reversing())
   #else
   let stamp=NSBezierPath(roundedRect:CGRect(x:-0.21,y:y,width:0.42,height:0.26),xRadius:0.045,yRadius:0.045),inside=NSBezierPath(roundedRect:CGRect(x:-0.19,y:y+0.02,width:0.38,height:0.22),xRadius:0.03,yRadius:0.03)
   stamp.append(inside.reversed)
   #endif
   stamp.flatness=0.002;let g=SCNShape(path:stamp,extrusionDepth:0.004);g.materials=[silver];let n=SCNNode(geometry:g);n.name="internal:lid-shield-stamp";n.position.z = -0.124;lid.addChildNode(n)
  }
  // Stereo diaphragm, magnet and etched basket; these belong to the lid, never a CPU board.
  for x:CGFloat in [-2.62,2.62]{
   let basket=SCNCylinder(radius:0.43,height:0.045);basket.radialSegmentCount=48;basket.materials=[graphite];let n=SCNNode(geometry:basket);n.name="internal:lid-stereo-speaker";n.eulerAngles.x = .pi/2;n.position=SCNVector3(x,1.75,-0.10);lid.addChildNode(n)
   let magnet=SCNCylinder(radius:0.22,height:0.018);magnet.materials=[silver];let hub=SCNNode(geometry:magnet);hub.position.y = -0.031;n.addChildNode(hub)
   let dot=SCNBox(width:0.11,height:0.008,length:0.11,chamferRadius:0.005);dot.materials=[graphite];let core=SCNNode(geometry:dot);core.position.y = -0.042;n.addChildNode(core)
   for r:CGFloat in [0.30,0.37]{let g=SCNTorus(ringRadius:r,pipeRadius:0.012);g.materials=[silver];let rim=SCNNode(geometry:g);rim.position.y = -0.028;n.addChildNode(rim)}
   for sign:CGFloat in [-1,1]{plate("speaker-lead",x+sign*0.09,2.43,0.012,0.48,0.008,-0.09,sign<0 ? orange:graphite)}
  }
  plate("display-flex",-2.27,0.62,0.29,0.90,0.012,-0.095,orange)
  plate("hinge-flex",-2.25,0.19,0.55,0.13,0.014,-0.095,orange)
  for i in 0..<9{plate("flex-trace",-2.39+CGFloat(i)*0.03,0.62,0.007,0.85,0.003,-0.105,silver)}
  if model=="3ds" {let camera=SCNCylinder(radius:0.075,height:0.025);camera.materials=[graphite];let n=SCNNode(geometry:camera);n.eulerAngles.x = .pi/2;n.position=SCNVector3(0,3.10,-0.10);n.name="internal:lid-camera";lid.addChildNode(n)}
 }

 private func buildRearDetails(){
  let depth:CGFloat=model=="gbc" ? 1.02:model=="gba" ? 0.84:model=="psp" ? 0.58:0.50
  var retired=[SCNNode]();device.enumerateChildNodes{n,_ in if n.name=="battery-door" || n.name=="legacy-rear-fastener"{retired.append(n)}};retired.forEach{$0.removeFromParentNode()}
  let rearInk=SCNMaterial();rearInk.lightingModel = .physicallyBased;rearInk.diffuse.contents=CGColor(gray:0.13,alpha:1);rearInk.roughness.contents=0.67
  let resin=SCNMaterial();resin.lightingModel = .physicallyBased;resin.roughness.contents=(["nds","3ds","psp"].contains(model) && theme != 3) ? 0.20:0.68
  let original=device.childNode(withName:"rear-shell-with-cartridge-pocket",recursively:true) ?? device.childNode(withName:"rear-pocket-cover",recursively:true) ?? device.childNode(withName:"front-shell",recursively:true)
  resin.diffuse.contents=original?.geometry?.firstMaterial?.diffuse.contents ?? CGColor(gray:0.20,alpha:1)
  func p(_ x:CGFloat,_ y:CGFloat,_ z:CGFloat)->SCNVector3{SCNVector3((size.width/2-x)/100,(size.height/2-y)/100,z)}
  func block(_ name:String,_ rect:CGRect,_ thickness:CGFloat,_ material:SCNMaterial,_ z:CGFloat)->SCNNode {
   let g=SCNBox(width:rect.width/100,height:rect.height/100,length:thickness,chamferRadius:min(0.035,thickness/3));g.materials=[material.copy() as! SCNMaterial];let n=SCNNode(geometry:g);n.name=name;n.position=p(rect.midX,rect.midY,z);device.addChildNode(n);return n
  }
  func screw(_ x:CGFloat,_ y:CGFloat){
   let depth:CGFloat=model=="gba" ? 0.64:depth
   let well=SCNCylinder(radius:0.060,height:0.018);well.materials=[rearInk];let n=SCNNode(geometry:well);n.name="rear-screw-well";n.eulerAngles.x = .pi/2;n.position=p(x,y,-depth-0.014);device.addChildNode(n)
   let head=SCNCylinder(radius:0.032,height:0.010),metal=SCNMaterial();metal.diffuse.contents=CGColor(gray:0.45,alpha:1);metal.metalness.contents=0.8;metal.roughness.contents=0.34;head.materials=[metal];let h=SCNNode(geometry:head);h.name="rear-fastener";h.eulerAngles.x = .pi/2;h.position=p(x,y,-depth-0.027);device.addChildNode(h)
   for sign:CGFloat in [-1,1]{let cut=block("rear-screw-cross",CGRect(x:x-1.8,y:y-0.35,width:3.6,height:0.7),0.002,rearInk,-depth-0.034);cut.eulerAngles.z = .init(sign * .pi/4)}
  }
  func legend(_ rect:CGRect,_ brand:String,_ code:String){
   let depth:CGFloat=model=="gba" ? 0.73:depth
   let imageSize=CGSize(width:600,height:600*rect.height/rect.width),typeScale=600*rect.height/rect.width/240
   func paint(){
    #if canImport(UIKit)
    let background=UIColor(white:0.11,alpha:1),ink=UIColor(white:0.80,alpha:1),font=UIFont.systemFont(ofSize:20*typeScale,weight:.medium),bold=UIFont.systemFont(ofSize:34*typeScale,weight:.bold)
    #else
    let background=NSColor(white:0.11,alpha:1),ink=NSColor(white:0.80,alpha:1),font=NSFont.systemFont(ofSize:20*typeScale,weight:.medium),bold=NSFont.systemFont(ofSize:34*typeScale,weight:.bold)
    #endif
    background.setFill()
    #if canImport(UIKit)
    UIBezierPath(roundedRect:CGRect(origin:.zero,size:imageSize),cornerRadius:9).fill()
    #else
    NSBezierPath(roundedRect:CGRect(origin:.zero,size:imageSize),xRadius:9,yRadius:9).fill()
    #endif
    if model=="gba"{
     #if canImport(UIKit)
     let heading=UIFont.systemFont(ofSize:15,weight:.bold),small=UIFont.systemFont(ofSize:9,weight:.medium)
     #else
     let heading=NSFont.systemFont(ofSize:15,weight:.bold),small=NSFont.systemFont(ofSize:9,weight:.medium)
     #endif
     ("GAME BOY ADVANCE" as NSString).draw(at:CGPoint(x:14,y:5),withAttributes:[.font:heading,.foregroundColor:ink])
     ("MODEL NO. AGB-001" as NSString).draw(at:CGPoint(x:410,y:7),withAttributes:[.font:small,.foregroundColor:ink])
     ("RATING: 3V — 0.6W   BATTERY: LR6 (AA) ×2   © Nintendo" as NSString).draw(at:CGPoint(x:14,y:26),withAttributes:[.font:small,.foregroundColor:ink])
     ("PLEASE REFER TO THE INSTRUCTION BOOKLET.   MADE IN JAPAN" as NSString).draw(at:CGPoint(x:14,y:40),withAttributes:[.font:small,.foregroundColor:ink]);return
    }
    let dual=model=="nds" || model=="3ds"
    if dual {
     #if canImport(UIKit)
     UIGraphicsGetCurrentContext()?.clear(CGRect(origin:.zero,size:imageSize))
     #else
     NSGraphicsContext.current?.cgContext.clear(CGRect(origin:.zero,size:imageSize))
     #endif
    }
    let logoURL=Self.directory.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Logos/"+model+"-home.png")
    let logo=SpatialImage(contentsOfFile:logoURL.path),logoArea=CGRect(x:dual ? 155:30,y:15*typeScale,width:dual ? 290:420,height:50*typeScale)
    if let logo {let q=min(logoArea.width/logo.size.width,logoArea.height/logo.size.height);logo.draw(in:CGRect(x:logoArea.midX-logo.size.width*q/2,y:logoArea.midY-logo.size.height*q/2,width:logo.size.width*q,height:logo.size.height*q))}
    else {(brand as NSString).draw(at:CGPoint(x:24,y:20*typeScale),withAttributes:[.font:bold,.foregroundColor:ink])}
    let words=["MODEL "+code+" · Nintendo",model=="gbc" || model=="gba" ? "RATING: DC 3V · BATTERY: LR6 (AA) × 2":"RECHARGEABLE PORTABLE VIDEO GAME SYSTEM","PLEASE REFER TO THE INSTRUCTION BOOKLET","Nintendo · GAME CARD SYSTEM"]
    for (i,word) in words.enumerated(){(word as NSString).draw(at:CGPoint(x:dual ? 85:25,y:(83+CGFloat(i)*22)*typeScale),withAttributes:[.font:font,.foregroundColor:ink])}
    let bar=CGRect(x:175,y:184*typeScale,width:250,height:33*typeScale)
    #if canImport(UIKit)
    UIColor(white:0.90,alpha:1).setFill();UIRectFill(bar);UIColor(white:0.09,alpha:1).setFill()
    #else
    NSColor(white:0.90,alpha:1).setFill();bar.fill();NSColor(white:0.09,alpha:1).setFill()
    #endif
    for i in 0..<78 where (i*17+11)%7<4 {let stripe=CGRect(x:bar.minX+10+CGFloat(i)*2.9,y:bar.minY+3*typeScale,width:(i%3==0 ? 2:1),height:25*typeScale)
     #if canImport(UIKit)
     UIRectFill(stripe)
     #else
     stripe.fill()
     #endif
    }

   }
   #if canImport(UIKit)
   let image=UIGraphicsImageRenderer(size:imageSize).image{_ in paint()}
   #else
   let image=NSImage(size:imageSize);image.lockFocusFlipped(true);paint();image.unlockFocus()
   #endif
   let g=SCNPlane(width:rect.width/100,height:rect.height/100),m=SCNMaterial();m.diffuse.contents=image;m.lightingModel = .physicallyBased;m.roughness.contents=0.80;g.materials=[m];let n=SCNNode(geometry:g);n.name="rear-system-label";n.eulerAngles.y = .pi;n.position=p(rect.midX,rect.midY,-depth-0.035);device.addChildNode(n)
  }
  switch model {
  case "gbc":
   _=block("rear-pocket-inner-wall",CGRect(x:62,y:27,width:256,height:250),0.025,resin,-0.59)
   _=block("rear-pocket-lower-shield",CGRect(x:61,y:175,width:258,height:106),0.025,resin,-depth-0.002)
   _=block("battery-door",CGRect(x:57,y:410,width:266,height:164),0.025,resin,-depth-0.018)
   _=block("battery-latch-recess",CGRect(x:171,y:553,width:38,height:17),0.012,rearInk,-depth-0.034)
   _=block("battery-latch",CGRect(x:181,y:553,width:18,height:7),0.021,resin,-depth-0.044)
   legend(CGRect(x:58,y:303,width:264,height:88),"GAME BOY COLOR","CGB-001")
   for (x,y) in [(45.0,67.0),(335,67),(42,318),(338,318),(42,577),(338,577)]{screw(x,y)}
  case "gba":
   _=block("battery-door",CGRect(x:225,y:225,width:270,height:111),0.030,resin,-depth-0.020)
   _=block("battery-latch-recess",CGRect(x:341,y:217,width:38,height:24),0.014,rearInk,-depth-0.037)
   _=block("battery-latch",CGRect(x:348,y:218,width:24,height:15),0.024,resin,-depth-0.049)
   _=block("rear-cartridge-molding",CGRect(x:226,y:53,width:268,height:125),0.025,resin,-0.75)
   legend(CGRect(x:200,y:180,width:320,height:34),"GAME BOY ADVANCE","AGB-001")
   for (x,y) in [(110.0,62.0),(610,62),(80,145),(620,145),(77,307),(620,307)]{screw(x,y)}
  case "nds":
   _=block("battery-door",CGRect(x:503,y:396,width:144,height:251),0.023,resin,-depth-0.019)
   _=block("rear-slot2-throat",CGRect(x:210,y:680,width:248,height:6),0.032,rearInk,-depth-0.021)
   legend(CGRect(x:169,y:447,width:302,height:140),"Nintendo DS Lite","USG-001")
   for (x,y) in [(168.0,377.0),(360,370),(552,377),(75,411),(632,420),(72,663),(648,663)]{screw(x,y)}
  case "3ds":
   _=block("battery-door",CGRect(x:57,y:380,width:606,height:290),0.024,resin,-depth-0.019)
   if theme != 1{legend(CGRect(x:196,y:464,width:328,height:130),"Nintendo 3DS","CTR-001")}
   for (x,y) in [(80.0,389.0),(194,387),(526,387),(640,389),(74,665),(646,665)]{screw(x,y)}
  case "psp":
   for (x,y) in [(645.0,80.0),(645,268)]{screw(x,y)}
  default:break
  }
 }
 /// Small edge fittings use their own outward-facing local plane, never front-panel decals.
 private func buildEdgeDetails(){
  let dark=SCNMaterial();dark.lightingModel = .physicallyBased;dark.diffuse.contents=CGColor(gray:0.025,alpha:1);dark.roughness.contents=0.78
  let alloy=SCNMaterial();alloy.lightingModel = .physicallyBased;alloy.diffuse.contents=CGColor(gray:0.46,alpha:1);alloy.metalness.contents=0.86;alloy.roughness.contents=0.32
  func fitting(_ name:String,_ x:CGFloat,_ y:CGFloat,_ z:CGFloat,_ width:CGFloat,_ height:CGFloat,_ edge:Int,_ metal:Bool=true)->SCNNode{
   let root=SCNNode();root.name="edge:"+name;root.position=SCNVector3((x-size.width/2)/100,(size.height/2-y)/100,z)
   // The local Z axis points out of the actual edge (top, bottom, left, right).
   root.eulerAngles=SCNVector3(edge==0 ? -Float.pi/2:edge==1 ? Float.pi/2:0,edge==2 ? -Float.pi/2:edge==3 ? Float.pi/2:0,0)
   let surround=SCNBox(width:width,height:height,length:0.014,chamferRadius:min(0.025,height/4));surround.materials=[metal ? alloy:dark];root.addChildNode(SCNNode(geometry:surround))
   let hole=SCNBox(width:width-0.035,height:height-0.025,length:0.009,chamferRadius:min(0.018,height/5));hole.materials=[dark];let throat=SCNNode(geometry:hole);throat.position.z=0.009;root.addChildNode(throat);device.addChildNode(root);return root
  }
  func jack(_ name:String,_ x:CGFloat,_ y:CGFloat,_ z:CGFloat,_ edge:Int){let n=fitting(name,x,y,z,0.20,0.20,edge);let socket=SCNTube(innerRadius:0.052,outerRadius:0.075,height:0.025);socket.radialSegmentCount=32;socket.materials=[alloy];let ring=SCNNode(geometry:socket);ring.eulerAngles.x = .pi/2;ring.position.z=0.018;n.addChildNode(ring)}
  switch model {
  case "gba":
   let link=fitting("ext-link",360,27,-0.29,0.34,0.16,0)
   for i in 0..<6{let g=SCNBox(width:0.016,height:0.035,length:0.012,chamferRadius:0.002);g.materials=[alloy];let n=SCNNode(geometry:g);n.position=SCNVector3(-0.10+CGFloat(i)*0.04,0,0.018);link.addChildNode(n)}
   jack("headphone",360,350,-0.28,1)
   _=fitting("power-slide",244,346,-0.28,0.30,0.13,1,false)
   // Stock AGB-001 uses AA batteries. It has no USB charging connector.
  case "gbc":
   _=fitting("ext-link",18,205,-0.66,0.34,0.18,2)
   _=fitting("volume-wheel",18,284,-0.66,0.27,0.15,2,false)
   _=fitting("power-slide",362,154,-0.66,0.30,0.15,3,false)
   jack("headphone",137,590,-0.68,1);jack("dc-3v",240,590,-0.68,1)
   let ir=fitting("infrared",275,25,-0.62,0.40,0.15,0,false);ir.geometry?.firstMaterial?.diffuse.contents=CGColor(red:0.16,green:0.025,blue:0.03,alpha:1)
  case "nds":
   _=fitting("dc-5v2",554,363,-0.28,0.25,0.14,0)
   jack("headphone",518,686,-0.25,1)
   _=fitting("power-slide",678,500,-0.25,0.30,0.12,3,false)
   _=fitting("volume-slide",148,686,-0.25,0.35,0.12,1,false)
  case "3ds":
   jack("headphone",360,686,-0.25,1)
   _=fitting("volume-slide",43,466,-0.25,0.35,0.12,2,false)
   _=fitting("charge-port",551,363,-0.27,0.27,0.14,0)
  case "psp":
   _=fitting("usb-mini-b",360,34,-0.24,0.34,0.13,0)
   jack("dc-5v",601,314,-0.27,1);jack("headphone",179,314,-0.27,1)
  default:break
  }
 }
 private func buildPSPPhysicalDetails(){
  // PBR specular must not light the transparent paper surrounding etched ink.
  device.enumerateChildNodes{n,_ in guard let g=n.geometry as? SCNPlane,g.width>2.5,g.height>2.5,n.name?.hasPrefix("screen:") != true else{return}
   for m in g.materials{m.shaderModifiers=[.fragment:"""
   #pragma body
   if (_surface.diffuse.a < 0.04) discard_fragment();
   _output.color.a = _surface.diffuse.a;
   """]}
  }

  func p(_ x:CGFloat,_ y:CGFloat,_ z:CGFloat)->SCNVector3{SCNVector3((x-size.width/2)/100,(size.height/2-y)/100,z)}
  func ink(_ gray:CGFloat)->SCNMaterial{let m=SCNMaterial();m.lightingModel = .physicallyBased;m.diffuse.contents=CGColor(gray:gray,alpha:1);m.roughness.contents=0.45;return m}
  let black=ink(0.035),plastic=ink(theme==0 ? 0.72:0.18)
  #if canImport(UIKit)
  let loop=UIBezierPath(roundedRect:CGRect(x:-0.28,y:-0.11,width:0.56,height:0.22),cornerRadius:0.10)
  loop.append(UIBezierPath(roundedRect:CGRect(x:-0.20,y:-0.055,width:0.40,height:0.11),cornerRadius:0.045).reversing())
  #else
  let loop=NSBezierPath(roundedRect:CGRect(x:-0.28,y:-0.11,width:0.56,height:0.22),xRadius:0.10,yRadius:0.10)
  loop.append(NSBezierPath(roundedRect:CGRect(x:-0.20,y:-0.055,width:0.40,height:0.11),xRadius:0.045,yRadius:0.045).reversed)
  #endif
  loop.flatness=0.002;let eye=SCNShape(path:loop,extrusionDepth:0.13);eye.chamferRadius=0.022;let chrome=ink(0.72);chrome.metalness.contents=0.96;chrome.roughness.contents=0.20;eye.materials=[chrome];let eyelet=SCNNode(geometry:eye);eyelet.name="single-metal-strap-eyelet";eyelet.position=p(94,309,-0.42);eyelet.eulerAngles.z = -0.16;device.addChildNode(eyelet)
  // Physical reader hardware sits behind the seated disc, with actual clearance.
  let driveMetal=ink(0.34);driveMetal.metalness.contents=0.70;driveMetal.roughness.contents=0.40
  for (radius,height,z) in [(0.24,0.025,-0.310),(0.115,0.028,-0.340)] {
   let g=SCNCylinder(radius:radius,height:height);g.radialSegmentCount=48;g.materials=[driveMetal];let n=SCNNode(geometry:g);n.name="optical-drive-spindle";n.eulerAngles.x = .pi/2;n.position=SCNVector3(0,0.16,z);device.addChildNode(n)
  }
  for y:CGFloat in [0.03,0.29]{let g=SCNBox(width:0.78,height:0.018,length:0.018,chamferRadius:0.006);g.materials=[driveMetal];let n=SCNNode(geometry:g);n.name="optical-drive-rail";n.position=SCNVector3(0.66,y,-0.325);device.addChildNode(n)}
  let sled=SCNBox(width:0.25,height:0.22,length:0.028,chamferRadius:0.025);sled.materials=[black];let pickup=SCNNode(geometry:sled);pickup.name="optical-drive-pickup";pickup.position=SCNVector3(0.63,0.16,-0.335);device.addChildNode(pickup)
  let lens=SCNSphere(radius:0.040),glass=SCNMaterial();glass.diffuse.contents=CGColor(red:0.09,green:0.25,blue:0.34,alpha:1);glass.roughness.contents=0.10;glass.metalness.contents=0.20;lens.materials=[glass];let optic=SCNNode(geometry:lens);optic.scale=SCNVector3(1,1,0.25);optic.position.z = -0.022;pickup.addChildNode(optic)

  for x:CGFloat in [160,549]{for y:CGFloat in [84,95,106]{let g=SCNBox(width:0.08,height:0.02,length:0.012,chamferRadius:0.009);g.materials=[black];let n=SCNNode(geometry:g);n.name="psp-speaker-aperture";n.position=p(x+4,y+1,0.015);device.addChildNode(n)}}
  let symbols=["⌂","−","+","♫","☀"]
  for (i,x) in [CGFloat(192),228,264,460,424].enumerated(){
   let g=SCNBox(width:0.25,height:0.15,length:0.065,chamferRadius:0.030);g.materials=[plastic];let n=SCNNode(geometry:g);n.name="utility:"+String(i);n.position=p(x+12.5,295,0.042);device.addChildNode(n)
   let size=CGSize(width:100,height:60)
   func paint(){
    #if canImport(UIKit)
    let font=UIFont.systemFont(ofSize:36,weight:.medium),color=UIColor(white:self.theme==0 ? 0.20:0.86,alpha:1)
    #else
    let font=NSFont.systemFont(ofSize:36,weight:.medium),color=NSColor(white:self.theme==0 ? 0.20:0.86,alpha:1)
    #endif
    let text=symbols[i] as NSString,attrs:[NSAttributedString.Key:Any]=[.font:font,.foregroundColor:color],extent=text.size(withAttributes:attrs);text.draw(at:CGPoint(x:(100-extent.width)/2,y:(60-extent.height)/2),withAttributes:attrs)
   }
   #if canImport(UIKit)
   let image=UIGraphicsImageRenderer(size:size).image{_ in paint()}
   #else
   let image=NSImage(size:size);image.lockFocusFlipped(true);paint();image.unlockFocus()
   #endif
   let plane=SCNPlane(width:0.23,height:0.13),m=SCNMaterial();m.diffuse.contents=image;m.lightingModel = .constant;plane.materials=[m];let label=SCNNode(geometry:plane);label.position.z=0.0345;n.addChildNode(label)
  }
  let slot=SCNBox(width:0.10,height:0.43,length:0.025,chamferRadius:0.01);slot.materials=[black];let rail=SCNNode(geometry:slot);rail.name="psp-power-rail";rail.position=p(674,220,0.018);device.addChildNode(rail)
  let grip=SCNBox(width:0.075,height:0.17,length:0.04,chamferRadius:0.015);grip.materials=[plastic];let slider=SCNNode(geometry:grip);slider.name="psp-power-switch";slider.position=p(674,220,0.039);device.addChildNode(slider)
 }
 private func buildPSPStick(){
  guard let stick else{return}
  for child in stick.childNodes{child.removeFromParentNode()}
  let plastic=SCNMaterial();plastic.lightingModel = .physicallyBased;plastic.diffuse.contents=CGColor(gray:theme==0 ? 0.60:0.13,alpha:1);plastic.roughness.contents=0.78;plastic.specular.contents=CGColor(gray:0.12,alpha:1);plastic.metalness.contents=0;plastic.fresnelExponent=1.4
  let rim=SCNMaterial();rim.lightingModel = .physicallyBased;rim.diffuse.contents=CGColor(gray:0.055,alpha:1);rim.roughness.contents=0.38
  if let cylinder=stick.geometry as? SCNCylinder{cylinder.height=0.095;cylinder.materials=[rim]}
  let stem=SCNCylinder(radius:0.095,height:0.11);stem.materials=[rim];let shaft=SCNNode(geometry:stem);shaft.position.y=0.055;shaft.name="stick-shaft";stick.addChildNode(shaft)
  let cap=SCNCylinder(radius:0.245,height:0.055);cap.radialSegmentCount=64;cap.materials=[plastic];let crown=SCNNode(geometry:cap);crown.position.y=0.12;crown.name="stick-textured-cap";stick.addChildNode(crown)
  let edge=SCNTorus(ringRadius:0.235,pipeRadius:0.015);edge.materials=[plastic];let lip=SCNNode(geometry:edge);lip.position.y=0.148;stick.addChildNode(lip)
  for row in -7...7{for column in -7...7{let x=CGFloat(column)*0.027,z=CGFloat(row)*0.027;guard x*x+z*z<0.215*0.215 else{continue};let bump=SCNSphere(radius:0.009);bump.segmentCount=6;bump.materials=[plastic];let n=SCNNode(geometry:bump);n.scale=SCNVector3(1,0.6,1);n.position=SCNVector3(x,0.031,z);crown.addChildNode(n)}}
  let merged=crown.flattenedClone();merged.geometry?.materials=Array(repeating:plastic,count:max(1,merged.geometry?.materials.count ?? 1));merged.enumerateChildNodes{n,_ in n.geometry?.materials=Array(repeating:plastic,count:max(1,n.geometry?.materials.count ?? 1))};crown.removeFromParentNode();stick.addChildNode(merged)
 }
 private var gbaButtonColor:CGColor {theme==2 ? CGColor(red:0.49,green:0.89,blue:0.04,alpha:1):CGColor(red:0.88,green:0.91,blue:0.90,alpha:1)}
 private func configureGBAFinish(){
  // Retire the old wide front-facing seam: it belonged to the uniform extrusion,
  // and projects as a black border outside the new rolled shell.
  for node in device.childNodes{if let shape=node.geometry as? SCNShape,shape.extrusionDepth<0.03{let box=shape.boundingBox;if box.max.x-box.min.x>6 && box.max.y-box.min.y>3{node.removeFromParentNode()}}}
  let translucent=theme==1 || theme==3
  device.enumerateChildNodes{n,_ in
   guard let g=n.geometry else{return}
   if n.name=="front-shell" || n.name=="gba-rolled-sidewall" || n.name=="gba-shoulder-seat" || n.name=="gba-battery-cradle" || n.name=="gba-cartridge-pocket-wall" || n.name=="rear-shell-with-cartridge-pocket" || n.name=="battery-door" || n.name=="rear-cartridge-molding" || n.name=="battery-latch" {
    let rear = n.name != "front-shell"
    n.opacity=translucent ? (rear ? 0.96:(self.theme==3 ? 0.78:0.80)):1;n.renderingOrder=translucent ? 10:0
    for m in g.materials{if self.theme==3{m.diffuse.contents=CGColor(red:0.60,green:0.64,blue:0.66,alpha:1)};m.transparency=1;m.lightingModel = .physicallyBased;m.roughness.contents=translucent ? 0.60:0.36;m.writesToDepthBuffer = rear || !translucent;m.isDoubleSided=true;m.transparencyMode = .aOne}
   }
   if n.name=="dpad" || n.name?.hasPrefix("key:")==true || n.name?.hasPrefix("physical-shoulder:")==true {
    for m in g.materials{m.diffuse.contents=self.gbaButtonColor;m.roughness.contents=0.35}
   }
  }
 }
 private func buildGBAFrontDetails(){
  func p(_ x:CGFloat,_ y:CGFloat,_ z:CGFloat)->SCNVector3{SCNVector3((x-size.width/2)/100,(size.height/2-y)/100,z)}
  // A real, opaque LCD surround shields the display from transmitted electronics.
  #if canImport(UIKit)
  let glass=UIBezierPath()
  #else
  let glass=NSBezierPath()
  #endif
  glass.move(to:CGPoint(x:-1.62,y:1.34))
  #if canImport(UIKit)
  glass.addCurve(to:CGPoint(x:1.62,y:1.34),controlPoint1:CGPoint(x:-0.65,y:1.42),controlPoint2:CGPoint(x:0.65,y:1.42));glass.addCurve(to:CGPoint(x:1.79,y:-1.19),controlPoint1:CGPoint(x:1.86,y:1.32),controlPoint2:CGPoint(x:1.86,y:-0.85));glass.addCurve(to:CGPoint(x:-1.79,y:-1.19),controlPoint1:CGPoint(x:0.90,y:-1.39),controlPoint2:CGPoint(x:-0.90,y:-1.39));glass.addCurve(to:CGPoint(x:-1.62,y:1.34),controlPoint1:CGPoint(x:-1.86,y:-0.85),controlPoint2:CGPoint(x:-1.86,y:1.32))
  #else
  glass.curve(to:CGPoint(x:1.62,y:1.34),controlPoint1:CGPoint(x:-0.65,y:1.42),controlPoint2:CGPoint(x:0.65,y:1.42));glass.curve(to:CGPoint(x:1.79,y:-1.19),controlPoint1:CGPoint(x:1.86,y:1.32),controlPoint2:CGPoint(x:1.86,y:-0.85));glass.curve(to:CGPoint(x:-1.79,y:-1.19),controlPoint1:CGPoint(x:0.90,y:-1.39),controlPoint2:CGPoint(x:-0.90,y:-1.39));glass.curve(to:CGPoint(x:-1.62,y:1.34),controlPoint1:CGPoint(x:-1.86,y:-0.85),controlPoint2:CGPoint(x:-1.86,y:1.32))
  #endif
  glass.close();glass.flatness=0.002
  let bezel=SCNShape(path:glass,extrusionDepth:0.028),black=SCNMaterial();black.diffuse.contents=CGColor(gray:0.035,alpha:1);black.lightingModel = .physicallyBased;black.roughness.contents=0.38;bezel.materials=[black];let n=SCNNode(geometry:bezel);n.name="gba-lcd-surround";n.position=p(360,184,0.023);device.addChildNode(n)
  let inkSize=CGSize(width:720,height:380)
  func paint(){
   #if canImport(UIKit)
   let ink=UIColor(white:0.78,alpha:1),font=UIFont.systemFont(ofSize:8,weight:.semibold)
   #else
   let ink=NSColor(white:0.78,alpha:1),font=NSFont.systemFont(ofSize:8,weight:.semibold)
   #endif
   if let url=Bundle.main.url(forResource:"gba-home",withExtension:"png",subdirectory:"Assets/Logos"),let image=SpatialImage(contentsOfFile:url.path){let q=min(2.46/image.size.width,0.24/image.size.height)*100;image.draw(in:CGRect(x:360-image.size.width*q/2,y:296+(24-image.size.height*q)/2,width:image.size.width*q,height:image.size.height*q))}
   ("Nintendo" as NSString).draw(at:CGPoint(x:340,y:40),withAttributes:[.font:font,.foregroundColor:ink])
   ("POWER" as NSString).draw(at:CGPoint(x:587,y:90),withAttributes:[.font:font,.foregroundColor:ink])
   if theme==1 {
    #if canImport(UIKit)
    let mark=UIFont.italicSystemFont(ofSize:14)
    #else
    let mark=NSFontManager.shared.convert(NSFont.boldSystemFont(ofSize:14),toHaveTrait:.italicFontMask)
    #endif
    ("SONIC" as NSString).draw(at:CGPoint(x:92,y:68),withAttributes:[.font:mark,.foregroundColor:ink]);("TEAM" as NSString).draw(at:CGPoint(x:96,y:82),withAttributes:[.font:font,.foregroundColor:ink])
   }
   if theme==2 {("EVA-01" as NSString).draw(at:CGPoint(x:84,y:80),withAttributes:[.font:font,.foregroundColor:ink])}
  }
  #if canImport(UIKit)
  let image=UIGraphicsImageRenderer(size:inkSize).image{_ in paint()}
  #else
  let image=NSImage(size:inkSize);image.lockFocusFlipped(true);paint();image.unlockFocus()
  #endif
  let g=SCNPlane(width:7.2,height:3.8),m=SCNMaterial();m.diffuse.contents=image;m.lightingModel = .constant;m.writesToDepthBuffer=false;g.materials=[m];let print=SCNNode(geometry:g);print.name="gba-permanent-print";print.position.z=0.045;device.addChildNode(print)
  for i in 0..<6{let slit=SCNBox(width:0.48,height:0.025,length:0.014,chamferRadius:0.012);slit.materials=[black];let n=SCNNode(geometry:slit);n.name="speaker-aperture";n.eulerAngles.z=0.12;n.position=p(600,268+CGFloat(i)*8,0.016);device.addChildNode(n)}
 }
 private func softenTransmittedDetail(){
  device.enumerateChildNodes{node,_ in
   guard let name=node.name,name.hasPrefix("internal:") || name=="pcb-form" else{return}
   if name.contains("passive") || name.contains("trace") || name.contains("connector-pin"){node.opacity=0.32}
   if name.contains("contact"){node.opacity=0.38}
   for material in node.geometry?.materials ?? []{material.roughness.contents=0.90}
  }
 }
 private func buildPassiveComponents(){
  let clusters:[(CGFloat,CGFloat,Int)]
  switch model{case "gba":clusters=[(95,105,18),(171,266,16),(553,242,14),(590,89,12)];case "gbc":clusters=[(67,478,12),(279,457,10)];case "psp":clusters=[(563,77,14),(622,201,12),(81,202,10)];default:clusters=[(92,605,18),(579,598,14),(168,640,12)]}
  let solder=SCNMaterial();solder.diffuse.contents=CGColor(gray:0.60,alpha:1);solder.lightingModel = .physicallyBased;solder.metalness.contents=0.75;solder.roughness.contents=0.36
  let ceramic=SCNMaterial();ceramic.diffuse.contents=CGColor(red:0.48,green:0.38,blue:0.24,alpha:1);ceramic.lightingModel = .physicallyBased;ceramic.roughness.contents=0.68
  let ink=SCNMaterial();ink.diffuse.contents=CGColor(gray:0.12,alpha:1);ink.lightingModel = .physicallyBased;ink.roughness.contents=0.60
  let z:CGFloat=model=="gbc" ? -0.29:-0.11
  for (cx,cy,count) in clusters{for i in 0..<count{let x=cx+CGFloat((i*17)%47),y=cy+CGFloat((i*11)%39),w:CGFloat=i%4==0 ? 5:2.8,h:CGFloat=i%4==0 ? 3:1.8
   let package=SCNNode(geometry:SCNBox(width:w/100,height:h/100,length:0.018,chamferRadius:0.002));package.geometry?.materials=[i%3==0 ? ceramic:ink];package.name="internal:passive-package";package.position=SCNVector3((x-size.width/2)/100,(size.height/2-y)/100,z);device.addChildNode(package)
   for dx in [-w/2,w/2]{let end=SCNNode(geometry:SCNBox(width:0.008,height:h/100,length:0.019,chamferRadius:0.001));end.geometry?.materials=[solder];end.position=SCNVector3(dx/100,0,0);package.addChildNode(end)}
  }}
 }
 func update(openness:CGFloat,loading:CGFloat,held:Set<Int>,frame:CGImage?,axis:CGPoint = .zero,operating:Bool=false){
  for id in [10,11]{keys[id]?.isHidden = !operating || model=="psp" || model=="gba"}
  if let slider=powerSlider{slider.position=SCNVector3(powerRest.x,powerRest.y+(frame == nil ? 0:0.08),powerRest.z)}
  lid?.eulerAngles=SCNVector3(Float((1-openness)*CGFloat.pi+openness*0.10),0,0)
  if model=="psp"{device.eulerAngles=SCNVector3(0,Float((1-openness)*CGFloat.pi+openness*0.10),0);if let hatch{hatch.eulerAngles=SCNVector3(Float(MediaLoadingMotion.doorAngle(Double(loading))),Float.pi,0)}}
  if previous != held {
   SCNTransaction.begin();SCNTransaction.disableActions=false;SCNTransaction.animationDuration=0.075;SCNTransaction.animationTimingFunction=CAMediaTimingFunction(name:.easeOut)
   for (id,node) in physicalShoulders{node.eulerAngles.x=held.contains(id) ? (model=="gba" ? 0.16:-0.18):0}
   for (id,node) in keys {node.geometry?.materials.forEach{$0.multiply.contents=CGColor(gray:held.contains(id) ? 0.82:1,alpha:1)};if let r=rest[id]{node.position=SCNVector3(Float(r.x),Float(r.y),Float(r.z)-(held.contains(id) ? (model=="gbc" ? 0.060:4.2):0));if id==10 || id==11{node.eulerAngles=SCNVector3(held.contains(id) ? -0.08:0,0,0)}}}
   let x=Float((held.contains(5) ? 1:0)-(held.contains(4) ? 1:0)),y=Float((held.contains(7) ? 1:0)-(held.contains(6) ? 1:0)),length=max(1,sqrt(x*x+y*y))
   cross?.eulerAngles=SCNVector3(x/length*0.23,y/length*0.23,0);SCNTransaction.commit();previous=held
  }
  if let stick,let r=stickRest{stick.position=SCNVector3(Float(r.x)+Float(axis.x)*0.18,Float(r.y)-Float(axis.y)*0.18,Float(r.z));stick.eulerAngles=SCNVector3(Float.pi/2+Float(axis.y)*0.16,Float(axis.x)*0.16,0)}
  guard frame !== lastFrame else{return};lastFrame=frame
  for (i,m) in screenMaterials.enumerated(){
   guard let frame else{
    #if canImport(UIKit)
    m.diffuse.contents=UIColor(red:0.08,green:0.12,blue:0.1,alpha:1)
    #else
    m.diffuse.contents=NSColor(calibratedRed:0.08,green:0.12,blue:0.1,alpha:1)
    #endif
    continue
   }
   if screenMaterials.count==1{m.diffuse.contents=frame}else{let h=frame.height/2,w=model=="3ds" && i==1 ? frame.width*4/5:frame.width;m.diffuse.contents=frame.cropping(to:CGRect(x:(frame.width-w)/2,y:i*h,width:w,height:h))}
   m.diffuse.magnificationFilter = .nearest;m.diffuse.minificationFilter = .nearest
  }
 }
 var internalParts:[String]{var names=[String]();device.enumerateChildNodes{n,_ in if let name=n.name,name.hasPrefix("internal:") || name=="pcb-form"{names.append(name)}};return names.sorted()}
 var mechanicalState:[String:Any]{["liveScreenBindings":screenMaterials.allSatisfy{m in var found=false;device.enumerateChildNodes{n,_ in if n.name?.hasPrefix("screen:")==true,n.geometry?.firstMaterial === m{found=true}};return found},"model":model,"rigidCross":cross != nil,"cross":cross.map{[Double($0.eulerAngles.x),Double($0.eulerAngles.y)]} ?? [],"held":previous.sorted(),"depth":Dictionary(uniqueKeysWithValues:keys.map{(String($0.key),Double($0.value.position.z))}),"stickPose":stick.map{[Double($0.position.x),Double($0.position.y),Double($0.eulerAngles.x),Double($0.eulerAngles.y)]} ?? [],"physicalShoulders":physicalShoulders.count,"mesh":true]}
 func controls(at hit:SCNHitTestResult)->Set<Int>{var node:SCNNode?=hit.node;while let n=node{if let name=n.name,name.hasPrefix("physical-shoulder:"),let id=Int(name.dropFirst(18)),model=="psp" || model=="gba"{return [id]};if let name=n.name,name.hasPrefix("key:"),let id=Int(name.dropFirst(4)){return [id]};if n.name=="dpad"{let p=n.convertPosition(hit.worldCoordinates,from:nil),threshold:CGFloat=model=="gbc" ? 0.12:12;var ids=Set<Int>();if CGFloat(p.x) < -threshold{ids.insert(6)};if CGFloat(p.x)>threshold{ids.insert(7)};if CGFloat(p.y)>threshold{ids.insert(4)};if CGFloat(p.y) < -threshold{ids.insert(5)};return ids};node=n.parent};return []}
 func controlNode(_ id:Int)->SCNNode?{if (id==10 || id==11) && (model=="psp" || model=="gba"){return physicalShoulders[id]};return (4...7).contains(id) && model != "psp" ? cross:keys[id]}
 private static var mediaPlaceholders:[String:SpatialImage]=[:]
 private static func mediaPlaceholder(_ model:String)->SpatialImage{
  if let cached=mediaPlaceholders[model]{return cached}
  let size=CGSize(width:512,height:512)
  func paint(_ c:CGContext){
   let colors=[CGColor(red:0.20,green:0.27,blue:0.24,alpha:1),CGColor(red:0.09,green:0.14,blue:0.13,alpha:1)]
   let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors as CFArray,locations:[0,1])!;c.drawLinearGradient(gradient,start:.zero,end:CGPoint(x:512,y:512),options:[])
   c.setStrokeColor(CGColor(gray:0.85,alpha:0.14));c.setLineWidth(2);c.stroke(CGRect(x:35,y:35,width:442,height:442));for x in stride(from:CGFloat(70),through:440,by:16){c.move(to:CGPoint(x:x,y:366));c.addLine(to:CGPoint(x:x,y:414))};c.strokePath()
   #if canImport(UIKit)
   let font=UIFont.monospacedSystemFont(ofSize:35,weight:.medium),ink=UIColor(red:0.80,green:0.84,blue:0.77,alpha:1)
   #else
   let font=NSFont.monospacedSystemFont(ofSize:35,weight:.medium),ink=NSColor(calibratedRed:0.80,green:0.84,blue:0.77,alpha:1)
   #endif
   let paragraph=NSMutableParagraphStyle();paragraph.alignment = .center
   ("GAME" as NSString).draw(in:CGRect(x:35,y:216,width:442,height:65),withAttributes:[.font:font,.foregroundColor:ink,.paragraphStyle:paragraph])
  }
  #if canImport(UIKit)
  let image=UIGraphicsImageRenderer(size:size).image{paint($0.cgContext)}
  #else
  let image=NSImage(size:size);image.lockFocusFlipped(true);paint(NSGraphicsContext.current!.cgContext);image.unlockFocus()
  #endif
  mediaPlaceholders[model]=image;return image
 }
 /// Pick only physical geometry. Decorative alpha planes must never consume a
 /// preview press or make a transparent canvas behave like the model's body.
 static func previewTarget(_ node:SCNNode)->SCNNode? {
  guard node.categoryBitMask & 1 != 0 else{return nil}
  var ancestor:SCNNode?=node
  while let n=ancestor {if let name=n.name,name.hasPrefix("card:"){return n};if let name=n.name,["model:","theme:"].contains(where:{name.hasPrefix($0)}),!(node.geometry is SCNPlane){return n};ancestor=n.parent}
  return nil
 }
 static func mediaIsTranslucent(model:String,title:String?)->Bool {
  guard let name=title?.lowercased() else{return false}
  return model=="gba" ? ["emerald","ruby","sapphire","firered","fire red","leafgreen","leaf green"].contains(where:name.contains):model=="gbc" && name.contains("crystal")
 }
 static func media(model:String,cover:SpatialImage?,tint:Int,title:String?=nil)->SCNNode? {
  guard let scene=try? SCNScene(url:directory.appendingPathComponent("media-"+model+".scn"),options:nil),let root=scene.rootNode.childNode(withName:"media",recursively:false) else{return nil}
  root.enumerateChildNodes{node,_ in for m in node.geometry?.materials ?? [] {
   if m.name=="cover" || m.name=="media-shell" || node.name=="umd-protective-shell" {
    // Material-level highlight knee, independent of the cached cover colour.
    // Prevent mobile LDR clipping from turning dyed plastic/paper into white patches.
    m.shaderModifiers=[.fragment:"""
    #pragma body
    float peak=max(max(_output.color.r,_output.color.g),_output.color.b);
    float mapped=peak<=0.65 ? peak : 0.65+0.20*(1.0-exp(-(peak-0.65)/0.20));
    _output.color.rgb *= mapped/max(peak,0.0001);
    """]
   }

   if m.name=="cover"{
    m.roughness.contents=0.86;m.metalness.contents=0;m.specular.contents=CGColor(gray:0.06,alpha:1)
    m.diffuse.contents=cover ?? mediaPlaceholder(model)
    if model=="gba",let image=cover,let plane=node.geometry as? SCNPlane,image.size.height>0 {
     // A box-art fallback fills the physical sticker. Preserve the title area;
     // combine bounded vertical crop with horizontal expansion, never sidebars.
     let target=CGSize(width:600,height:600*plane.height/plane.width)
     func paint(_ cg:CGImage){
      let aspect=CGFloat(cg.width)/CGFloat(cg.height),spine:CGFloat=aspect>0.9 && aspect<1.35 ? 0.18:0
      let crop=cg.cropping(to:CGRect(x:CGFloat(cg.width)*spine,y:0,width:CGFloat(cg.width)*(1-spine),height:CGFloat(cg.height))) ?? cg
      #if canImport(UIKit)
      let art=UIImage(cgImage:crop)
      #else
      let art=NSImage(cgImage:crop,size:CGSize(width:crop.width,height:crop.height))
      #endif
      let cropFraction:CGFloat=min(0.12,max(0,(1-(art.size.width/art.size.height)/(target.width/target.height))/2))
      let visibleHeight=art.size.height*(1-2*cropFraction)
      let h=target.height*art.size.height/visibleHeight
      let r=CGRect(x:0,y:-target.height*cropFraction/(1-2*cropFraction),width:target.width,height:h)
      #if canImport(UIKit)
      UIColor(red:CGFloat((tint>>16)&255)/255*0.45,green:CGFloat((tint>>8)&255)/255*0.45,blue:CGFloat(tint&255)/255*0.45,alpha:1).setFill();UIRectFill(CGRect(origin:.zero,size:target))
      #else
      NSColor(calibratedRed:CGFloat((tint>>16)&255)/255*0.45,green:CGFloat((tint>>8)&255)/255*0.45,blue:CGFloat(tint&255)/255*0.45,alpha:1).setFill();CGRect(origin:.zero,size:target).fill()
      #endif
      art.draw(in:r)
     }
     #if canImport(UIKit)
     if let cg=image.cgImage {m.diffuse.contents=UIGraphicsImageRenderer(size:target).image{_ in paint(cg)}}
     #else
     if let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil){let labelImage=NSImage(size:target);labelImage.lockFocusFlipped(true);paint(cg);labelImage.unlockFocus();m.diffuse.contents=labelImage}
     #endif
     m.diffuse.magnificationFilter = .linear;m.diffuse.minificationFilter = .linear

    }
   }
   if m.name=="disc-read-surface" {
    // Radial diffraction changes with viewing angle; PBR still supplies the
    // actual studio highlights. The label face has no rainbow coating.
    m.shaderModifiers=[.surface:"""
    #pragma body
    vec3 N = normalize(_surface.normal);
    vec3 V = normalize(-_surface.position);
    float grazing = 1.0 - abs(dot(N,V));
    float azimuth = atan2(_surface.position.y, _surface.position.x);
    float phase = azimuth * 2.0 + grazing * 18.0;
    vec3 spectrum = 0.5 + 0.5 * cos(phase + vec3(0.0,2.094,4.188));
    float flare = pow(max(0.0,cos(azimuth*2.0+grazing*14.0)),18.0);
    float sheen = 0.18 + 0.50 * flare + 0.14 * pow(grazing,0.6);
    _surface.diffuse.rgb = mix(vec3(0.76,0.79,0.82), spectrum, sheen);
    _surface.emission.rgb = spectrum * (0.035+0.32*flare) + vec3(0.16)*pow(flare,3.0);
    """]
   }
   if m.name=="media-shell" && model != "psp" {
    // Dyed plastic is reflective, not a luminous white surface. Preserve hue
    // while leaving highlight headroom even for predominantly white box art.
    let energy=min(1,0.78/max(0.001,CGFloat(max((tint>>16)&255,max((tint>>8)&255,tint&255)))/255))
    #if canImport(UIKit)
    m.diffuse.contents=UIColor(red:CGFloat((tint>>16)&255)/255*energy,green:CGFloat((tint>>8)&255)/255*energy,blue:CGFloat(tint&255)/255*energy,alpha:1)
    #else
    m.diffuse.contents=NSColor(calibratedRed:CGFloat((tint>>16)&255)/255*energy,green:CGFloat((tint>>8)&255)/255*energy,blue:CGFloat(tint&255)/255*energy,alpha:1)
    #endif
    m.transparency=1;m.metalness.contents=0;m.roughness.contents=0.68;m.specular.contents=CGColor(gray:0.05,alpha:1)
    if Self.mediaIsTranslucent(model:model,title:title){node.opacity=0.83;node.renderingOrder=4;m.writesToDepthBuffer=false;m.roughness.contents=0.72}
   }
  }}
  return root
 }
}

/// Soft animated showcase light. Geometry is behind the selected object; small
/// seeded specks shimmer without an opaque stage or a large selection frame.
final class SpatialCeremony {
 let root=SCNNode()
 private var motes:[SCNNode]=[]
 private var focused=false
 private var beamNode:SCNNode?
 private var viewportHeight:CGFloat=0
 private static let beamImage:CGImage={
  let w=512,h=1024,c=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!,p=c.data!.assumingMemoryBound(to:UInt8.self)
  for y in 0..<h{for x in 0..<w{let t=Double(y)/Double(h-1),u=(Double(x)/Double(w-1)-0.5)/(0.035+0.43*t),a=0.62*exp(-u*u*2.2)*pow(max(0,sin(t*Double.pi)),0.9),i=(y*w+x)*4;p[i]=UInt8(255*a);p[i+1]=UInt8(218*a);p[i+2]=UInt8(134*a);p[i+3]=UInt8(255*a)}};return c.makeImage()!
 }()
 private static let moteImage:CGImage={
  let c=CGContext(data:nil,width:48,height:48,bitsPerComponent:8,bytesPerRow:192,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!,g=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[CGColor(red:1,green:0.86,blue:0.46,alpha:0.9),CGColor(red:1,green:0.76,blue:0.30,alpha:0)] as CFArray,locations:[0,1])!
  c.drawRadialGradient(g,startCenter:CGPoint(x:24,y:24),startRadius:0,endCenter:CGPoint(x:24,y:24),endRadius:23,options:[]);c.setFillColor(CGColor(red:1,green:0.94,blue:0.72,alpha:0.95));c.move(to:CGPoint(x:24,y:7));for p in [CGPoint(x:27,y:21),CGPoint(x:40,y:24),CGPoint(x:27,y:27),CGPoint(x:24,y:41),CGPoint(x:21,y:27),CGPoint(x:8,y:24),CGPoint(x:21,y:21)]{c.addLine(to:p)};c.closePath();c.fillPath();return c.makeImage()!
 }()
 init(){
  func ink(_ image:CGImage)->SCNMaterial{let m=SCNMaterial();m.diffuse.contents=image;m.diffuse.magnificationFilter = .linear;m.diffuse.minificationFilter = .linear;m.diffuse.mipFilter = .linear;m.lightingModel = .constant;m.blendMode = .add;m.writesToDepthBuffer=false;m.isDoubleSided=true;return m}
  let beam=SCNPlane(width:8.2,height:6.2),beamMaterial=ink(Self.beamImage)
  // Evaluate the light in floating point. An 8-bit premultiplied bitmap causes
  // visible contour bands when an additive gradient fills a phone display.
  beamMaterial.shaderModifiers=[.fragment:"""
  #pragma body
  float2 uv = _surface.diffuseTexcoord;
  float t = 1.0-uv.y;
  float u = (uv.x-0.5)/(0.035+0.43*t);
  float glow = 0.52*exp(-u*u*3.5)*pow(max(0.0,sin(t*3.14159265)),1.5);
  _output.color = float4(float3(1.0,0.855,0.525)*glow,glow);
  """];beam.materials=[beamMaterial];let n=SCNNode(geometry:beam);beamNode=n;n.name="ceremony-light-volume";n.position=SCNVector3(0,1.40,-1.7);n.renderingOrder = -50;root.addChildNode(n)
  for i in 0..<68{let size:CGFloat=i%9==0 ? 0.075:0.033;let plane=SCNPlane(width:size,height:size);plane.materials=[ink(Self.moteImage)];let node=SCNNode(geometry:plane);node.renderingOrder = -40;root.addChildNode(node);motes.append(node)}
  root.runAction(.repeatForever(.customAction(duration:12){[weak self] _,time in
   guard let self,!self.root.isHidden else{return};let t=Double(time)
   for (i,node) in self.motes.enumerated(){let seed=Double(i),phase=(seed*0.61803398875+t*0.085).truncatingRemainder(dividingBy:1),width=0.60+phase*2.55,x=sin(seed*8.73)*width+sin(t*0.7+seed)*0.045;node.position=SCNVector3(CGFloat(x),CGFloat(4.5-phase*7.0),CGFloat(-1.45+Double(i%3)*0.12));node.opacity=CGFloat(0.22+0.65*pow(max(0,sin(t*1.8+seed*2.1)),4))*CGFloat(sin(phase*Double.pi))}
   n.opacity=CGFloat(0.84+0.10*sin(t*0.8))
  }))
  root.opacity=0;root.isHidden=true
 }
 func fillViewport(width:CGFloat,height:CGFloat){
  guard let n=beamNode,let plane=n.geometry as? SCNPlane else{return}
  if abs(plane.width-width)<0.01 && viewportHeight==height{return}
  viewportHeight=height;plane.width=width;plane.height=height;n.position=SCNVector3(0,0,-1.7)
  plane.firstMaterial?.shaderModifiers=[.fragment:"""
  #pragma body
  float2 uv=_surface.diffuseTexcoord;
  float t=uv.y;
  float u=(uv.x-0.5)/(0.026+0.42*t);
  float fade=pow(max(0.0,1.0-t),0.8);
  float glow=0.55*exp(-u*u*4.0)*fade;
  _output.color=float4(float3(1.0,0.855,0.525)*glow,glow);
  """]
 }
 func focus(_ shown:Bool){guard focused != shown else{return};focused=shown;root.isHidden = !shown;root.opacity=0;if shown{SCNTransaction.begin();SCNTransaction.animationDuration=0.45;root.opacity=1;SCNTransaction.commit()}}
}

/// Short locally synthesized plastic friction/latch sounds, shared by both apps.
final class MediaSound {
 static let shared=MediaSound()
 private var players:[String:AVAudioPlayer]=[:],loadingEvents=Set<String>()
 func beginLoading(_ model:String){players.values.forEach{$0.stop()};loadingEvents.removeAll();advanceLoading(model,progress:0)}
 func advanceLoading(_ model:String,progress:CGFloat){for event in MediaLoadingMotion.soundEvents(model,Double(progress)) where loadingEvents.insert(event).inserted{play(event)}}
 var diagnostics:[String:Any]{players.mapValues{["playing":$0.isPlaying,"duration":$0.duration,"time":$0.currentTime]}}
 func play(_ name:String){
  if let existing=players[name]{existing.currentTime=0;existing.play();return}
  guard let url=Bundle.main.resourceURL?.appendingPathComponent("Assets/Sounds/"+name+".wav"),let player=try? AVAudioPlayer(contentsOf:url) else{return}
  player.volume=name=="media-latch" || name=="psp-door-close" ? 0.40:name=="psp-disc-read" ? 0.32:0.25;player.prepareToPlay();players[name]=player;player.play()
 }
}
