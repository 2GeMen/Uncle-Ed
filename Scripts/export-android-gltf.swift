// SPDX-License-Identifier: GPL-3.0-or-later
// Compile together with SpatialMachine.swift and PickerMotion.swift in an app
// bundle whose Assets directory supplies the PRIVATE model pack. No artwork is
// downloaded by this exporter. GLB output is private unless separately approved.
import Cocoa
import CryptoKit
import SceneKit
import SceneKit.ModelIO
import ModelIO
import simd

final class GLBWriter {
 var bytes=Data(),views=[[String:Any]](),accessors=[[String:Any]](),meshes=[[String:Any]](),nodes=[[String:Any]](),materials=[[String:Any]](),images=[[String:Any]](),textures=[[String:Any]]()
 var materialCache=[String:Int](),textureCache=[String:Int]()
 func align(){while bytes.count%4 != 0{bytes.append(0)}}
 func blob(_ data:Data,_ target:Int?=nil)->Int{align();let i=views.count;var v:[String:Any]=["buffer":0,"byteOffset":bytes.count,"byteLength":data.count];if let target{v["target"]=target};views.append(v);bytes.append(data);return i}
 func floats(_ a:[Float],_ type:String,_ count:Int,_ bounds:Bool=false)->Int {
  let data=a.withUnsafeBufferPointer{Data(buffer:$0)},view=blob(data,34962),i=accessors.count;var x:[String:Any]=["bufferView":view,"componentType":5126,"type":type,"count":count]
  if bounds {x["min"]=(0..<3).map{k in stride(from:k,to:a.count,by:3).map{a[$0]}.min() ?? 0};x["max"]=(0..<3).map{k in stride(from:k,to:a.count,by:3).map{a[$0]}.max() ?? 0}}
  accessors.append(x);return i
 }
 func source(_ s:SCNGeometrySource)->[Float] {s.data.withUnsafeBytes{ raw in
  var out=[Float]();out.reserveCapacity(s.vectorCount*s.componentsPerVector)
  for i in 0..<s.vectorCount {for k in 0..<s.componentsPerVector {let at=s.dataOffset+i*s.dataStride+k*s.bytesPerComponent
   if s.usesFloatComponents {if s.bytesPerComponent==4{out.append(raw.loadUnaligned(fromByteOffset:at,as:Float.self))}else{out.append(Float(raw.loadUnaligned(fromByteOffset:at,as:Double.self)))}}
   else if s.bytesPerComponent==1{out.append(Float(raw[at])/255)}else{out.append(Float(raw.loadUnaligned(fromByteOffset:at,as:UInt16.self))/65535)}
  }};return out
 }}
 func image(_ contents:Any?)->Int? {
  let cg:CGImage
  if let value=contents,CFGetTypeID(value as CFTypeRef)==CGImage.typeID{cg=(value as! CGImage)}
  else if let n=contents as? NSImage,let c=n.cgImage(forProposedRect:nil,context:nil,hints:nil){cg=c}
  else if let data=contents as? Data,let n=NSImage(data:data),let c=n.cgImage(forProposedRect:nil,context:nil,hints:nil){cg=c}
  else if let u=contents as? URL,let n=NSImage(contentsOf:u),let c=n.cgImage(forProposedRect:nil,context:nil,hints:nil){cg=c}
  else{return nil}
  guard let data=NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:]) else{return nil}
  let digest=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined();if let cached=textureCache[digest]{return cached}
  let view=blob(data),idx=textures.count;images.append(["bufferView":view,"mimeType":"image/png"]);textures.append(["source":images.count-1]);textureCache[digest]=idx;return idx
 }
 func color(_ value:Any?)->[Float]{
  let c:NSColor?
  if let n=value as? NSColor{c=n.usingColorSpace(.sRGB)}else if let v=value,CFGetTypeID(v as CFTypeRef)==CGColor.typeID{c=NSColor(cgColor:v as! CGColor)?.usingColorSpace(.sRGB)}else{c=nil}
  if let c{func linear(_ x:CGFloat)->Float{let x=Float(x);return x<=0.04045 ? x/12.92:pow((x+0.055)/1.055,2.4)};return [linear(c.redComponent),linear(c.greenComponent),linear(c.blueComponent),Float(c.alphaComponent)]};return [1,1,1,1]
 }
 func material(_ m:SCNMaterial,_ opacity:CGFloat)->Int {
  let key="\(ObjectIdentifier(m))-\(opacity)";if let i=materialCache[key]{return i}
  let i=materials.count;var rgba=color(m.diffuse.contents);rgba[3] *= Float(m.transparency*opacity)
  var pbr:[String:Any]=["baseColorFactor":rgba,"metallicFactor":(m.metalness.contents as? NSNumber)?.doubleValue ?? 0,"roughnessFactor":(m.roughness.contents as? NSNumber)?.doubleValue ?? 0.60]
  if let t=image(m.diffuse.contents){pbr["baseColorTexture"]=["index":t]}
  let screen=m.name?.hasPrefix("screen:") == true
  if screen,pbr["baseColorTexture"]==nil{
   let c=CGContext(data:nil,width:2,height:2,bitsPerComponent:8,bytesPerRow:8,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!;c.setFillColor(CGColor(gray:0.04,alpha:1));c.fill(CGRect(x:0,y:0,width:2,height:2));pbr["baseColorTexture"]=["index":image(c.makeImage()!)!];pbr["baseColorFactor"]=[1,1,1,1]
  }
  var entry:[String:Any]=["name":m.name ?? "material-\(i)","pbrMetallicRoughness":pbr,"doubleSided":m.isDoubleSided]
  let textured=pbr["baseColorTexture"] != nil
  if rgba[3]<0.995 || textured {entry["alphaMode"]="BLEND"}
  if screen || m.name=="cover" || m.lightingModel == .constant{entry["extensions"]=["KHR_materials_unlit":[:]];if screen{entry["alphaMode"]="OPAQUE"};if m.name=="cover"{entry["alphaMode"]="MASK";entry["alphaCutoff"]=0.5}}
  if let n=image(m.normal.contents){entry["normalTexture"]=["index":n,"scale":m.normal.intensity]}
  materials.append(entry);materialCache[key]=i;return i
 }
 // SceneKit uses GPU-generated primitive surfaces on recent macOS versions.
 // Its public geometry source may be only a proxy cube, even for a cylinder.
 // Generate actual surfaces, including bevels, rather than exporting that proxy.
 func explicitGeometry(_ original:SCNGeometry)->SCNGeometry {
  var points=[SIMD3<Float>](),normals=[SIMD3<Float>](),uvs=[CGPoint](),indices=[Int32]()
  func vertex(_ p:SIMD3<Float>,_ n:SIMD3<Float>,_ u:Float,_ v:Float){points.append(p);normals.append(n);uvs.append(CGPoint(x:CGFloat(u),y:CGFloat(v)))}
  func triangle(_ a:Int,_ b:Int,_ c:Int){let cross=simd_cross(points[b]-points[a],points[c]-points[a]);if simd_length_squared(cross)<1e-20{return};let n=normals[a]+normals[b]+normals[c];indices += simd_dot(cross,n)>=0 ? [Int32(a),Int32(b),Int32(c)]:[Int32(a),Int32(c),Int32(b)]}
  func lathe(_ profile:[SIMD4<Float>],_ segments:Int){
   for (row,p) in profile.enumerated(){for column in 0...segments{let theta=Float(column)*2*Float.pi/Float(segments),c=cos(theta),s=sin(theta);vertex(SIMD3(p.x*c,p.y,p.x*s),SIMD3(p.z*c,p.w,p.z*s),Float(column)/Float(segments),Float(row)/Float(max(1,profile.count-1)))}}
   for row in 0..<(profile.count-1){for column in 0..<segments{let a=row*(segments+1)+column,b=a+1,c=a+segments+1,d=c+1;triangle(a,b,c);triangle(b,d,c)}}
  }
  if let shape=original as? SCNShape,(shape.sources(for:.vertex).first?.vectorCount ?? 0)==0,shape.chamferRadius==0,let path=shape.path {
   // SCNShape can have no CPU mesh on macOS. Preserve its actual single-contour
   // outline instead of silently exporting an empty node (e.g. GBA LCD glass).
   var contours=[[CGPoint]](),contour=[CGPoint]();var current=CGPoint.zero
   func finish(){if contour.count>1,hypot(contour[0].x-contour.last!.x,contour[0].y-contour.last!.y)<1e-8{contour.removeLast()};if contour.count>=3{contours.append(contour)};contour=[]}
   func midpoint(_ a:CGPoint,_ b:CGPoint)->CGPoint{CGPoint(x:(a.x+b.x)/2,y:(a.y+b.y)/2)}
   func curve(_ a:CGPoint,_ b:CGPoint,_ c:CGPoint,_ d:CGPoint,_ depth:Int=0){
    let dx=d.x-a.x,dy=d.y-a.y,len=max(hypot(dx,dy),0.0000001)
    let error=max(abs(dx*(b.y-a.y)-dy*(b.x-a.x)),abs(dx*(c.y-a.y)-dy*(c.x-a.x)))/len
    if error<=0.002 || depth>=12{contour.append(d);return}
    let ab=midpoint(a,b),bc=midpoint(b,c),cd=midpoint(c,d),abc=midpoint(ab,bc),bcd=midpoint(bc,cd),m=midpoint(abc,bcd)
    curve(a,ab,abc,m,depth+1);curve(m,bcd,cd,d,depth+1)
   }
   for i in 0..<path.elementCount {var p=[NSPoint](repeating:.zero,count:3);let type=path.element(at:i,associatedPoints:&p)
    switch type {
     case .moveTo:finish();current=p[0];contour.append(current)
     case .lineTo:current=p[0];contour.append(current)
     case .curveTo:curve(current,p[0],p[1],p[2]);current=p[2]
     case .closePath:finish()
     default:preconditionFailure("Unsupported shape path element")
    }
   };finish()
   guard contours.count==1 else{return original};contour=contours[0]
   func cross(_ a:CGPoint,_ b:CGPoint,_ c:CGPoint)->CGFloat{(b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)}
   let area=contour.indices.reduce(CGFloat(0)){s,i in let a=contour[i],b=contour[(i+1)%contour.count];return s+a.x*b.y-b.x*a.y}
   if area<0{contour.reverse()};precondition(contour.count>=3)
   var remaining=Array(contour.indices),caps=[(Int,Int,Int)]()
   while remaining.count>3 {var clipped=false
    for i in remaining.indices {let a=remaining[(i+remaining.count-1)%remaining.count],b=remaining[i],c=remaining[(i+1)%remaining.count]
     let turn=cross(contour[a],contour[b],contour[c]);if abs(turn)<1e-10{remaining.remove(at:i);clipped=true;break};if turn<0{continue}
     let inside=remaining.contains{p in p != a && p != b && p != c && cross(contour[a],contour[b],contour[p])>=(-1e-10) && cross(contour[b],contour[c],contour[p])>=(-1e-10) && cross(contour[c],contour[a],contour[p])>=(-1e-10)}
     if !inside{caps.append((a,b,c));remaining.remove(at:i);clipped=true;break}
    };precondition(clipped,"Unable to triangulate shape contour")
   }
   caps.append((remaining[0],remaining[1],remaining[2]))
   let half=Float(shape.extrusionDepth/2),bounds=path.bounds
   for z in [half,-half] {let base=points.count;let normal=SIMD3<Float>(0,0,z==half ? 1:-1)
    for p in contour{vertex(SIMD3(Float(p.x),Float(p.y),z),normal,Float((p.x-bounds.minX)/max(bounds.width,0.000001)),Float((p.y-bounds.minY)/max(bounds.height,0.000001)))}
    for (a,b,c) in caps{triangle(base+a,base+b,base+c)}
   }
   for i in contour.indices{let a=contour[i],b=contour[(i+1)%contour.count],base=points.count;let normal=simd_normalize(SIMD3<Float>(Float(b.y-a.y),Float(a.x-b.x),0))
    vertex(SIMD3(Float(a.x),Float(a.y),half),normal,0,1);vertex(SIMD3(Float(b.x),Float(b.y),half),normal,1,1);vertex(SIMD3(Float(a.x),Float(a.y),-half),normal,0,0);vertex(SIMD3(Float(b.x),Float(b.y),-half),normal,1,0);triangle(base,base+1,base+2);triangle(base+1,base+3,base+2)
   }
  }else if let box=original as? SCNBox {
   let half=SIMD3<Float>(Float(box.width/2),Float(box.height/2),Float(box.length/2)),r=min(Float(box.chamferRadius),min(half.x,min(half.y,half.z))),core=half-SIMD3<Float>(repeating:r)
   func axisValues(_ half:Float)->[Float]{if r<=0{return [-half,half]};let n=max(3,min(16,box.chamferSegmentCount));var v=[Float]();for i in 0...n{v.append(-half+r*Float(i)/Float(n))};for i in 0...n{v.append(half-r+r*Float(i)/Float(n))};return v}
   for axis in 0..<3 {for sign in [Float(-1),Float(1)]{let u=(axis+1)%3,v=(axis+2)%3,us=axisValues(half[u]),vs=axisValues(half[v]),base=points.count
    for (j,y) in vs.enumerated(){for (i,x) in us.enumerated(){var p=SIMD3<Float>(repeating:0);p[axis]=sign*half[axis];p[u]=x;p[v]=y;var n=SIMD3<Float>(repeating:0);n[axis]=sign
     if r>0{let q=simd_clamp(p,-core,core),delta=p-q;if simd_length_squared(delta)>0{n=simd_normalize(delta);p=q+n*r}}
     vertex(p,n,Float(i)/Float(us.count-1),Float(j)/Float(vs.count-1))}}
    for j in 0..<(vs.count-1){for i in 0..<(us.count-1){let a=base+j*us.count+i,b=a+1,c=a+us.count,d=c+1;triangle(a,b,c);triangle(b,d,c)}}
   }}
  }else if let c=original as? SCNCylinder {
   let r=Float(c.radius),h=Float(c.height/2);lathe([SIMD4(0,h,0,1),SIMD4(r,h,0,1),SIMD4(r,h,1,0),SIMD4(r,-h,1,0),SIMD4(r,-h,0,-1),SIMD4(0,-h,0,-1)],max(24,c.radialSegmentCount))
  }else if let s=original as? SCNSphere {
   let r=Float(s.radius),rings=max(12,s.segmentCount/2);let p=(0...rings).map{i->SIMD4<Float> in let a = -Float.pi/2+Float(i)*Float.pi/Float(rings);return SIMD4(r*cos(a),r*sin(a),cos(a),sin(a))};lathe(p,max(24,s.segmentCount))
  }else if let t=original as? SCNTorus {
   let p=(0...t.pipeSegmentCount).map{i->SIMD4<Float> in let a=Float(i)*2*Float.pi/Float(t.pipeSegmentCount);return SIMD4(Float(t.ringRadius)+Float(t.pipeRadius)*cos(a),Float(t.pipeRadius)*sin(a),cos(a),sin(a))};lathe(p,max(32,t.ringSegmentCount))
  }else if let t=original as? SCNTube {
   let a=Float(t.innerRadius),b=Float(t.outerRadius),h=Float(t.height/2);lathe([SIMD4(a,-h,-1,0),SIMD4(a,h,-1,0),SIMD4(a,h,0,1),SIMD4(b,h,0,1),SIMD4(b,h,1,0),SIMD4(b,-h,1,0),SIMD4(b,-h,0,-1),SIMD4(a,-h,0,-1)],max(32,t.radialSegmentCount))
  }else {return original}
  let vs=points.map{SCNVector3($0.x,$0.y,$0.z)},ns=normals.map{SCNVector3($0.x,$0.y,$0.z)}
  let data=indices.withUnsafeBufferPointer{Data(buffer:$0)}
  return SCNGeometry(sources:[SCNGeometrySource(vertices:vs),SCNGeometrySource(normals:ns),SCNGeometrySource(textureCoordinates:uvs)],elements:[SCNGeometryElement(data:data,primitiveType:.triangles,primitiveCount:indices.count/3,bytesPerIndex:4)])
 }

 // Batch the original CPU primitives before SceneKit turns the cap into a
 // GPU-only flattened geometry. All cap parts intentionally share one resin.
 func mergedPrimitiveTree(_ root:SCNNode)->SCNGeometry {
  var vertices=[SCNVector3](),normals=[SCNVector3](),uvs=[CGPoint](),indices=[UInt32]()
  let inverse=root.simdWorldTransform.inverse
  func visit(_ n:SCNNode){
   if let original=n.geometry {
    let g=explicitGeometry(original);let vs=source(g.sources(for:.vertex)[0]);let ns=source(g.sources(for:.normal)[0]);let world=inverse*n.simdWorldTransform
    let normal=simd_float3x3(columns:(SIMD3(world.columns.0.x,world.columns.0.y,world.columns.0.z),SIMD3(world.columns.1.x,world.columns.1.y,world.columns.1.z),SIMD3(world.columns.2.x,world.columns.2.y,world.columns.2.z))).inverse.transpose
    let base=UInt32(vertices.count)
    for i in stride(from:0,to:vs.count,by:3){let p=world*SIMD4(vs[i],vs[i+1],vs[i+2],1),v=simd_normalize(normal*SIMD3(ns[i],ns[i+1],ns[i+2]));vertices.append(SCNVector3(p.x,p.y,p.z));normals.append(SCNVector3(v.x,v.y,v.z));uvs.append(.zero)}
    for e in g.elements {precondition(e.primitiveType == .triangles);e.data.withUnsafeBytes{b in for i in 0..<(e.data.count/e.bytesPerIndex){let at=i*e.bytesPerIndex;let index:UInt32=e.bytesPerIndex==2 ? UInt32(b.loadUnaligned(fromByteOffset:at,as:UInt16.self)):e.bytesPerIndex==1 ? UInt32(b[at]):b.loadUnaligned(fromByteOffset:at,as:UInt32.self);indices.append(base+index)}}}
   };n.childNodes.forEach{visit($0)}
  };visit(root)
  let data=indices.withUnsafeBufferPointer{Data(buffer:$0)}
  let g=SCNGeometry(sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:normals),SCNGeometrySource(textureCoordinates:uvs)],elements:[SCNGeometryElement(data:data,primitiveType:.triangles,primitiveCount:indices.count/3,bytesPerIndex:4)])
  g.materials=root.geometry!.materials;return g
 }
 func node(_ n:SCNNode,_ opacity:CGFloat=1)->Int? {
  if n.isHidden || n.opacity<0.001{return nil}
  let idx=nodes.count;nodes.append([:]);let t=n.simdTransform
  var entry:[String:Any]=["name":n.name ?? "node-\(idx)","matrix":[t.columns.0,t.columns.1,t.columns.2,t.columns.3].flatMap{[$0.x,$0.y,$0.z,$0.w]}]
  if let sourceGeometry=n.geometry {
   let original=n.name=="stick-textured-cap" && !n.childNodes.isEmpty ? mergedPrimitiveTree(n):sourceGeometry
   if n.name=="stick-textured-cap"{precondition((original.sources(for:.vertex).first?.vectorCount ?? 0)>0,"PSP cap missing: compile with UNCLEED_ANDROID_EXPORT")}
   var g=explicitGeometry(original)
   if g.sources(for:.vertex).isEmpty{g=SCNGeometry(mdlMesh:MDLMesh(scnGeometry:original))}
   if let vertex=g.sources(for:.vertex).first,vertex.vectorCount>0 {
    // SceneKit's parametric primitives expose a unit mesh: width/height/depth
    // live in an internal geometry transform, not the node transform.
    var positions=source(vertex)
    let bounds=original.boundingBox
    let low=[Float(bounds.min.x),Float(bounds.min.y),Float(bounds.min.z)],high=[Float(bounds.max.x),Float(bounds.max.y),Float(bounds.max.z)]
    var intrinsic=[Float](repeating:1,count:3)
    for axis in 0..<3 {
     let values=stride(from:axis,to:positions.count,by:3).map{positions[$0]};let lo=values.min() ?? 0,hi=values.max() ?? 0
     if hi-lo>0.0000001 {intrinsic[axis]=(high[axis]-low[axis])/(hi-lo);for k in stride(from:axis,to:positions.count,by:3){positions[k]=(positions[k]-lo)*intrinsic[axis]+low[axis]}}
    }
    var attributes:[String:Int]=["POSITION":floats(positions,"VEC3",vertex.vectorCount,true)]
    if let normal=g.sources(for:.normal).first{
     var ns=source(normal)
     for k in stride(from:0,to:ns.count,by:3){var v=SIMD3<Float>(ns[k]/max(abs(intrinsic[0]),0.000001),ns[k+1]/max(abs(intrinsic[1]),0.000001),ns[k+2]/max(abs(intrinsic[2]),0.000001));if simd_length_squared(v)>0{v=simd_normalize(v)};ns[k]=v.x;ns[k+1]=v.y;ns[k+2]=v.z}
     attributes["NORMAL"]=floats(ns,"VEC3",normal.vectorCount)
    }
    if let uv=g.sources(for:.texcoord).first{let values=source(uv);attributes["TEXCOORD_0"]=floats(values,"VEC2",uv.vectorCount)}
    var primitives=[[String:Any]]()
    for (j,e) in g.elements.enumerated(){
     let raw:[UInt32]=e.data.withUnsafeBytes{ b in (0..<(e.data.count/e.bytesPerIndex)).map{i in let p=i*e.bytesPerIndex;switch e.bytesPerIndex{case 1:return UInt32(b[p]);case 2:return UInt32(b.loadUnaligned(fromByteOffset:p,as:UInt16.self));default:return b.loadUnaligned(fromByteOffset:p,as:UInt32.self)}}}
     var indices=raw,mode=4
     if e.primitiveType == .triangleStrip{mode=5}else if e.primitiveType == .line{mode=1}else if e.primitiveType == .point{mode=0}
     else if e.primitiveType == .polygon {indices=[];let sizes=Array(raw.prefix(e.primitiveCount));var at=e.primitiveCount;for size in sizes{let count=Int(size);if count>=3{for k in 1..<(count-1){indices += [raw[at],raw[at+k],raw[at+k+1]]}};at+=count}}
     if indices.isEmpty{continue};let view=blob(indices.withUnsafeBufferPointer{Data(buffer:$0)},34963),access=accessors.count;accessors.append(["bufferView":view,"componentType":5125,"type":"SCALAR","count":indices.count]);let m=original.materials.isEmpty ? SCNMaterial():original.materials[min(j,original.materials.count-1)];primitives.append(["attributes":attributes,"indices":access,"mode":mode,"material":material(m,opacity*n.opacity)])
    }
    if !primitives.isEmpty{entry["mesh"]=meshes.count;meshes.append(["primitives":primitives])}
   }
  }
  let children=(n.name=="stick-textured-cap" ? []:n.childNodes).compactMap{node($0,opacity*n.opacity)};if !children.isEmpty{entry["children"]=children};nodes[idx]=entry;return idx
 }
 func write(_ root:SCNNode,_ url:URL)throws {
  var low=SIMD3<Float>(repeating:Float.greatestFiniteMagnitude),high = -low
  func solids(_ n:SCNNode){
   guard !n.isHidden,n.opacity>0.001 else{return}
   if let g=n.geometry,!(g is SCNPlane){let b=g.boundingBox;for x in [b.min.x,b.max.x]{for y in [b.min.y,b.max.y]{for z in [b.min.z,b.max.z]{let p=n.convertPosition(SCNVector3(x,y,z),to:nil),v=SIMD3<Float>(Float(p.x),Float(p.y),Float(p.z));low=simd_min(low,v);high=simd_max(high,v)}}}}
   n.childNodes.forEach{solids($0)}
  };solids(root)
  let first=node(root)!;align();var json:[String:Any]=["asset":["version":"2.0","generator":"Uncle Ed shared SceneKit export"],"scene":0,"scenes":[["nodes":[first]]],"nodes":nodes,"meshes":meshes,"buffers":[["byteLength":bytes.count]],"bufferViews":views,"accessors":accessors,"materials":materials,"images":images,"textures":textures,"extensionsUsed":["KHR_materials_unlit"]]
  if low.x.isFinite && high.x.isFinite{json["extras"]=["uncleedPhysicalBounds":["min":[low.x,low.y,low.z],"max":[high.x,high.y,high.z]]]}
  if textures.isEmpty{json.removeValue(forKey:"textures");json.removeValue(forKey:"images")}
  var header=try JSONSerialization.data(withJSONObject:json,options:[.sortedKeys,.withoutEscapingSlashes]);while header.count%4 != 0{header.append(0x20)}
  var file=Data();func u(_ n:UInt32){var x=n.littleEndian;file.append(Data(bytes:&x,count:4))}
  u(0x46546c67);u(2);u(UInt32(12+8+header.count+8+bytes.count));u(UInt32(header.count));u(0x4e4f534a);file.append(header);u(UInt32(bytes.count));u(0x004e4942);file.append(bytes);try file.write(to:url)
  print(url.lastPathComponent,"nodes",nodes.count,"meshes",meshes.count,"bytes",file.count);fflush(stdout)
 }
}
