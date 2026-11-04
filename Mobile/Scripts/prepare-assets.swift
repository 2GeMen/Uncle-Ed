import AppKit
let root=URL(fileURLWithPath:CommandLine.arguments[1])
for kind in ["nds","gba","gbc","psp","3ds"] {
 let size=CGSize(width:180,height:48)
 let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:360,pixelsHigh:96,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 rep.size=size;NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
 let variant=["nds","gba","gbc"].contains(kind) ? "-dark":""
 let ink=NSColor(srgbRed:0.86,green:0.89,blue:0.84,alpha:1)
 if let logo=NSImage(contentsOf:root.appendingPathComponent("../Assets/Logos/\(kind)\(variant).svg")){let ratio=min(180/logo.size.width,44/logo.size.height);logo.draw(in:CGRect(x:(180-logo.size.width*ratio)/2,y:(48-logo.size.height*ratio)/2,width:logo.size.width*ratio,height:logo.size.height*ratio))}
 else{let word=kind=="psp" ? "PSP":"NINTENDO 3DS",font=NSFont.systemFont(ofSize:kind=="psp" ? 36:19,weight:kind=="psp" ? .ultraLight:.bold);let attr:[NSAttributedString.Key:Any]=[.font:font,.foregroundColor:ink];let extent=(word as NSString).size(withAttributes:attr);(word as NSString).draw(at:CGPoint(x:(180-extent.width)/2,y:(48-extent.height)/2),withAttributes:attr)}
 NSGraphicsContext.restoreGraphicsState()
 var minX=360,minY=96,maxX=0,maxY=0
 for y in 0..<96 {for x in 0..<360 {if (rep.colorAt(x:x,y:y)?.alphaComponent ?? 0)>0.01 {minX=min(minX,x);maxX=max(maxX,x);minY=min(minY,y);maxY=max(maxY,y)}}}
 let output:NSBitmapImageRep
 if maxX>=minX,maxY>=minY,let cg=rep.cgImage?.cropping(to:CGRect(x:minX,y:minY,width:maxX-minX+1,height:maxY-minY+1)){output=NSBitmapImageRep(cgImage:cg)}else{output=rep}
 let dest=root.appendingPathComponent("Resources/Images.xcassets/\(kind)-mark.imageset");try! FileManager.default.createDirectory(at:dest,withIntermediateDirectories:true);try! output.representation(using:.png,properties:[:])!.write(to:dest.appendingPathComponent("mark.png"));try! Data("{\"images\":[{\"idiom\":\"universal\",\"filename\":\"mark.png\",\"scale\":\"2x\"}],\"info\":{\"version\":1,\"author\":\"xcode\"}}".utf8).write(to:dest.appendingPathComponent("Contents.json"))
}
