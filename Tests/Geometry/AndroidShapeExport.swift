// SPDX-License-Identifier: GPL-3.0-or-later
import Cocoa
import SceneKit

@main struct AndroidShapeExportCheck {
 static func main(){
  let writer=GLBWriter()
  for reversed in [false,true]{
   let path=NSBezierPath();var points=[CGPoint(x:0,y:0),CGPoint(x:2,y:0),CGPoint(x:2,y:2),CGPoint(x:1,y:1),CGPoint(x:0,y:2)];if reversed{points.reverse()}
   path.move(to:points[0]);points.dropFirst().forEach{path.line(to:$0)};path.close();path.move(to:.zero)
   let geometry=writer.explicitGeometry(SCNShape(path:path,extrusionDepth:0.1))
   let vertices=writer.source(geometry.sources(for:.vertex)[0]),normals=writer.source(geometry.sources(for:.normal)[0]);var area:Float=0
   for element in geometry.elements{element.data.withUnsafeBytes{bytes in
    for i in stride(from:0,to:bytes.count/4,by:3){let ids=(0..<3).map{Int(bytes.loadUnaligned(fromByteOffset:(i+$0)*4,as:Int32.self))}
     if ids.allSatisfy({normals[$0*3+2]>0.9}){let a=ids[0]*3,b=ids[1]*3,c=ids[2]*3;area+=((vertices[b]-vertices[a])*(vertices[c+1]-vertices[a+1])-(vertices[b+1]-vertices[a+1])*(vertices[c]-vertices[a]))/2}
    }
   }}
   precondition(abs(area-3)<0.0001,"Concave cap area or winding changed: \(area)")
  }
  let curve=NSBezierPath();curve.move(to:CGPoint(x:-1,y:0));curve.curve(to:CGPoint(x:1,y:0),controlPoint1:CGPoint(x:-1,y:1),controlPoint2:CGPoint(x:1,y:1));curve.line(to:CGPoint(x:1,y:-1));curve.line(to:CGPoint(x:-1,y:-1));curve.close()
  let geometry=writer.explicitGeometry(SCNShape(path:curve,extrusionDepth:0.028));precondition(geometry.sources(for:.vertex)[0].vectorCount>60,"Curve not subdivided")
  print("PASS: concave cap area, both windings, trailing empty subpath, adaptive curve tessellation")
 }
}
