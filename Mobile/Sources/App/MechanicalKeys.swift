import UIKit
import SceneKit

/// Separate rigid caps above the shell sockets. Input remains in DeviceGeometry;
/// the visual tilt never changes logical directions or touch coordinates.
final class MechanicalKeys: SCNView {
    private var keys:[GameControl:SCNNode]=[:],cross:SCNNode?,signature="",last=Set<GameControl>()
    private var resting:[GameControl:Float]=[:]
    private var sleepWork:DispatchWorkItem?
    override init(frame:CGRect = .zero,options:[String:Any]?=nil){
        super.init(frame:frame,options:options);isUserInteractionEnabled=false;backgroundColor = .clear;isOpaque=false;scene=SCNScene();autoenablesDefaultLighting=false;antialiasingMode = .multisampling4X;preferredFramesPerSecond=60
        let camera=SCNNode();camera.name="camera";camera.camera=SCNCamera();camera.camera?.usesOrthographicProjection=true;camera.camera?.zNear=0.1;camera.camera?.zFar=2000;camera.position=SCNVector3(0,0,1000);scene!.rootNode.addChildNode(camera);pointOfView=camera
        let ambient=SCNNode();ambient.light=SCNLight();ambient.light?.type = .ambient;ambient.light?.intensity=220;scene!.rootNode.addChildNode(ambient)
        let light=SCNNode();light.light=SCNLight();light.light?.type = .directional;light.light?.intensity=1100;light.eulerAngles=SCNVector3(-0.55,-0.45,0);scene!.rootNode.addChildNode(light)
    }
    required init?(coder:NSCoder){fatalError()}
    private func material(_ tint:Int)->SCNMaterial{let m=SCNMaterial();m.diffuse.contents=UIColor(hex:UInt32(tint));m.lightingModel = .blinn;m.specular.contents=UIColor(white:0.8,alpha:1);m.shininess=0.55;return m}
    private func shoulderGeometry(_ size:CGSize,right:Bool)->SCNGeometry {
        let w=size.width,h=size.height,p=UIBezierPath()
        p.move(to:CGPoint(x:13,y:1));p.addCurve(to:CGPoint(x:w-5,y:3),controlPoint1:CGPoint(x:w*0.4,y:-3),controlPoint2:CGPoint(x:w*0.85,y:1));p.addLine(to:CGPoint(x:w-1,y:h-9));p.addCurve(to:CGPoint(x:w-10,y:h-2),controlPoint1:CGPoint(x:w,y:h-3),controlPoint2:CGPoint(x:w-4,y:h-2));p.addLine(to:CGPoint(x:5,y:h));p.addCurve(to:CGPoint(x:0,y:h-13),controlPoint1:CGPoint(x:-1,y:h-1),controlPoint2:CGPoint(x:0,y:h-8));p.addCurve(to:CGPoint(x:13,y:1),controlPoint1:CGPoint(x:1,y:7),controlPoint2:CGPoint(x:5,y:2));p.close()
        p.apply(CGAffineTransform(a:right ? -1:1,b:0,c:0,d:-1,tx:right ? w/2:-w/2,ty:h/2));p.flatness=0.05
        let g=SCNShape(path:p,extrusionDepth:5);g.chamferRadius=1.1;return g
    }
    func configure(model:DeviceModel,theme:Int,geometry g:DeviceGeometry){
        let next=model.rawValue+String(theme)+String(describing:g.controls.sorted{$0.key.rawValue<$1.key.rawValue})
        guard signature != next else{return};signature=next;keys=[:];cross=nil;resting=[:];last=[]
        for node in scene!.rootNode.childNodes where node.geometry != nil || node.name=="cross" {node.removeFromParentNode()}
        let size=g.size;pointOfView?.camera?.orthographicScale=Double(size.height/2)
        func position(_ rect:CGRect,_ z:Float=4)->SCNVector3{SCNVector3(Float(rect.midX-size.width/2),Float(size.height/2-rect.midY),z)}
        let padTint:Int=model == .gbc ? (theme==0 ? 0x167CA0:0x26302E):model == .gba ? 0xCD741C:model == .nds ? [0x697174,0xEC3B30,0xCEC69F][theme]:0x34383E
        let directions:Set<GameControl>=[.up,.down,.left,.right]
        if model != .psp {
            let rect=directions.compactMap{g.controls[$0]}.reduce(CGRect.null){$0.union($1)},w=rect.width/3,h=rect.height/3
            let p=UIBezierPath();p.move(to:CGPoint(x:-w/2,y:1.5*h));for point in [CGPoint(x:w/2,y:1.5*h),CGPoint(x:w/2,y:h/2),CGPoint(x:1.5*w,y:h/2),CGPoint(x:1.5*w,y:-h/2),CGPoint(x:w/2,y:-h/2),CGPoint(x:w/2,y:-1.5*h),CGPoint(x:-w/2,y:-1.5*h),CGPoint(x:-w/2,y:-h/2),CGPoint(x:-1.5*w,y:-h/2),CGPoint(x:-1.5*w,y:h/2),CGPoint(x:-w/2,y:h/2)]{p.addLine(to:point)};p.close();p.flatness=0.05
            let shape=SCNShape(path:p,extrusionDepth:7);shape.chamferRadius=1.1;shape.materials=[material(padTint)];let pad=SCNNode(geometry:shape);pad.position=position(rect);pad.name="cross";scene!.rootNode.addChildNode(pad);cross=pad
            for (x,y,gw,gh) in [(CGFloat(0),h,CGFloat(1.5),h*0.38),(0,-h,1.5,h*0.38),(-w,0,w*0.38,1.5),(w,0,w*0.38,1.5)]{let groove=SCNBox(width:gw,height:gh,length:0.6,chamferRadius:0.2);groove.materials=[material(0x101A19)];let n=SCNNode(geometry:groove);n.position=SCNVector3(Float(x),Float(y),3.6);pad.addChildNode(n)}
        }
        for (control,original) in g.controls {
            if model != .psp && directions.contains(control){continue}
            var r=original
            if model == .nds && (control == .select || control == .start){r=CGRect(x:r.minX,y:r.minY+3,width:18,height:18)}
            let shoulder=control == .l || control == .r,small=control == .select || control == .start,segment=directions.contains(control)
            let tint:Int=model == .gbc ? (theme==0 ? (control == .a ? 0xC71632:control == .b ? 0x14895B:0x526454):theme==1 && !small ? 0x9F164F:0x343B3A):model == .gba ? (shoulder ? [0x6C7C79,0xB8C7C0,0x85A98C][theme]:small ? 0x66796A:0x316A80):model == .psp ? (shoulder && theme==1 ? 0xB49B54:theme==0 ? 0xCBCED4:0x35363B):model == .nds ? [0x697174,0xEC3B30,0xCEC69F][theme]:0x383C40
            let round=(!small && !shoulder && !segment) || (model == .nds && small)
            let geom:SCNGeometry
            if shoulder {geom=shoulderGeometry(r.size,right:control == .r)}else if round {geom=SCNCylinder(radius:r.width/2,height:6)}else if small {let path=UIBezierPath(roundedRect:CGRect(x:-r.width/2,y:-r.height/2,width:r.width,height:r.height),cornerRadius:r.height/2);path.flatness=0.05;let pill=SCNShape(path:path,extrusionDepth:5);pill.chamferRadius=0.9;geom=pill}else{geom=SCNBox(width:r.width,height:r.height,length:5,chamferRadius:min(shoulder ? 5:segment ? 3:6,r.height*0.35))}
            geom.materials=[material(tint)];let n=SCNNode(geometry:geom);n.position=position(r);if round{n.eulerAngles.x = .pi/2};keys[control]=n;resting[control]=n.position.z;if shoulder{n.pivot=SCNMatrix4MakeTranslation(0,Float(r.height/2),0);n.position.y += Float(r.height/2)};scene!.rootNode.addChildNode(n)
            if round {let dome=SCNSphere(radius:r.width/2-0.4);dome.segmentCount=32;dome.materials=geom.materials;let top=SCNNode(geometry:dome);top.scale=SCNVector3(1,0.10,1);top.position.y=2.7;n.addChildNode(top)}
            let title:String=model == .nds && small || model == .gbc && small || model == .gba && small ? "":model == .psp ? [GameControl.a:"○",.b:"×",.x:"△",.y:"□"][control] ?? control.title:control.title
            if !title.isEmpty {
                let renderer=UIGraphicsImageRenderer(size:r.size);let image=renderer.image{_ in let paragraph=NSMutableParagraphStyle();paragraph.alignment = .center;let font=UIFont.systemFont(ofSize:shoulder ? 9:small ? 6:segment ? 13:min(20,r.width*0.55),weight:.medium);let h=font.lineHeight;(title as NSString).draw(in:CGRect(x:0,y:(r.height-h)/2,width:r.width,height:h),withAttributes:[.font:font,.foregroundColor:UIColor(hex:shoulder && (tint>>16&255)+(tint>>8&255)+(tint&255)>440 || model == .psp && theme==0 ? 0x53615C:0xDCE3D9),.paragraphStyle:paragraph])}
                let plane=SCNPlane(width:r.width,height:r.height),m=SCNMaterial();m.diffuse.contents=image;m.lightingModel = .constant;plane.materials=[m];let text=SCNNode(geometry:plane);if round{text.eulerAngles.x = -.pi/2;text.position.y=Float(3+r.width*0.05)}else{text.position.z=3};n.addChildNode(text)
            }
        }
        wake()
    }
    func setHeld(_ held:Set<GameControl>){
        guard held != last else{return};last=held;wake()
        SCNTransaction.begin();SCNTransaction.animationDuration=0.07;SCNTransaction.animationTimingFunction=CAMediaTimingFunction(name:.easeOut)
        for (control,node) in keys {node.position.z=(resting[control] ?? 4)-(held.contains(control) ? 2.5:0);if control == .l || control == .r {node.eulerAngles.x=held.contains(control) ? -0.08:0}}
        if let cross {let pose=DPadPose(held:held);cross.eulerAngles=SCNVector3(Float(pose.x),Float(pose.y),0)}
        SCNTransaction.commit()
    }
    #if DEBUG
    var mechanicalState:[String:Any]{["cross":cross.map{[Double($0.eulerAngles.x),Double($0.eulerAngles.y)]} ?? [],"depth":Dictionary(uniqueKeysWithValues:keys.map{(String($0.key.rawValue),Double($0.value.position.z))}),"held":last.map{$0.rawValue}.sorted(),"rigidCross":cross != nil]}
    #endif
    private func wake(){sleepWork?.cancel();isPlaying=true;rendersContinuously=true;let work=DispatchWorkItem{[weak self] in self?.isPlaying=false;self?.rendersContinuously=false};sleepWork=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.18,execute:work)}
}
