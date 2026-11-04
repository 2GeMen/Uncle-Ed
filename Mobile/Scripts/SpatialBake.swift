// Baked once on Mac, consumed unchanged by SceneKit on macOS and iOS.
import SceneKit
import CryptoKit
final class SpatialImageWriter:NSObject,SCNSceneExportDelegate {
 func write(_ image:NSImage,withSceneDocumentURL url:URL,originalImageURL:URL?)->URL? {
  guard let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil),let data=NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:]) else{return nil}
  let hash=SHA256.hash(data:data).prefix(12).map{String(format:"%02x",$0)}.joined(),dest=url.deletingLastPathComponent().appendingPathComponent(hash+".png");try! data.write(to:dest);return dest
 }
}
// A shallow tangent-space normal map for the fine grey etching visible in the
// reference. Painted/color artwork remains an albedo/roughness layer instead.
func spatialEtchNormal(_ image:NSImage)->NSImage? {
 guard let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil) else{return nil}
 let width=cg.width,height=cg.height,source=NSBitmapImageRep(cgImage:cg)
 guard let output=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:width*4,bitsPerPixel:32),let bytes=output.bitmapData else{return nil}
 func value(_ x:Int,_ y:Int)->Double{guard let c=source.colorAt(x:max(0,min(width-1,x)),y:max(0,min(height-1,y)))?.usingColorSpace(.sRGB) else{return 1};return Double(c.redComponent*0.2126+c.greenComponent*0.7152+c.blueComponent*0.0722)}
 for y in 0..<height{for x in 0..<width{let dx=(value(x+1,y)-value(x-1,y))*0.9,dy=(value(x,y+1)-value(x,y-1))*0.9,n=sqrt(dx*dx+dy*dy+1),i=y*width*4+x*4;bytes[i]=UInt8(max(0,min(255,128-dx/n*127)));bytes[i+1]=UInt8(max(0,min(255,128+dy/n*127)));bytes[i+2]=UInt8(128+127/n);bytes[i+3]=255}}
 let result=NSImage(size:image.size);result.addRepresentation(output);return result
}
func bakeSpatialModels(){
 let destination=exportRoot.appendingPathComponent("Spatial");try! fm.createDirectory(at:destination,withIntermediateDirectories:true);let writer=SpatialImageWriter()
 func mat(_ tint:Int,_ rough:CGFloat=0.4,_ metallic:CGFloat=0)->SCNMaterial{let m=SCNMaterial();m.diffuse.contents=color(tint);m.lightingModel = .physicallyBased;m.roughness.contents=rough;m.metalness.contents=metallic;return m}
 func image(_ stem:String)->NSImage?{NSImage(contentsOf:exportRoot.appendingPathComponent(stem+".png"))}
 func plane(_ image:NSImage?,_ size:CGSize)->SCNNode{let g=SCNPlane(width:size.width/100,height:size.height/100),m=mat(0xFFFFFF);m.diffuse.contents=image;m.writesToDepthBuffer=false;g.materials=[m];return SCNNode(geometry:g)}
 func shape(_ path:NSBezierPath,_ depth:CGFloat,_ tint:Int)->SCNNode{path.flatness=0.002;let g=SCNShape(path:path,extrusionDepth:depth);g.chamferRadius=min(0.035,depth*0.15);g.materials=[mat(tint)];return SCNNode(geometry:g)}
 func box(_ width:CGFloat,_ height:CGFloat,_ depth:CGFloat,_ tint:Int,_ radius:CGFloat=0.03)->SCNNode{let g=SCNBox(width:width,height:height,length:depth,chamferRadius:radius);g.materials=[mat(tint)];return SCNNode(geometry:g)}
 // The shoulder paddles replace a shallow part of the top corner. Relieve all
 // three shell layers together, otherwise the rear lip cuts through the cap.
 func gbaShoulderRelief(_ path:NSBezierPath)->NSBezierPath{
  let previous=NSBezierPath.defaultFlatness;NSBezierPath.defaultFlatness=0.002;let flat=path.flattened;NSBezierPath.defaultFlatness=previous
  let result=NSBezierPath();var tmp=[NSPoint](repeating:.zero,count:3),previousPoint=CGPoint.zero
  func smooth(_ x:CGFloat)->CGFloat{let t=max(0,min(1,x));return t*t*(3-2*t)}
  func relief(_ input:CGPoint)->CGPoint{var p=input;let x=abs(p.x);p.y -= 0.225*smooth((x-2.10)/0.07)*smooth((3.15-x)/0.09)*smooth((p.y-1.02)/0.20);return p}
  for i in 0..<flat.elementCount{let kind=flat.element(at:i,associatedPoints:&tmp)
   if kind == .closePath{result.close();continue}
   guard kind == .moveTo || kind == .lineTo else{continue}
   let end=tmp[0]
   if kind == .moveTo{result.move(to:relief(end))}else{
    // Rear top rails contain long straight segments: sample before bending the
    // relief, otherwise one interpolated triangle still cuts through the cap.
    let delta=CGPoint(x:end.x-previousPoint.x,y:end.y-previousPoint.y),steps=max(1,Int(ceil(hypot(delta.x,delta.y)/0.015)))
    for j in 1...steps{let t=CGFloat(j)/CGFloat(steps);result.line(to:relief(CGPoint(x:previousPoint.x+delta.x*t,y:previousPoint.y+delta.y*t)))}
   };previousPoint=end
  };return result
 }
 // Explicit portable front triangles avoid platform-specific SCNShape cap tessellation.
 func gbaFront(_ contour:NSBezierPath,_ tint:Int,relief:Bool=true,scale:CGFloat=0.97,face:CGFloat=1)->SCNNode {
  let previous=NSBezierPath.defaultFlatness;NSBezierPath.defaultFlatness=0.002;let flat=(relief ? gbaShoulderRelief(contour):contour).flattened;NSBezierPath.defaultFlatness=previous
  var outline=[CGPoint](),tmp=[NSPoint](repeating:.zero,count:3)
  for i in 0..<flat.elementCount{let type=flat.element(at:i,associatedPoints:&tmp);if type == .moveTo || type == .lineTo{if outline.last != tmp[0]{outline.append(tmp[0])}}}
  if outline.first==outline.last{outline.removeLast()}
  // Shoulder recesses make this a concave outline. A centre fan overlaps the
  // face along radial seams, so clip ears and publish explicit portable triangles.
  func cross(_ a:CGPoint,_ b:CGPoint,_ c:CGPoint)->CGFloat{(b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)}
  var changed=true
  while changed && outline.count>3{changed=false;for i in 0..<outline.count{let a=outline[(i+outline.count-1)%outline.count],b=outline[i],c=outline[(i+1)%outline.count];if abs(cross(a,b,c))<0.000000001{outline.remove(at:i);changed=true;break}}}
  let area=outline.indices.reduce(CGFloat.zero){sum,i in let a=outline[i],b=outline[(i+1)%outline.count];return sum+a.x*b.y-b.x*a.y},direction:CGFloat=area>0 ? 1:-1
  var remaining=Array(outline.indices),indices=[Int32]()
  while remaining.count>3{
   var found=false
   for i in remaining.indices{let a=remaining[(i+remaining.count-1)%remaining.count],b=remaining[i],c=remaining[(i+1)%remaining.count],pa=outline[a],pb=outline[b],pc=outline[c]
    guard cross(pa,pb,pc)*direction>0.000000001 else{continue}
    let occupied=remaining.contains{j in guard j != a && j != b && j != c else{return false};let q=outline[j];return cross(pa,pb,q)*direction >= -0.000000001 && cross(pb,pc,q)*direction >= -0.000000001 && cross(pc,pa,q)*direction >= -0.000000001}
    if !occupied{indices += direction>0 ? [Int32(a),Int32(b),Int32(c)]:[Int32(a),Int32(c),Int32(b)];remaining.remove(at:i);found=true;break}
   }
   precondition(found,"GBA front outline could not be triangulated")
  }
  if remaining.count==3{indices += direction>0 ? remaining.map(Int32.init):remaining.reversed().map(Int32.init)}
  if face<0{for i in stride(from:0,to:indices.count,by:3){indices.swapAt(i+1,i+2)}}
  let points=outline.map{SCNVector3($0.x*scale,$0.y*scale,face>0 ? 0.04:0)},normals=outline.map{_ in SCNVector3(0,0,face)}
  let geometry=SCNGeometry(sources:[SCNGeometrySource(vertices:points),SCNGeometrySource(normals:normals)],elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)]);geometry.materials=[mat(tint,0.55)];geometry.firstMaterial?.isDoubleSided=true;return SCNNode(geometry:geometry)
 }
 // GBA perimeter is a rolled, tapering surface, rather than a uniform extrusion.
 func gbaRim(_ contour:NSBezierPath,_ tint:Int)->SCNNode {
  let previousFlatness=NSBezierPath.defaultFlatness;NSBezierPath.defaultFlatness=0.002;let flat=gbaShoulderRelief(contour).flattened;NSBezierPath.defaultFlatness=previousFlatness
  var outline=[CGPoint](),tmp=[NSPoint](repeating:.zero,count:3)
  for i in 0..<flat.elementCount{let type=flat.element(at:i,associatedPoints:&tmp);if type == .moveTo || type == .lineTo{if outline.last != tmp[0]{outline.append(tmp[0])}}}
  if outline.first==outline.last{outline.removeLast()}
  let rings:[(CGFloat,CGFloat)]=[(0.970,-0.028),(0.995,-0.070),(1.000,-0.135),(0.999,-0.240),(0.983,-0.435),(0.950,-0.590),(0.940,-0.640)]
  let count=outline.count;var positions=[SCNVector3](),normals=[SCNVector3](),indices=[Int32]()
  for (ring,(scale,z)) in rings.enumerated(){for p in outline{positions.append(SCNVector3(p.x*scale,p.y*scale,z));let nz:CGFloat=ring==0 ? 0.85:ring==rings.count-1 ? -0.85:0,dx=p.x/3.2,dy=p.y/1.65,length=sqrt(dx*dx+dy*dy+nz*nz);normals.append(SCNVector3(dx/length,dy/length,nz/length))}}
  for row in 0..<rings.count-1{for col in 0..<count{let next=(col+1)%count,p=outline[col],q=outline[next]
   // The cartridge throat opens through the upper rear rolled edge.
   if row>=3 && abs((p.x+q.x)/2)<1.36 && min(p.y,q.y)>1.28{continue}
   let a=Int32(row*count+col),b=Int32(row*count+next),c=Int32((row+1)*count+col),d=Int32((row+1)*count+next);indices += [a,c,b,b,c,d]
  }}
  let geometry=SCNGeometry(sources:[SCNGeometrySource(vertices:positions),SCNGeometrySource(normals:normals)],elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)]);geometry.materials=[mat(tint,0.44)];geometry.firstMaterial?.isDoubleSided=true;let n=SCNNode(geometry:geometry);n.name="gba-rolled-sidewall";return n
 }
 // An open notch is part of the contour, never an overlapping reversed rectangle.
 func notchedProfile(_ kind:Handheld,_ half:CGFloat,_ pocket:CGFloat,_ body:CGRect)->NSBezierPath{
  let p=NSBezierPath(),top=body.height/200,bottom=top-pocket
  p.move(to:NSPoint(x:-2.98,y:kind == .gba ? 1.58:top))
  p.line(to:NSPoint(x:-half,y:kind == .gba ? 1.70:top));p.line(to:NSPoint(x:-half,y:bottom));p.line(to:NSPoint(x:half,y:bottom));p.line(to:NSPoint(x:half,y:kind == .gba ? 1.70:top));p.line(to:NSPoint(x:2.98,y:kind == .gba ? 1.58:top))
  if kind == .gba{p.curve(to:NSPoint(x:3.10,y:-1.25),controlPoint1:NSPoint(x:3.35,y:1),controlPoint2:NSPoint(x:3.35,y:-0.7));p.curve(to:NSPoint(x:-3.1,y:-1.25),controlPoint1:NSPoint(x:2,y:-2.05),controlPoint2:NSPoint(x:-2,y:-2.05));p.curve(to:NSPoint(x:-2.98,y:1.58),controlPoint1:NSPoint(x:-3.35,y:-0.7),controlPoint2:NSPoint(x:-3.35,y:1))}
  else{p.curve(to:NSPoint(x:3.2,y:top-0.2),controlPoint1:NSPoint(x:3.12,y:top),controlPoint2:NSPoint(x:3.2,y:top-0.08));p.line(to:NSPoint(x:3.2,y:-top+0.2));p.curve(to:NSPoint(x:3,y:-top),controlPoint1:NSPoint(x:3.2,y:-top+0.08),controlPoint2:NSPoint(x:3.12,y:-top));p.line(to:NSPoint(x:-3,y:-top));p.curve(to:NSPoint(x:-3.2,y:-top+0.2),controlPoint1:NSPoint(x:-3.12,y:-top),controlPoint2:NSPoint(x:-3.2,y:-top+0.08));p.line(to:NSPoint(x:-3.2,y:top-0.2));p.curve(to:NSPoint(x:-2.98,y:top),controlPoint1:NSPoint(x:-3.2,y:top-0.08),controlPoint2:NSPoint(x:-3.12,y:top))}
  p.close();return p
 }
 func save(_ root:SCNNode,_ name:String){let scene=SCNScene();scene.rootNode.addChildNode(root);precondition(scene.write(to:destination.appendingPathComponent(name+".scn"),options:nil,delegate:writer,progressHandler:nil),"Cannot bake "+name)}
 for kind in Handheld.allCases {for theme in 0..<(kind == .gba ? 4:3) {
  v.handheld=kind;v.theme=theme;v.lid=1;v.phase = .playing;v.running=false;v.choosing=false;v.pose=0;v.held=[]
  let data=metadata[kind.rawValue] as! [String:Any],sizeArray=data["size"] as! [Double],size=CGSize(width:sizeArray[0],height:sizeArray[1]),crop=data["crop"] as! [Double],stem=kind.rawValue+"-"+String(theme),root=SCNNode();root.name="device"
  func point(_ x:CGFloat,_ y:CGFloat,_ z:CGFloat=0)->SCNVector3{SCNVector3((x-size.width/2)/100,(size.height/2-y)/100,z)}
  if kind == .gbc {
   let rig=GBCMachineMesh(theme:theme,owner:v);rig.root.position=SCNVector3(0,0.05,-0.55);root.addChildNode(rig.root)
  }else {
   let dual=kind == .nds || kind == .n3ds
   let shellTint=kind == .gba ? [0xFFC02C,0x2363AD,0x6026A0,0xEFF2F1][theme]:kind == .psp ? [0xCFD4DC,0x303238,0x123442][theme]:v.shellHi
   let bodyRect:CGRect=dual ? CGRect(x:40,y:360,width:640,height:330):kind == .gba ? CGRect(x:40,y:25,width:640,height:330):CGRect(x:30,y:30,width:660,height:290)
   let path:NSBezierPath
   if kind == .gba {
    path=NSBezierPath();path.move(to:NSPoint(x:-2.98,y:1.36));path.curve(to:NSPoint(x:-1.36,y:1.58),controlPoint1:NSPoint(x:-2.82,y:1.66),controlPoint2:NSPoint(x:-1.88,y:1.62));path.curve(to:NSPoint(x:1.36,y:1.58),controlPoint1:NSPoint(x:-0.60,y:1.77),controlPoint2:NSPoint(x:0.60,y:1.77));path.curve(to:NSPoint(x:2.98,y:1.36),controlPoint1:NSPoint(x:1.88,y:1.62),controlPoint2:NSPoint(x:2.82,y:1.66));path.curve(to:NSPoint(x:3.10,y:-1.20),controlPoint1:NSPoint(x:3.24,y:0.95),controlPoint2:NSPoint(x:3.27,y:-0.76));path.curve(to:NSPoint(x:2.66,y:-1.48),controlPoint1:NSPoint(x:3.06,y:-1.37),controlPoint2:NSPoint(x:2.91,y:-1.44));path.curve(to:NSPoint(x:-2.66,y:-1.48),controlPoint1:NSPoint(x:1.02,y:-1.75),controlPoint2:NSPoint(x:-1.02,y:-1.75));path.curve(to:NSPoint(x:-3.10,y:-1.20),controlPoint1:NSPoint(x:-2.91,y:-1.44),controlPoint2:NSPoint(x:-3.06,y:-1.37));path.curve(to:NSPoint(x:-2.98,y:1.36),controlPoint1:NSPoint(x:-3.27,y:-0.76),controlPoint2:NSPoint(x:-3.24,y:0.95));path.close()
   }else{path=NSBezierPath(roundedRect:CGRect(x:-bodyRect.width/200,y:-bodyRect.height/200,width:bodyRect.width/100,height:bodyRect.height/100),xRadius:kind == .psp ? 1.20:0.20,yRadius:kind == .psp ? 1.20:0.20)}
   let depth:CGFloat=kind == .psp ? 0.58:kind == .gba ? 0.92:0.50
   let frontDepth:CGFloat=kind == .psp ? 0.18:kind == .gba ? 0.08:0.16
   let frontProfile=path.copy() as! NSBezierPath
   if kind == .psp {frontProfile.append(NSBezierPath(roundedRect:CGRect(x:-2.06,y:-1.04,width:4.12,height:2.42),xRadius:0.08,yRadius:0.08).reversed)}
   let housing=kind == .gba ? gbaFront(frontProfile,shellTint):shape(frontProfile,frontDepth,shellTint);housing.name="front-shell";housing.position=point(bodyRect.midX,bodyRect.midY,-frontDepth/2);if dual,let g=housing.geometry as? SCNShape{g.chamferRadius=0.045};root.addChildNode(housing)
   if kind == .gba{let rim=gbaRim(path,shellTint);rim.position=point(bodyRect.midX,bodyRect.midY,0);root.addChildNode(rim)}
   if kind != .psp,let slot=mediaSlots[kind.rawValue]{
    let pocketHeight=slot.cardWidth*slot.ratio/100+0.16,rearProfile=notchedProfile(kind,slot.width/200/(kind == .gba ? 0.94:1),kind == .gba ? pocketHeight/0.94:pocketHeight,bodyRect)
    let relievedRear:NSBezierPath
    if kind == .gba{let t=AffineTransform(scale:0.94);rearProfile.transform(using:t);relievedRear=gbaShoulderRelief(rearProfile);let inverse=AffineTransform(scale:1/0.94);relievedRear.transform(using:inverse)}else{relievedRear=rearProfile}
    let rear=kind == .gba ? gbaFront(relievedRear,shellTint,relief:false,scale:1,face:-1):shape(relievedRear,depth-frontDepth,shellTint);rear.name="rear-shell-with-cartridge-pocket";if dual,let g=rear.geometry as? SCNShape{g.chamferRadius=0.075};rear.position=point(bodyRect.midX,bodyRect.midY,kind == .gba ? -0.635:-frontDepth-(depth-frontDepth)/2);if kind == .gba{rear.scale=SCNVector3(0.94,0.94,1)};root.addChildNode(rear)
    if kind == .gba {
     // Only the centre battery cradle has additional rear depth.
     let bulge=box(2.75,1.17,0.24,shellTint,0.11);bulge.name="gba-battery-cradle";bulge.position=point(360,278,-0.725);root.addChildNode(bulge)
     for x:CGFloat in [225,495]{let cheek=box(0.06,1.24,0.56,shellTint,0.02);cheek.name="gba-cartridge-pocket-wall";cheek.position=point(x,113,-0.43);root.addChildNode(cheek)}
    }
    let floor=box(slot.width/100-0.02,0.045,kind == .gba ? 0.50:depth-frontDepth-0.03,0x16221C,0.004);floor.position=point(360,bodyRect.minY+pocketHeight*100,kind == .gba ? -0.40:-frontDepth-(depth-frontDepth)/2);root.addChildNode(floor)
   }
   if dual {
    let rearCover=shape(path,0.035,shellTint);rearCover.name="rear-pocket-cover";rearCover.position=point(bodyRect.midX,bodyRect.midY,-depth+0.0175);root.addChildNode(rearCover)
    let door=box(kind == .n3ds ? 5.8:2.85,kind == .n3ds ? 2.65:1.75,0.018,shellTint,0.07);door.name="battery-door";door.position=point(kind == .n3ds ? 360:450,kind == .n3ds ? 526:542,-depth-0.012);root.addChildNode(door)
    if kind == .n3ds && theme==1 {
     let backInk=NSImage(size:CGSize(width:640,height:330));backInk.lockFocusFlipped(true);color(0x8597A4,0.75).setFill()
     for (section,x,y,scale) in [("moon",CGFloat(32),CGFloat(65),CGFloat(0.24)),("lion",CGFloat(478),CGFloat(65),CGFloat(0.24))]{let path=v.sunMoonSilkPath(section);let transform=AffineTransform(m11:scale,m12:0,m21:0,m22:scale,tX:x,tY:y);path.transform(using:transform);path.fill()}
     v.centered("Nintendo 3DS",320,177,15,color(0x778B99),.bold);v.centered("Nintendo",320,208,9,color(0x778B99),.medium);backInk.unlockFocus()
     let print=plane(backInk,CGSize(width:640,height:330));print.name="sunmoon-rear-silk";print.position=point(360,525,-depth-0.030);print.eulerAngles.y = .pi;print.geometry?.firstMaterial?.roughness.contents=0.78;root.addChildNode(print)
    }
    for x:CGFloat in [80,640]{for y:CGFloat in [399,648]{let screw=SCNCylinder(radius:0.035,height:0.008);screw.materials=[mat(0x2B3233,0.55,0.35)];let n=SCNNode(geometry:screw);n.eulerAngles.x = .pi/2;n.name="legacy-rear-fastener";n.position=point(x,y,-depth-0.025);root.addChildNode(n)}}
   }
   if kind == .psp {
    let rearProfile=path.copy() as! NSBezierPath
    rearProfile.append(NSBezierPath(roundedRect:CGRect(x:-1.42,y:-1.18,width:2.84,height:2.56),xRadius:0.045,yRadius:0.045).reversed)
    let rearShell=shape(rearProfile,depth-frontDepth,shellTint);rearShell.name="rear-shell-with-bay";rearShell.position=point(bodyRect.midX,bodyRect.midY,-(depth+frontDepth)/2);root.addChildNode(rearShell)
   }
   // The side seam is a real narrow extrusion between separately molded halves.
   var seamPath=path.copy() as! NSBezierPath;if kind != .psp,let slot=mediaSlots[kind.rawValue]{seamPath=notchedProfile(kind,slot.width/200,slot.cardWidth*slot.ratio/100+0.16,bodyRect)};let innerSeam=seamPath.copy() as! NSBezierPath;let inset=AffineTransform(scale:0.985);innerSeam.transform(using:inset);seamPath.append(innerSeam.reversed);let seam=shape(seamPath,kind == .psp ? 0.10:0.018,kind == .psp ? (theme==1 ? 0xB59B54:0xB3BEC6):0x111916);if kind == .psp{seam.name="psp-metal-perimeter";seam.geometry?.firstMaterial?.metalness.contents=0.92;seam.geometry?.firstMaterial?.roughness.contents=0.24};seam.scale=SCNVector3(1.004,1.004,1);seam.position=housing.position;if kind == .psp{seam.position.z = -depth/2};root.addChildNode(seam)
   let surface=plane(kind == .psp ? v.pspSpatialInk(back:false):image(stem+(dual ? "-base-body":"-body")),size);surface.position.z=0.006;if kind != .gba{root.addChildNode(surface)}
   if kind == .gba {
    housing.geometry?.firstMaterial?.transparency=1;housing.geometry?.firstMaterial?.roughness.contents=0.60;surface.opacity=0
    // Electronics are the shared live assembly, not a legacy repeated grid.

   }
   let controls=MechanicalControlStage(owner:v).exportedControls();controls.name="controls";controls.scale=SCNVector3(0.01,0.01,0.01);controls.position.y=(CGFloat(crop[1])+size.height/2-410)/100;root.addChildNode(controls)
   if dual {
    let lid=SCNNode();lid.name="lid";lid.position=point(360,360,0.17);root.addChildNode(lid)
    let lidBody=box(6.4,3.3,0.17,shellTint,0.07);lidBody.position=SCNVector3(0,1.65,-0.085);lid.addChildNode(lidBody)
    let inner=plane(image(stem+"-inner"),CGSize(width:640,height:330));inner.position=SCNVector3(0,1.65,0.005);lid.addChildNode(inner)
    let outer=plane(image(stem+"-outer"),CGSize(width:640,height:330));outer.geometry?.firstMaterial?.roughness.contents=kind == .n3ds && theme==0 ? 0.29:0.38;outer.geometry?.firstMaterial?.metalness.contents=kind == .n3ds && theme==0 ? 0.35:0.02;outer.position=SCNVector3(0,1.65,-0.174);outer.eulerAngles=SCNVector3(0,CGFloat.pi,CGFloat.pi);lid.addChildNode(outer)
    // A physical, cylindrical hinge ties both shells together.
    let hinge=SCNCylinder(radius:0.105,height:6.2);hinge.materials=[mat(kind == .n3ds ? 0x272D2E:shellTint,0.28)];let barrel=SCNNode(geometry:hinge);barrel.eulerAngles.z = .pi/2;barrel.name="hinge-barrel";barrel.position=point(360,360,0.10);root.addChildNode(barrel)
   }
   if kind == .psp {
    let originalBack:NSImage?=v.pspSpatialInk(back:true)
    let opened=NSImage(size:size);opened.lockFocusFlipped(true);originalBack?.draw(in:CGRect(origin:.zero,size:size));NSGraphicsContext.current?.cgContext.clear(CGRect(x:219,y:30,width:282,height:268));opened.unlockFocus()
    let cavity=box(2.80,2.54,0.015,0x131A1B,0.04);cavity.position=point(360,164,-depth+0.305);root.addChildNode(cavity)
    for side:CGFloat in [-1,1] {
     var vertices:[SCNVector3]=[],normals:[SCNVector3]=[],uv:[CGPoint]=[],indices:[Int32]=[]
     let columns=16,rows=28
     for row in 0...rows{let v=CGFloat(row)/CGFloat(rows),y = -1.43+v*2.86,dy=max(0,abs(y)-0.25),edge=2.10+sqrt(max(0,1.20*1.20-dy*dy))
      for column in 0...columns{let u=CGFloat(column)/CGFloat(columns),x=side*(1.43+(edge-1.43)*u),bulge=0.055*sin(u * .pi)*sin(v * .pi);vertices.append(SCNVector3(x,y,-depth-0.008-bulge));let nx = -0.055 * .pi*cos(u * .pi)*sin(v * .pi)/(side*(edge-1.43)),ny = -0.055 * .pi*sin(u * .pi)*cos(v * .pi)/2.86,length=sqrt(nx*nx+ny*ny+1);normals.append(SCNVector3(nx/length,ny/length,-1/length));uv.append(CGPoint(x:(3.60-x)/7.20,y:(1.75-y)/3.50))}
     }
     for row in 0..<rows{for col in 0..<columns{let i=Int32(row*(columns+1)+col),n=Int32(columns+1);indices += side<0 ? [i,i+n,i+1,i+1,i+n,i+n+1]:[i,i+1,i+n,i+1,i+n+1,i+n]}}
     for i in stride(from:0,to:indices.count,by:3){indices.swapAt(i+1,i+2)}
     let element=SCNGeometryElement(indices:indices,primitiveType:.triangles),geometry=SCNGeometry(sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:normals),SCNGeometrySource(textureCoordinates:uv)],elements:[element]);geometry.materials=[mat(shellTint,0.27)];geometry.firstMaterial?.isDoubleSided=true
     let grip=SCNNode(geometry:geometry);grip.name="curved-rear-grip";root.addChildNode(grip)
     let art=geometry.copy() as! SCNGeometry,ink=mat(0xFFFFFF,theme==0 ? 0.46:0.68);ink.diffuse.contents=opened;ink.writesToDepthBuffer=false;ink.isDoubleSided=true;ink.shaderModifiers=[.fragment:"#pragma body\nif (_surface.diffuse.a < 0.04) discard_fragment();\n_output.color.a = _surface.diffuse.a;"];if theme==0,let originalBack{ink.normal.contents=spatialEtchNormal(originalBack);ink.normal.intensity=0.25};art.materials=[ink];let print=SCNNode(geometry:art);print.name="curved-grip-print";print.position.z = -0.002;root.addChildNode(print)
    }
    if theme==1 {for (right,bottom) in [(false,false),(true,false),(false,true),(true,true)] {
      let trim=NSBezierPath();trim.move(to:NSPoint(x:0,y:0));trim.curve(to:NSPoint(x:0.65,y:0.26),controlPoint1:NSPoint(x:0.12,y:0.22),controlPoint2:NSPoint(x:0.40,y:0.26));trim.line(to:NSPoint(x:0.79,y:0.26));trim.line(to:NSPoint(x:0.69,y:0.17));trim.curve(to:NSPoint(x:0.10,y:0),controlPoint1:NSPoint(x:0.36,y:0.18),controlPoint2:NSPoint(x:0.23,y:0.10));trim.close()
      let inlay=shape(trim,0.016,0xBAA15D);inlay.name="rear-corner-inlay";inlay.geometry?.firstMaterial?.metalness.contents=0.65;inlay.geometry?.firstMaterial?.roughness.contents=0.32;inlay.position=point(right ? 615:105,bottom ? 274:76,-depth-0.019);inlay.scale=SCNVector3(right ? -1:1,bottom ? 1:-1,1);root.addChildNode(inlay)
    }}
    let hatch=SCNNode();hatch.name="hatch";hatch.position=point(360,298,-depth-0.018);hatch.eulerAngles.y = .pi;root.addChildNode(hatch)
    let door=box(2.8,2.66,0.025,shellTint,0.06);door.name="umd-door-shell";door.position.y=1.33;hatch.addChildNode(door)
    if let original=originalBack,let cg=original.cgImage(forProposedRect:nil,context:nil,hints:nil){let scale=CGFloat(cg.width)/size.width;if let crop=cg.cropping(to:CGRect(x:219*scale,y:30*scale,width:282*scale,height:268*scale)){let ink=plane(NSImage(cgImage:crop,size:CGSize(width:282,height:268)),CGSize(width:282,height:268));ink.name="umd-door-print";ink.position=SCNVector3(0,1.33,0.020);if theme==0{ink.geometry?.firstMaterial?.normal.contents=spatialEtchNormal(NSImage(cgImage:crop,size:CGSize(width:282,height:268)));ink.geometry?.firstMaterial?.normal.intensity=0.5};hatch.addChildNode(ink)}}
    // The circular UMD ring is metal geometry, not a painted circle.
    let ringPath=NSBezierPath(ovalIn:CGRect(x:-1.03,y:-1.03,width:2.06,height:2.06));ringPath.append(NSBezierPath(ovalIn:CGRect(x:-0.83,y:-0.83,width:1.66,height:1.66)).reversed)
    ringPath.flatness=0.002
    let ring=SCNShape(path:ringPath,extrusionDepth:0.014);ring.chamferRadius=0.006
    let metal=mat(theme==1 ? 0xC5AE63:0xB9C6D0,0.22,0.96)
    let brush=NSImage(size:CGSize(width:512,height:512));brush.lockFocusFlipped(true);color(0x808080).setFill();CGRect(x:0,y:0,width:512,height:512).fill()
    for i in 0..<640{let radius=CGFloat(i)*0.42;let line=NSBezierPath(ovalIn:CGRect(x:256-radius,y:256-radius,width:radius*2,height:radius*2));NSColor(white:0.5+sin(CGFloat(i)*1.73)*0.055,alpha:1).setStroke();line.lineWidth=0.28;line.stroke()};brush.unlockFocus()
    metal.normal.contents=spatialEtchNormal(brush);metal.normal.intensity=0.20;ring.materials=[metal]
    let n=SCNNode(geometry:ring);n.name="umd-brushed-metal-annulus";n.position=SCNVector3(0,1.33,0.035);hatch.addChildNode(n)
   }
   let screens=data["screens"] as! [[Double]]
   for (i,values) in screens.enumerated(){let r=CGRect(x:values[0],y:values[1],width:values[2],height:values[3]),bezel=box((r.width*(kind == .psp ? 1.18:1)+8)/100,(r.height*(kind == .psp ? 1.18:1)+8)/100,0.038,0x08100F,0.025);bezel.name=kind == .psp ? "psp-lcd-surround":"lcd-surround";bezel.position=point(r.midX,r.midY,0.017)
    let screen=SCNPlane(width:r.width/100,height:r.height/100),m=mat(0x17231F);m.name="screen:\(i)";m.lightingModel = .constant;m.diffuse.magnificationFilter = .nearest;screen.materials=[m];let panel=SCNNode(geometry:screen);panel.name="screen:\(i)";panel.position=point(r.midX,r.midY,0.043)
    if dual && i==0 {let lid=root.childNode(withName:"lid",recursively:true)!;for node in [bezel,panel]{node.position.y -= lid.position.y;lid.addChildNode(node)}}else{root.addChildNode(bezel);root.addChildNode(panel)}
   }
   if let values=data["stick"] as? [Double]{let r=CGRect(x:values[0],y:values[1],width:values[2],height:values[3]),g=SCNCylinder(radius:r.width/200,height:0.065);g.materials=[mat(kind == .psp && theme==0 ? 0xBFC6CB:0x687372,0.48)];let n=SCNNode(geometry:g);n.name="stick";n.eulerAngles.x = .pi/2;n.position=point(r.midX,r.midY,kind == .psp ? 0.045:0.055);root.addChildNode(n)
    if kind == .psp {let socket=SCNCylinder(radius:r.width/200+0.055,height:0.04);socket.materials=[mat(0x12191C,0.48)];let base=SCNNode(geometry:socket);base.eulerAngles.x = .pi/2;base.position=point(r.midX,r.midY,0.025);root.addChildNode(base)
     let dome=SCNSphere(radius:r.width/200-0.01);dome.segmentCount=40;dome.materials=g.materials;let cap=SCNNode(geometry:dome);cap.scale=SCNVector3(1,0.10,1);cap.position.y=0.028;n.addChildNode(cap)
     for radius:CGFloat in [0.17,0.20,0.23]{let ring=SCNTorus(ringRadius:radius,pipeRadius:0.009);ring.materials=[mat(0x6D7778,0.5)];let rim=SCNNode(geometry:ring);rim.position.y=0.048;n.addChildNode(rim)}
    }
    for i in -3...3{let bar=box(r.width/100*0.70,0.004,0.008,0x8E9997,0.001);bar.position=SCNVector3(0,kind == .psp ? 0.076:0.035,CGFloat(i)*0.045);n.addChildNode(bar)}}
  }
  // Slot is on the rear/top seam with a recessed throat, not a new front-face stripe.
  if kind != .psp,let slot=mediaSlots[kind.rawValue] {
   let slotNode=SCNNode();slotNode.name="slot";slotNode.position=point(slot.x+slot.width/2,slot.y,kind == .gbc ? -0.80:kind == .gba ? -0.54:-0.32);root.addChildNode(slotNode)
   for x in [-slot.width/200,slot.width/200]{let rail=box(0.035,0.22,0.16,0x1C2925,0.008);rail.position=SCNVector3(x,-0.08,0);slotNode.addChildNode(rail)}
   // Two lips leave a genuine empty throat matching the cartridge thickness.
   for z:CGFloat in [(kind == .gba || kind == .gbc) ? -0.205:-0.10,(kind == .gba || kind == .gbc) ? 0.205:0.17]{let lip=box(slot.width/100,0.025,0.025,0x111916,0.004);lip.position.z=z;slotNode.addChildNode(lip)}
  }
  save(root,stem)
 }}
 for kind in Handheld.allCases {
  let root=SCNNode();root.name="media"
  if kind == .psp {
   // UMD: a protected 60mm rotor inside its moulded 65mm carrier.
   // The shell stays fixed in the guide cage; only umd-rotor spins on the spindle.
   let rotor=SCNNode();rotor.name="umd-rotor";root.addChildNode(rotor)
   let disc=NSBezierPath(ovalIn:CGRect(x:-1.19,y:-1.19,width:2.38,height:2.38));disc.append(NSBezierPath(ovalIn:CGRect(x:-0.13,y:-0.13,width:0.26,height:0.26)).reversed)
   let substrate=shape(disc,0.024,0xBBC5CB);substrate.name="disc-substrate";substrate.geometry?.firstMaterial?.metalness.contents=0.75;substrate.geometry?.firstMaterial?.roughness.contents=0.20;rotor.addChildNode(substrate)
   let readSide=shape(disc,0.001,0xC4CDD3);readSide.name="disc-read-surface";readSide.position.z = -0.013;let readMaterial=readSide.geometry!.firstMaterial!;readMaterial.name="disc-read-surface";readMaterial.metalness.contents=0.92;readMaterial.roughness.contents=0.16;rotor.addChildNode(readSide)
   let face=plane(nil,CGSize(width:236,height:236));face.name="disc-label";face.position.z=0.014;face.geometry?.firstMaterial?.name="cover"
   let mask=NSImage(size:CGSize(width:512,height:512));mask.lockFocus();NSColor.white.setFill();let ring=NSBezierPath(ovalIn:CGRect(x:0,y:0,width:512,height:512));ring.append(NSBezierPath(ovalIn:CGRect(x:208,y:208,width:96,height:96)).reversed);ring.fill();mask.unlockFocus();face.geometry?.firstMaterial?.transparent.contents=mask;face.geometry?.firstMaterial?.transparencyMode = .aOne;rotor.addChildNode(face)
   let hubPath=NSBezierPath(ovalIn:CGRect(x:-0.24,y:-0.24,width:0.48,height:0.48));hubPath.append(NSBezierPath(ovalIn:CGRect(x:-0.13,y:-0.13,width:0.26,height:0.26)).reversed);let hub=shape(hubPath,0.026,0xD1D7D6);hub.name="disc-hub";hub.geometry?.firstMaterial?.metalness.contents=0.65;rotor.addChildNode(hub)
   let profile=NSBezierPath();profile.move(to:CGPoint(x:-1.30,y:-0.74));profile.line(to:CGPoint(x:-1.30,y:0));profile.curve(to:CGPoint(x:1.30,y:0),controlPoint1:CGPoint(x:-1.30,y:1.74),controlPoint2:CGPoint(x:1.30,y:1.74));profile.line(to:CGPoint(x:1.30,y:-0.74));profile.curve(to:CGPoint(x:1.12,y:-1.26),controlPoint1:CGPoint(x:1.30,y:-1.08),controlPoint2:CGPoint(x:1.22,y:-1.22));profile.curve(to:CGPoint(x:-1.12,y:-1.26),controlPoint1:CGPoint(x:0.55,y:-1.39),controlPoint2:CGPoint(x:-0.55,y:-1.39));profile.curve(to:CGPoint(x:-1.30,y:-0.74),controlPoint1:CGPoint(x:-1.22,y:-1.22),controlPoint2:CGPoint(x:-1.30,y:-1.08));profile.close()
   let frame=profile.copy() as! NSBezierPath;frame.append(NSBezierPath(ovalIn:CGRect(x:-1.21,y:-1.21,width:2.42,height:2.42)).reversed)
   let carrier=shape(frame,0.17,0xE6E5D9);carrier.name="umd-protective-shell";carrier.geometry?.firstMaterial?.roughness.contents=0.40;root.addChildNode(carrier)
   // Rear polycarbonate has a hub opening and a radial optical access window.
   let rear=profile.copy() as! NSBezierPath;rear.append(NSBezierPath(ovalIn:CGRect(x:-0.25,y:-0.25,width:0.50,height:0.50)).reversed);rear.append(NSBezierPath(roundedRect:CGRect(x:0.34,y:-0.18,width:0.92,height:0.36),xRadius:0.04,yRadius:0.04).reversed)
   let rearPlate=shape(rear,0.016,0xCED6DC);rearPlate.name="umd-rear-polycarbonate";rearPlate.opacity=0.22;rearPlate.position.z = -0.068;rearPlate.geometry?.firstMaterial?.roughness.contents=0.16;rearPlate.geometry?.firstMaterial?.writesToDepthBuffer=false;root.addChildNode(rearPlate)
   let front=SCNShape(path:NSBezierPath(ovalIn:CGRect(x:-1.21,y:-1.21,width:2.42,height:2.42)),extrusionDepth:0.008);front.materials=[mat(0xFFFFFF,0.13)];let window=SCNNode(geometry:front);window.name="umd-clear-label-window";window.opacity=0.035;window.position.z=0.063;window.geometry?.firstMaterial?.writesToDepthBuffer=false;root.addChildNode(window)
   let stamp=NSImage(size:CGSize(width:240,height:80));stamp.lockFocusFlipped(true);v.centered("UMD",120,9,24,color(0x536383),.medium);v.centered("UNIVERSAL MEDIA DISC",120,40,8,color(0x647078),.medium);stamp.unlockFocus();let stampNode=plane(stamp,CGSize(width:82,height:27));stampNode.name="umd-carrier-identity";stampNode.position=SCNVector3(0,-1.14,0.088);root.addChildNode(stampNode)
  }else{
   let slot=mediaSlots[kind.rawValue]!,w=slot.cardWidth/100,h=w*slot.ratio
   let depth:CGFloat=kind == .gba ? w*(8.0/60.0):kind == .gbc ? w*(8.0/57.0):0.13
   let isGB=kind == .gba || kind == .gbc,mouth:CGFloat=isGB ? h*0.13:0
   let path=NSBezierPath(roundedRect:CGRect(x:-w/2,y:-h/2+mouth,width:w,height:h-mouth),xRadius:0.05,yRadius:0.05)
   if kind == .n3ds {path.removeAllPoints();path.move(to:NSPoint(x:-w/2,y:h/2));for q in [NSPoint(x:w/2+0.10,y:h/2),NSPoint(x:w/2+0.10,y:h/2-0.20),NSPoint(x:w/2,y:h/2-0.20),NSPoint(x:w/2,y:-h/2),NSPoint(x:-w/2,y:-h/2)]{path.line(to:q)};path.close()}
   // Two molded halves and a perimeter side wall, leaving an open connector mouth.
   for z in [-depth/2+0.022,depth/2-0.022]{let faceProfile=isGB ? NSBezierPath(roundedRect:CGRect(x:-w/2,y:-h/2,width:w,height:h),xRadius:0.05,yRadius:0.05):(path.copy() as! NSBezierPath)
    if !isGB && z<0 {faceProfile.append(NSBezierPath(roundedRect:CGRect(x:-w*0.425,y:-h*0.48,width:w*0.85,height:h*0.32),xRadius:0.012,yRadius:0.012).reversed)}
    let shell=shape(faceProfile,0.044,kind == .n3ds ? 0xE0E2D8:0x5A7565);shell.name=z>0 ? "cartridge-front":"cartridge-rear";shell.geometry?.firstMaterial?.name="media-shell";shell.position.z=z;root.addChildNode(shell)}
   let side=path.copy() as! NSBezierPath,inside=NSBezierPath(roundedRect:CGRect(x:-w/2+0.055,y:-h/2+mouth+0.035,width:w-0.11,height:h-mouth-0.09),xRadius:0.035,yRadius:0.035);side.append(inside.reversed);let wall=shape(side,depth-0.06,0x5A7565);wall.name="cartridge-sidewalls";wall.geometry?.firstMaterial?.name="media-shell";root.addChildNode(wall)
   if isGB {for x in [-w/2+0.045,w/2-0.045]{let guide=box(0.09,mouth,depth,0x5A7565,0.015);guide.name="cartridge-connector-guard";guide.geometry?.firstMaterial?.name="media-shell";guide.position=SCNVector3(x,-h/2+mouth/2,0);root.addChildNode(guide)}}
   let pcb=box(w*0.89,h*0.85,0.035,0x345D42,0.008);pcb.name="cartridge-pcb";pcb.position.y = -h*0.045;root.addChildNode(pcb)
   let chip=box(w*0.30,h*0.24,0.045,0x202525,0.008);chip.name="cartridge-rom";chip.position=SCNVector3(-w*0.12,h*0.02,0.04);root.addChildNode(chip)
   // One real 32-contact PCB edge inside the open bottom mouth, not gold paint
   // on the sticker, and never a second runtime row of floating contacts.
   let pins=isGB ? 32:kind == .nds ? 17:19
   for i in 0..<pins{
    let width=w*0.80/CGFloat(pins)*0.60,height=h*(isGB ? 0.10:0.26)
    let pin:SCNNode
    do {let copper=SCNPlane(width:width,height:height);let material=mat(0xC6AF6B,0.30,0.75);material.isDoubleSided=false;copper.materials=[material];pin=SCNNode(geometry:copper);pin.eulerAngles.y = .pi}
    pin.name="edge-contact:"+String(i+1);pin.position=SCNVector3(-w*0.40+(CGFloat(i)+0.5)*w*0.80/CGFloat(pins),-h*(isGB ? 0.43:0.32),isGB ? -0.0195:-depth/2+0.018);root.addChildNode(pin)
   }
   if !isGB {for i in 0...pins{let rib=box(w*0.80/CGFloat(pins)*0.16,h*0.30,0.025,0x5A7565,0.004);rib.name="cartridge-contact-divider";rib.geometry?.firstMaterial?.name="media-shell";rib.position=SCNVector3(-w*0.40+CGFloat(i)*w*0.80/CGFloat(pins),-h*0.32,-depth/2-0.002);root.addChildNode(rib)}}

   let label=shape(NSBezierPath(roundedRect:CGRect(x:-w*0.39,y:-h*0.31,width:w*0.78,height:h*0.63),xRadius:0.025,yRadius:0.025),0.004,0xC3D0C6);label.position.z=depth/2+0.002;root.addChildNode(label)
   let face=plane(nil,CGSize(width:w*78,height:h*63));face.geometry?.firstMaterial?.name="cover";face.position=SCNVector3(0,h*0.005,depth/2+0.006);root.addChildNode(face)
   if isGB {
    // Rear carries only molded identity/regulatory text and a recessed screw;
    // the game artwork remains exclusively on the front label.
    let identity=NSImage(size:CGSize(width:520,height:220));identity.lockFocusFlipped(true);v.centered(kind == .gba ? "Nintendo GAME BOY ADVANCE":"Nintendo GAME BOY",260,40,24,color(0xB8C5BA),.bold);v.centered("GAME PAK",260,112,13,color(0xA6B4A8),.medium);identity.unlockFocus()
    let rearMark=plane(identity,CGSize(width:w*76,height:h*42));rearMark.name="cartridge-rear-identity";rearMark.position=SCNVector3(0,h*0.10,-depth/2-0.006);rearMark.eulerAngles.y = .pi;root.addChildNode(rearMark)
    let screw=SCNCylinder(radius:w*0.028,height:0.008);screw.materials=[mat(0x68736A,0.55,0.4)];let n=SCNNode(geometry:screw);n.name="cartridge-rear-screw";n.eulerAngles.x = .pi/2;n.position=SCNVector3(0,-h*0.22,-depth/2-0.006);root.addChildNode(n)
   }
   if kind == .gba {for x in [-w*0.45,w*0.45]{let tab=box(w*0.10,h*0.12,depth,0x5A7565,0.015);tab.geometry?.firstMaterial?.name="media-shell";tab.position=SCNVector3(x,h*0.40,0);root.addChildNode(tab)}}
   if kind == .gbc {for y in [h*0.35,h*0.40,h*0.45]{let rib=box(w*0.70,0.015,0.015,0x5A7565,0.003);rib.geometry?.firstMaterial?.name="media-shell";rib.position=SCNVector3(0,y,depth/2+0.005);root.addChildNode(rib)}}
   let brand=kind == .gba ? "GAME BOY ADVANCE":kind == .gbc ? "GAME BOY":kind == .n3ds ? "NINTENDO 3DS":"NINTENDO DS"
   let ink=NSImage(size:CGSize(width:360,height:56));ink.lockFocusFlipped(true);v.centered(brand,180,12,20,color(0xD6E0D1),.bold);ink.unlockFocus();let brandNode=plane(ink,CGSize(width:w*82,height:h*10));brandNode.position=SCNVector3(0,h*0.40,depth/2+0.018);root.addChildNode(brandNode)
  }
  save(root,"media-"+kind.rawValue)
 }
 let finishes:[String:Any]=["psp-0":"fine-grey-etch-normal","psp-1":"matte-ink-metal-inlays","psp-2":"silk-on-gloss","3ds-0":"gold-foil-print","default":"silk-print","basis":"Visual treatment inferred from the supplied references; not a claim about the original manufacturing process."]
 try! JSONSerialization.data(withJSONObject:finishes,options:[.prettyPrinted,.sortedKeys]).write(to:destination.appendingPathComponent("finishes.json"))
 try! JSONSerialization.data(withJSONObject:metadata,options:[.prettyPrinted,.sortedKeys]).write(to:destination.appendingPathComponent("geometry.json"))
}
bakeSpatialModels()
