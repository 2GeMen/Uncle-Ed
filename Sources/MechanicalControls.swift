import Cocoa
import SceneKit

private final class MechanicalControlView:SCNView {
  override func hitTest(_ point:NSPoint)->NSView?{nil} // The existing machine touch map remains authoritative.
}
final class MechanicalControlStage {
  weak var owner:StudioView?
  private let view=MechanicalControlView(),scene=SCNScene(),camera=SCNNode(),pivot=SCNNode()
  private var signature="",buttons:[Int:SCNNode]=[:],cross:SCNNode?,previous=Set<Int>()
  init(owner:StudioView){self.owner=owner;view.scene=scene;view.backgroundColor = .clear;view.wantsLayer=true;view.layer?.backgroundColor=NSColor.clear.cgColor;view.antialiasingMode = .multisampling4X;view.preferredFramesPerSecond=60
    camera.camera=SCNCamera();camera.camera?.usesOrthographicProjection=true;camera.camera?.zFar=2000;camera.position=SCNVector3(0,0,1000);scene.rootNode.addChildNode(camera);view.pointOfView=camera;scene.rootNode.addChildNode(pivot)
    let ambient=SCNNode();ambient.light=SCNLight();ambient.light?.type = .ambient;ambient.light?.intensity=220;scene.rootNode.addChildNode(ambient)
    let key=SCNNode();key.light=SCNLight();key.light?.type = .directional;key.light?.intensity=1100;key.eulerAngles=SCNVector3(-0.55,-0.45,0);scene.rootNode.addChildNode(key)
    owner.addSubview(view)
  }
  private func material(_ tint:Int)->SCNMaterial{let m=SCNMaterial();m.diffuse.contents=color(tint);m.lightingModel = .blinn;m.specular.contents=NSColor(white:0.8,alpha:1);m.shininess=0.55;return m}
  func exportedControls()->SCNNode {guard let owner else{return SCNNode()};build(owner);let node=pivot.clone();node.position=SCNVector3Zero;node.eulerAngles=SCNVector3Zero;return node}
  private func shoulderGeometry(_ size:CGSize,right:Bool)->SCNGeometry {
    let w=size.width,h=size.height,p=NSBezierPath();p.move(to:NSPoint(x:13,y:1));p.curve(to:NSPoint(x:w-5,y:3),controlPoint1:NSPoint(x:w*0.4,y:-3),controlPoint2:NSPoint(x:w*0.85,y:1));p.line(to:NSPoint(x:w-1,y:h-9));p.curve(to:NSPoint(x:w-10,y:h-2),controlPoint1:NSPoint(x:w,y:h-3),controlPoint2:NSPoint(x:w-4,y:h-2));p.line(to:NSPoint(x:5,y:h));p.curve(to:NSPoint(x:0,y:h-13),controlPoint1:NSPoint(x:-1,y:h-1),controlPoint2:NSPoint(x:0,y:h-8));p.curve(to:NSPoint(x:13,y:1),controlPoint1:NSPoint(x:1,y:7),controlPoint2:NSPoint(x:5,y:2));p.close()
    p.transform(using:AffineTransform(m11:right ? -1:1,m12:0,m21:0,m22:-1,tX:right ? w/2:-w/2,tY:h/2));p.flatness=0.05;let g=SCNShape(path:p,extrusionDepth:5);g.chamferRadius=1.1;return g
  }
  func sync(){guard let owner else{return};let active=owner.usesMechanicalControls
    view.isHidden = !active;view.isPlaying=active;view.rendersContinuously=active;if !active{return}
    view.frame=CGRect(x:owner.offset.x,y:owner.offset.y,width:720*owner.scale,height:owner.canvasHeight*owner.scale);camera.camera?.orthographicScale=Double(owner.canvasHeight/2)
    pivot.position=SCNVector3(0,Float(owner.canvasHeight/2-410),0);pivot.eulerAngles.z=owner.pose * .pi/2
    let next=owner.handheld.rawValue+String(owner.theme)
    if signature != next{signature=next;build(owner);previous=[]}
    if previous != owner.held {
      SCNTransaction.begin();SCNTransaction.animationDuration=0.07;SCNTransaction.animationTimingFunction=CAMediaTimingFunction(name:.easeOut)
      for (id,node) in buttons {node.position.z=owner.held.contains(id) ? 1.5:4;if id==10 || id==11{node.eulerAngles.x=owner.held.contains(id) ? -0.08:0}}
      let x=Float((owner.held.contains(5) ? 1:0)-(owner.held.contains(4) ? 1:0)),y=Float((owner.held.contains(7) ? 1:0)-(owner.held.contains(6) ? 1:0)),length=max(1,sqrt(x*x+y*y))
      cross?.eulerAngles=SCNVector3(x/length*0.14,y/length*0.14,0);SCNTransaction.commit();previous=owner.held
    }
  }
  private func build(_ owner:StudioView){for n in pivot.childNodes{n.removeFromParentNode()};buttons=[:];cross=nil
    func point(_ r:CGRect)->SCNVector3{SCNVector3(Float(r.midX-360),Float(410-r.midY),4)}
    let kind=owner.handheld,t=owner.theme
    let padTint=kind == .gba ? 0xCD741C:kind == .nds ? owner.keyHi:0x34383E
    if kind != .psp {
      let r=owner.dpad.map{$0.2.offsetBy(dx:-240,dy:0)}.reduce(CGRect.null){$0.union($1)},w=r.width/3,h=r.height/3
      let p=NSBezierPath();p.move(to:NSPoint(x:-w/2,y:1.5*h));for q in [NSPoint(x:w/2,y:1.5*h),NSPoint(x:w/2,y:h/2),NSPoint(x:1.5*w,y:h/2),NSPoint(x:1.5*w,y:-h/2),NSPoint(x:w/2,y:-h/2),NSPoint(x:w/2,y:-1.5*h),NSPoint(x:-w/2,y:-1.5*h),NSPoint(x:-w/2,y:-h/2),NSPoint(x:-1.5*w,y:-h/2),NSPoint(x:-1.5*w,y:h/2),NSPoint(x:-w/2,y:h/2)]{p.line(to:q)};p.close();p.flatness=0.05
      let g=SCNShape(path:p,extrusionDepth:10);g.chamferRadius=1.5;g.materials=[material(padTint)];let n=SCNNode(geometry:g);n.position=point(r);pivot.addChildNode(n);cross=n;n.name="dpad"
      for (x,y,gw,gh) in [(CGFloat(0),h,CGFloat(1.5),h*0.38),(0,-h,1.5,h*0.38),(-w,0,w*0.38,1.5),(w,0,w*0.38,1.5)]{let groove=SCNBox(width:gw,height:gh,length:0.6,chamferRadius:0.2);groove.materials=[material(0x101A19)];let mark=SCNNode(geometry:groove);mark.position=SCNVector3(Float(x),Float(y),3.6);n.addChildNode(mark)}
    }
    let defs=owner.buttons+(kind == .psp ? owner.dpad:[])
    for (name,id,world) in defs {
      var r=world.offsetBy(dx:-240,dy:0);let small=id==2 || id==3,shoulder=id==10 || id==11,segment=(4...7).contains(id)
      if kind == .nds && small{r=CGRect(x:r.minX,y:r.minY+3,width:18,height:18)}
      let round=(!small && !shoulder && !segment) || ((kind == .nds || kind == .gba) && small)
      let tint=kind == .gba ? (shoulder ? [0xE5E7E3,0xE5E7E3,0x8DE516,0xEFF2F1][t]:[0xE5E7E3,0xE5E7E3,0x8DE516,0xEFF2F1][t]):kind == .nds ? owner.keyHi:kind == .psp ? (shoulder && t==1 ? 0xB49B54:t==0 ? 0xCBCED4:0x35363B):0x383C40
      let pill=NSBezierPath(roundedRect:CGRect(x:-r.width/2,y:-r.height/2,width:r.width,height:r.height),xRadius:r.height/2,yRadius:r.height/2);pill.flatness=0.05;let soft=SCNShape(path:pill,extrusionDepth:5);soft.chamferRadius=0.9
      let geom:SCNGeometry=shoulder && kind != .psp ? shoulderGeometry(r.size,right:id==11):shoulder ? soft:round ? SCNCylinder(radius:r.width/2,height:6):small ? soft:SCNBox(width:r.width,height:r.height,length:5,chamferRadius:min(shoulder ? 5:segment ? 3:6,r.height*0.35))
      geom.materials=[material(tint)];let n=SCNNode(geometry:geom);n.position=point(r);if round{n.eulerAngles.x = .pi/2};pivot.addChildNode(n);buttons[id]=n;n.name="key:\(id)"
      if shoulder {n.pivot=SCNMatrix4MakeTranslation(0,r.height/2,0);n.position.y += r.height/2}
      if round{let dome=SCNSphere(radius:r.width/2-0.4);dome.segmentCount=32;dome.materials=geom.materials;let top=SCNNode(geometry:dome);top.scale=SCNVector3(1,0.1,1);top.position.y=2.7;n.addChildNode(top)}
      let title=kind == .nds && small || kind == .gba && small ? "":segment ? [4:"△",5:"▽",6:"◁",7:"▷"][id]!:name
      if !title.isEmpty {
        let image=NSImage(size:r.size);image.lockFocusFlipped(true);owner.centered(title,r.width/2,(r.height-(small ? 8:shoulder ? 11:21))/2,small ? 6:shoulder ? 9:segment ? 13:17,color(kind == .gba ? (t==2 ? 0x31550C:0x68746D):shoulder && (tint>>16&255)+(tint>>8&255)+(tint&255)>440 || kind == .psp && t==0 ? 0x53615C:0xDCE3D9),.medium);image.unlockFocus()
        let plane=SCNPlane(width:r.width,height:r.height),m=SCNMaterial();m.diffuse.contents=image;m.lightingModel = .constant;m.writesToDepthBuffer=false;plane.materials=[m];let label=SCNNode(geometry:plane);if round{label.eulerAngles.x = -.pi/2;label.position.y=3+r.width*0.05}else{label.position.z=3};n.addChildNode(label)
      }
    }
  }
}
extension StudioView {
  var usesMechanicalControls:Bool{!CommandLine.arguments.contains("--render-source") && !usesGBC3D && handheld != .gbc && !choosing && !focusActive && (phase == .playing || phase == .idleOpen)}
  var omitControlCaps:Bool{exportBareKeys || usesMechanicalControls}
}
