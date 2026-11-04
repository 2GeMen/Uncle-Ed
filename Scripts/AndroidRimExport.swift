// SPDX-License-Identifier: GPL-3.0-or-later
// Offline export only. Reuses the existing iOS solid-silhouette renderer.
import Cocoa
import SceneKit
import CryptoKit
import simd

func exportAndroidRims(model:String,theme:Int,glb:URL,destination:URL)throws {
 let data=try Data(contentsOf:glb)
 let length=data.withUnsafeBytes{Int($0.loadUnaligned(fromByteOffset:12,as:UInt32.self).littleEndian)}
 let json=try JSONSerialization.jsonObject(with:data.subdata(in:20..<(20+length))) as! [String:Any]
 let nodes=json["nodes"] as! [[String:Any]],meshes=json["meshes"] as! [[String:Any]],accessors=json["accessors"] as! [[String:Any]]
 var low=SIMD3<Float>(repeating:Float.greatestFiniteMagnitude),high = -low
 func visit(_ index:Int,_ parent:simd_float4x4){
  let node=nodes[index],a=(node["matrix"] as! [NSNumber]).map{$0.floatValue}
  let local=simd_float4x4(columns:(SIMD4(a[0],a[1],a[2],a[3]),SIMD4(a[4],a[5],a[6],a[7]),SIMD4(a[8],a[9],a[10],a[11]),SIMD4(a[12],a[13],a[14],a[15])))
  let world=parent*local
  if let mesh=node["mesh"] as? Int {for primitive in meshes[mesh]["primitives"] as! [[String:Any]] {
   let attrs=primitive["attributes"] as! [String:Int],position=accessors[attrs["POSITION"]!]
   let lo=(position["min"] as! [NSNumber]).map{$0.floatValue},hi=(position["max"] as! [NSNumber]).map{$0.floatValue}
   for x in [lo[0],hi[0]]{for y in [lo[1],hi[1]]{for z in [lo[2],hi[2]]{let p=world*SIMD4(x,y,z,1);let v=SIMD3(p.x,p.y,p.z);low=simd_min(low,v);high=simd_max(high,v)}}}
  }}
  for child in node["children"] as? [Int] ?? []{visit(child,world)}
 }
 for root in ((json["scenes"] as! [[String:Any]])[0]["nodes"] as! [Int]){visit(root,matrix_identity_float4x4)}
 if let bounds=(json["extras"] as? [String:Any])?["uncleedPhysicalBounds"] as? [String:[NSNumber]],let a=bounds["min"],let b=bounds["max"]{low=SIMD3(a[0].floatValue,a[1].floatValue,a[2].floatValue);high=SIMD3(b[0].floatValue,b[1].floatValue,b[2].floatValue)}
 let centre=(low+high)/2,q=2/(high-low).max()
 guard let rig=SpatialMachine(model:model,theme:theme) else{throw CocoaError(.fileReadNoSuchFile)}
 rig.update(openness:model=="nds" || model=="3ds" ? 0:1,loading:0,held:[],frame:nil,operating:false)
 let group=SCNNode();group.addChildNode(rig.root);rig.root.simdPosition = -centre
 let count=16
 func pose(_ index:Int){let wave=sin(Float(index)*2*Float.pi/Float(count));group.eulerAngles=SCNVector3(0.06+0.055*wave,-0.16+0.18*wave,0)}
 var rimLow=SIMD3<Float>(repeating:Float.greatestFiniteMagnitude),rimHigh = -rimLow
 func solids(_ node:SCNNode){
  guard !node.isHidden,node.opacity>0.001 else{return}
  if let g=node.geometry,!(g is SCNPlane){let bounds=g.boundingBox
   for x in [bounds.min.x,bounds.max.x]{for y in [bounds.min.y,bounds.max.y]{for z in [bounds.min.z,bounds.max.z]{let p=node.convertPosition(SCNVector3(x,y,z),to:nil),v=SIMD3(Float(p.x),Float(p.y),Float(p.z));rimLow=simd_min(rimLow,v);rimHigh=simd_max(rimHigh,v)}}}
  }
  for child in node.childNodes{solids(child)}
 }
 for index in 0..<count{pose(index);solids(group)}
 try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
 var files=[String](),dimensions=[[Int]]()
 for index in 0..<count {try autoreleasepool {
  pose(index)
  guard let image=SpatialMachine.rimTexture(node:group,low:SCNVector3(rimLow.x,rimLow.y,rimLow.z),high:SCNVector3(rimHigh.x,rimHigh.y,rimHigh.z)),let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil),let png=NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:]) else{throw CocoaError(.fileWriteUnknown)}
  let name=String(format:"pose-%02d.png",index);try png.write(to:destination.appendingPathComponent(name));files.append(name);dimensions.append([cg.width,cg.height])
 }}
 let padding:Float=0.12
 let metadata:[String:Any]=["version":1,"model":model,"theme":theme,"sourceGLBSha256":SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined(),"normalizationScale":q,"periodSeconds":8.5,"bounds":[rimLow.x-padding,rimLow.y-padding,rimHigh.x+padding,rimHigh.y+padding],"frames":files,"pixelSizes":dimensions,"method":"shared iOS solid silhouette; planes excluded; constant union bounds; centred on glTF geometry","colour":[255,214,133]]
 try JSONSerialization.data(withJSONObject:metadata,options:[.sortedKeys,.prettyPrinted,.withoutEscapingSlashes]).write(to:destination.appendingPathComponent("rim.json"))
 print("Rim export",model,theme,"frames",count,"pixels",dimensions.first!,"scale",q)
}
