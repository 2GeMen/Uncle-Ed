import Cocoa
import SceneKit

// Native geometry for the complete GBC flow. Only print and game pixels use textures.
private func gbcMaterial(_ tint:Int,_ roughness:CGFloat=0.42,_ metallic:CGFloat=0)->SCNMaterial {
  let m=SCNMaterial();m.diffuse.contents=color(tint);m.lightingModel = .physicallyBased;m.roughness.contents=roughness;m.metalness.contents=metallic;return m
}
private func gbcPoint(_ x:CGFloat,_ y:CGFloat,_ z:Float)->SCNVector3 {SCNVector3(Float((x-175)/100),Float((285-y)/100),z)}
private func gbcPrint(_ size:CGSize,_ body:()->Void)->NSImage {
  let q:CGFloat=3,w=Int(size.width*q),h=Int(size.height*q)
  let c=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
  c.translateBy(x:0,y:CGFloat(h));c.scaleBy(x:q,y:-q)
  NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:c,flipped:true);body();NSGraphicsContext.restoreGraphicsState()
  return NSImage(cgImage:c.makeImage()!,size:size)
}
private func gbcDecal(_ image:Any?,width:CGFloat,height:CGFloat)->SCNNode {
  let p=SCNPlane(width:width,height:height),m=SCNMaterial();m.diffuse.contents=image;m.lightingModel = .constant;m.isDoubleSided=false;m.diffuse.magnificationFilter = .linear;m.writesToDepthBuffer=false;p.materials=[m];return SCNNode(geometry:p)
}
final class GBCMachineMesh {
  let root=SCNNode(),screen=SCNMaterial()
  var buttons:[Int:SCNNode]=[:]
  private let led=SCNMaterial()
  private var lastPadPose=SCNVector3Zero,lastHeld=Set<Int>()
  init(theme:Int,owner:StudioView){
    let tint=[0xF59B19,0xD9D8C5,0xE9C521][min(2,max(0,theme))],shell=gbcMaterial(tint,0.38),edge=gbcMaterial(tint,0.52)
    // Front shell and rear shell have separate thicknesses. The rear has an open
    // cartridge pocket, so the media is physically occluded by the housing.
    let outline=NSBezierPath(roundedRect:NSRect(x:-1.75,y:-2.85,width:3.5,height:5.7),xRadius:0.27,yRadius:0.27)
    outline.flatness=0.002
    let frontProfile=outline.copy() as! NSBezierPath
    // Apertures are cut out of the molding. No transparent solid slab crosses
    // the key wells or LCD, and the real shell wall is separate from its face.
    frontProfile.append(NSBezierPath(roundedRect:CGRect(x:-1.13,y:-0.088,width:2.26,height:2.06),xRadius:0.025,yRadius:0.025).reversed)
    let crossHole=NSBezierPath();crossHole.move(to:CGPoint(x:-0.15,y:0.435));for p in [CGPoint(x:0.15,y:0.435),CGPoint(x:0.15,y:0.15),CGPoint(x:0.435,y:0.15),CGPoint(x:0.435,y:-0.15),CGPoint(x:0.15,y:-0.15),CGPoint(x:0.15,y:-0.435),CGPoint(x:-0.15,y:-0.435),CGPoint(x:-0.15,y:-0.15),CGPoint(x:-0.435,y:-0.15),CGPoint(x:-0.435,y:0.15),CGPoint(x:-0.15,y:0.15)]{crossHole.line(to:p)};crossHole.close();let shift=AffineTransform(translationByX:-0.98,byY:-0.97);crossHole.transform(using:shift);frontProfile.append(crossHole.reversed)
    for c in [CGPoint(x:0.54,y:-1.15),CGPoint(x:1.10,y:-0.89)]{frontProfile.append(NSBezierPath(ovalIn:CGRect(x:c.x-0.232,y:c.y-0.232,width:0.464,height:0.464)).reversed)}
    for x:CGFloat in [-0.405,0.145]{frontProfile.append(NSBezierPath(roundedRect:CGRect(x:x-0.205,y:-1.965,width:0.41,height:0.17),xRadius:0.08,yRadius:0.08).reversed)}
    let front=SCNShape(path:frontProfile,extrusionDepth:0.065);front.chamferRadius=0.055;front.materials=[shell]
    let f=SCNNode(geometry:front);f.position.z=0.5175;f.name="front-shell";root.addChildNode(f)
    let wallProfile=outline.copy() as! NSBezierPath;wallProfile.append(NSBezierPath(roundedRect:CGRect(x:-1.68,y:-2.78,width:3.36,height:5.56),xRadius:0.22,yRadius:0.22).reversed);let wall=SCNShape(path:wallProfile,extrusionDepth:0.48);wall.materials=[edge];let side=SCNNode(geometry:wall);side.name="front-shell-sidewall";side.position.z=0.24;root.addChildNode(side)
    let back=NSBezierPath();back.move(to:NSPoint(x:-1.48,y:2.85));back.line(to:NSPoint(x:-1.30,y:2.85));back.line(to:NSPoint(x:-1.30,y:-0.08));back.line(to:NSPoint(x:1.30,y:-0.08));back.line(to:NSPoint(x:1.30,y:2.85));back.line(to:NSPoint(x:1.48,y:2.85));back.curve(to:NSPoint(x:1.75,y:2.58),controlPoint1:NSPoint(x:1.65,y:2.85),controlPoint2:NSPoint(x:1.75,y:2.75));back.line(to:NSPoint(x:1.75,y:-2.5));back.curve(to:NSPoint(x:1.4,y:-2.85),controlPoint1:NSPoint(x:1.75,y:-2.72),controlPoint2:NSPoint(x:1.6,y:-2.85));back.line(to:NSPoint(x:-1.48,y:-2.85));back.curve(to:NSPoint(x:-1.75,y:-2.58),controlPoint1:NSPoint(x:-1.65,y:-2.85),controlPoint2:NSPoint(x:-1.75,y:-2.75));back.line(to:NSPoint(x:-1.75,y:2.58));back.curve(to:NSPoint(x:-1.48,y:2.85),controlPoint1:NSPoint(x:-1.75,y:2.75),controlPoint2:NSPoint(x:-1.65,y:2.85));back.close()
    back.flatness=0.002
    let rear=SCNShape(path:back,extrusionDepth:0.46);rear.chamferRadius=0.045;rear.materials=[edge];let b=SCNNode(geometry:rear);b.position.z = -0.24;root.addChildNode(b)
    func box(_ w:CGFloat,_ h:CGFloat,_ d:CGFloat,_ radius:CGFloat,_ mat:SCNMaterial,_ point:SCNVector3)->SCNNode {let g=SCNBox(width:w,height:h,length:d,chamferRadius:radius);g.materials=[mat];let n=SCNNode(geometry:g);n.position=point;root.addChildNode(n);return n}
    let black=gbcMaterial(0x101918,0.5)
    _=box(2.58,0.06,0.42,0.01,black,SCNVector3(0,-0.06,-0.24))
    for x in [Float(-1.29),1.29]{_=box(0.035,2.5,0.34,0.008,black,SCNVector3(x,1.58,-0.24))}
    let battery=box(2.45,2.05,0.075,0.1,edge,SCNVector3(0,-1.5,-0.535));battery.name="battery-door"
    for (x,y) in [(-1.5,2.4),(1.5,2.4),(-1.5,-2.4),(1.5,-2.4)] {
      let screw=SCNCylinder(radius:0.045,height:0.018);screw.materials=[gbcMaterial(0x626B62,0.3,0.7)];let n=SCNNode(geometry:screw);n.eulerAngles.x = .pi/2;n.position=SCNVector3(Float(x),Float(y),-0.53);n.name="legacy-rear-fastener";root.addChildNode(n)
    }
    let bezelTint=theme==1 ? 0x838A88:0x20282A
    _=box(3.0,2.74,0.105,0.11,gbcMaterial(bezelTint,0.28),gbcPoint(175,163,0.565))
    _=box(2.22,2.01,0.04,0.025,black,gbcPoint(175,154.5,0.635))
    let glass=SCNPlane(width:2.12,height:1.91);screen.name="screen:0";screen.lightingModel = .constant;screen.diffuse.contents=color(0x182423);screen.diffuse.magnificationFilter = .nearest;screen.diffuse.minificationFilter = .nearest;glass.materials=[screen];let display=SCNNode(geometry:glass);display.position=gbcPoint(175,154.5,0.662);display.name="screen:0";root.addChildNode(display)
    let print=gbcPrint(CGSize(width:350,height:570)){
      owner.centered("GAME BOY",147,269,15,color(0xB1C1B8),.bold)
      for (i,letter) in Array("COLOR").enumerated(){owner.text(String(letter),195+CGFloat(i)*13,269,15,color([0xD7357A,0x615CB2,0x7EBE34,0xDCB929,0x269CBA][i]),.bold)}
      owner.text("POWER",30,101,4,color(0xA8B2A4))
      owner.centered("Nintendo",175,324,11,color(theme==0 ? 0xA85B08:0x9B9C83),.bold)
      owner.centered("SELECT",134.5,489,6,color(0x777C65));owner.centered("START",189.5,489,6,color(0x777C65))
      if theme==0{owner.drawPKCDecal();owner.centered("◉ POKÉMON CENTER",156,535,10,color(0x263A47),.bold)}
      if theme==1{owner.line([CGPoint(x:38,y:40),CGPoint(x:124,y:40)],color(0x722855),2);owner.line([CGPoint(x:38,y:44),CGPoint(x:124,y:44)],color(0x334775),1);owner.text("DOT MATRIX WITH STEREO SOUND",132,39,5,color(0xCDD3C9))}
    }
    let rim=NSBezierPath(roundedRect:NSRect(x:-0.50,y:-0.115,width:1,height:0.23),xRadius:0.115,yRadius:0.115);rim.append(NSBezierPath(roundedRect:NSRect(x:-0.475,y:-0.09,width:0.95,height:0.18),xRadius:0.09,yRadius:0.09).reversed);rim.flatness=0.002
    let molded=SCNShape(path:rim,extrusionDepth:0.022);molded.materials=[edge];let brand=SCNNode(geometry:molded);brand.position=gbcPoint(175,330,0.562);root.addChildNode(brand)
    let ink=gbcDecal(print,width:3.5,height:5.7);ink.position.z=0.675;root.addChildNode(ink)
    for (id,r) in [(8,CGRect(x:263,y:352,width:44,height:44)),(0,CGRect(x:207,y:378,width:44,height:44)),(2,CGRect(x:115,y:466,width:39,height:14)),(3,CGRect(x:170,y:466,width:39,height:14))] {
      let keyTint=theme==0 ? (id==8 ? 0xD73545: id==0 ? 0x238B64:0x343D3B):theme==1 && id<2 || theme==1 && id==8 ? 0x982956:0x333E3A
      let keyOutline=NSBezierPath(roundedRect:CGRect(x:-r.width/200,y:-r.height/200,width:r.width/100,height:r.height/100),xRadius:r.height/200,yRadius:r.height/200);keyOutline.flatness=0.002;let pill=SCNShape(path:keyOutline,extrusionDepth:0.08);pill.chamferRadius=0.012
      let geometry:SCNGeometry=id==0 || id==8 ? SCNCylinder(radius:0.22,height:0.095):pill
      geometry.materials=[gbcMaterial(keyTint,0.24)];let n=SCNNode(geometry:geometry);if id==0 || id==8{n.eulerAngles.x = .pi/2};n.position=gbcPoint(r.midX,r.midY,0.65);n.name="key:\(id)";root.addChildNode(n);buttons[id]=n
      if id==0 || id==8 {
        let label=gbcPrint(CGSize(width:44,height:44)){owner.centered(id==8 ? "A":"B",22,10,20,color(theme==0 ? 0xC9D5C8:0xD5CCD2),.semibold)}
        let cap=SCNSphere(radius:0.218);cap.segmentCount=48;cap.materials=[gbcMaterial(keyTint,0.24)];let top=SCNNode(geometry:cap);top.scale=SCNVector3(1,0.12,1);top.position.y=0.045;n.addChildNode(top)
        let letters=gbcDecal(label,width:0.44,height:0.44);letters.eulerAngles.x = -.pi/2;letters.position.y=0.073;n.addChildNode(letters)
      }
    }
    let pad=NSBezierPath();pad.move(to:NSPoint(x:-0.14,y:0.42));for p in [NSPoint(x:0.14,y:0.42),NSPoint(x:0.14,y:0.14),NSPoint(x:0.42,y:0.14),NSPoint(x:0.42,y:-0.14),NSPoint(x:0.14,y:-0.14),NSPoint(x:0.14,y:-0.42),NSPoint(x:-0.14,y:-0.42),NSPoint(x:-0.14,y:-0.14),NSPoint(x:-0.42,y:-0.14),NSPoint(x:-0.42,y:0.14),NSPoint(x:-0.14,y:0.14)]{pad.line(to:p)};pad.close();pad.flatness=0.002;let cross=SCNShape(path:pad,extrusionDepth:0.18);cross.chamferRadius=0.022;cross.materials=[gbcMaterial(theme==0 ? 0x167CA0:0x26302E,0.3)];let dpad=SCNNode(geometry:cross);dpad.position=gbcPoint(77,382,0.66);dpad.name="dpad";root.addChildNode(dpad);for i in 4...7{buttons[i]=dpad}
    for (x,y,w,h) in [(0.0,0.27,0.018,0.11),(0.0,-0.27,0.018,0.11),(-0.27,0.0,0.11,0.018),(0.27,0.0,0.11,0.018)]{let groove=SCNBox(width:w,height:h,length:0.006,chamferRadius:0.002);groove.materials=[gbcMaterial(0x111B1A,0.7)];let n=SCNNode(geometry:groove);n.position=SCNVector3(Float(x),Float(y),0.094);dpad.addChildNode(n)}
    for row in 0..<7 {for col in 0..<7 {let hole=SCNCylinder(radius:0.018,height:0.018);hole.materials=[black];let n=SCNNode(geometry:hole);n.eulerAngles.x = .pi/2;n.position=gbcPoint(CGFloat(250+col*9),CGFloat(464+row*9-col*2),0.556);root.addChildNode(n)}}
    let track=box(0.12,0.43,0.20,0.025,gbcMaterial(0x1F2925,0.55),gbcPoint(353.5,102,0.05));track.name="power"
    let slider=box(0.13,0.20,0.22,0.025,gbcMaterial(0x697365,0.36),gbcPoint(353.5,107,0.06));slider.name="power-slider"
    for y in [-0.055,0,0.055]{let rib=box(0.135,0.012,0.012,0.002,gbcMaterial(0xA8B39E,0.45),SCNVector3Zero);rib.removeFromParentNode();rib.position=SCNVector3(0,CGFloat(y),0.116);slider.addChildNode(rib)}
    let bulb=SCNSphere(radius:0.027);led.diffuse.contents=color(0x643832);led.emission.contents=color(0x000000);bulb.materials=[led];let diode=SCNNode(geometry:bulb);diode.position=gbcPoint(41.5,91.5,0.69);root.addChildNode(diode)
  }
  func update(frame:CGImage?,held:Set<Int>,powered:Bool){screen.diffuse.contents=powered ? (frame as Any? ?? color(0x182423)):color(0x182423);led.emission.contents=color(powered ? 0xB53425:0x000000)
    // The four directions are a single mesh, never four independently pressed tiles.
    for (id,n) in buttons where !(4...7).contains(id) && held.contains(id) != lastHeld.contains(id) {
      n.removeAction(forKey:"travel");let action=SCNAction.move(to:SCNVector3(n.position.x,n.position.y,0.65-(held.contains(id) ? 0.035:0)),duration:held.contains(id) ? 0.055:0.08);action.timingMode = .easeOut;n.runAction(action,forKey:"travel")
    }
    lastHeld=held
    let x=Float((held.contains(5) ? 1:0)-(held.contains(4) ? 1:0)),y=Float((held.contains(7) ? 1:0)-(held.contains(6) ? 1:0)),length=max(1,sqrt(x*x+y*y))
    if let pad=buttons[4] {
      let target=SCNVector3(x/length*0.14,y/length*0.14,0)
      if lastPadPose.x != target.x || lastPadPose.y != target.y { pad.removeAction(forKey:"rock");pad.runAction(.rotateTo(x:CGFloat(target.x),y:CGFloat(target.y),z:0,duration:0.065,usesShortestUnitArc:true),forKey:"rock");lastPadPose=target }
    }
  }
}
extension StudioView {
  var usesGBC3D:Bool{!CommandLine.arguments.contains("--render-source") && SpatialMachine.exists(handheld.rawValue,theme)}
  func drawGBCCardLabels(){
   guard phase == .library else{return}
   centered("选择游戏",360,115,25,color(0xF0EAD9),.semibold)
   for (i,game) in games.enumerated(){let r=cardRect(i);guard r.midX > -80 && r.midX<800 else{continue}
    let lookup=game.url.lastPathComponent;gameCatalog.request(model:handheld.rawValue,name:lookup)
    let title=GameCatalog.title(game.title),style=NSMutableParagraphStyle();style.alignment = .center;style.lineBreakMode = .byWordWrapping
    let width=max(178,min(250,spatialCardStride-18)),area=CGRect(x:r.midX-width/2,y:r.maxY+13,width:width,height:64)
    (title as NSString).draw(in:area,withAttributes:[.font:NSFont.systemFont(ofSize:11,weight:.medium),.foregroundColor:color(i==selectedIndex ? 0xD8E4CE:0x819184),.paragraphStyle:style])
   }
   if games.indices.contains(selectedIndex){let game=games[selectedIndex],record=gameCatalog.cached(model:handheld.rawValue,name:game.url.lastPathComponent)
    let style=NSMutableParagraphStyle();style.alignment = .center;style.lineBreakMode = .byWordWrapping
    let text="开发 · "+(record?.developer ?? "/")+"   出品 · "+(record?.publisher ?? "/")+"\n发售 · "+(record?.releaseDate ?? "/")+(record?.releaseRegion.map{" · "+$0} ?? "")+"    Metacritic · "+(record?.scoreText ?? "/")
    let labelWidth=max(178,min(250,spatialCardStride-18)),titleHeight=games.map{(GameCatalog.title($0.title) as NSString).boundingRect(with:CGSize(width:labelWidth,height:90),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:NSFont.systemFont(ofSize:11,weight:.medium)]).height}.max() ?? 16
    (text as NSString).draw(in:CGRect(x:80,y:cardRect(selectedIndex).maxY+21+titleHeight,width:560,height:58),withAttributes:[.font:NSFont.systemFont(ofSize:10,weight:.medium),.foregroundColor:color(0xB7BDB0),.paragraphStyle:style])
   }
   drawPageDots(count:games.count,index:selectedIndex,y:680)
   centered("横向滑动选卡 · 点击或回车拿起卡带",360,650,12,color(0x96A18F))
  }
}
