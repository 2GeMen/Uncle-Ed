let exportRoot=URL(fileURLWithPath:CommandLine.arguments[1])
try! fm.createDirectory(at:exportRoot,withIntermediateDirectories:true)
let v=StudioView(frame:CGRect(x:0,y:0,width:720,height:780));v.timer?.invalidate();v.choosing=false;v.hoverLabel=nil
func export(_ name:String,_ area:CGRect,_ body:()->Void){
 let scale:CGFloat=3,w=Int(area.width*scale),h=Int(area.height*scale)
 let c=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 c.translateBy(x:0,y:CGFloat(h));c.scaleBy(x:scale,y:-scale);c.translateBy(x:-area.minX,y:-area.minY)
 NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:c,flipped:true);body();NSGraphicsContext.restoreGraphicsState()
 let rep=NSBitmapImageRep(cgImage:c.makeImage()!);try! rep.representation(using:.png,properties:[:])!.write(to:exportRoot.appendingPathComponent(name+".png"))
}
func jsonRect(_ r:CGRect)->[Double]{[r.minX,r.minY,r.width,r.height].map{Double($0)}}
var metadata:[String:Any]=[:]
for kind in Handheld.allCases {for theme in 0..<(kind == .gba ? 4:3) {
 v.handheld=kind;v.theme=theme;v.lid=1;v.phase = .playing;v.running=false;v.pose=0;v.held=[]
 let area:CGRect=kind == .gbc ? CGRect(x:170,y:90,width:380,height:620):kind == .gba ? CGRect(x:0,y:110,width:720,height:380):kind == .psp ? CGRect(x:0,y:70,width:720,height:350):CGRect(x:0,y:50,width:720,height:730)
 let stem=kind.rawValue+"-"+String(theme)
 export(stem+"-front",area){v.drawMachine()}
 v.exportBareKeys=true;v.exportSpatialSurface=true;export(stem+"-body",area){v.drawMachine()};v.exportBareKeys=false;v.exportSpatialSurface=false
 if kind == .nds || kind == .n3ds {
  // Core Image can fail without graphics-service access. Never publish a skin
  // with a missing lid, even if AppKit completed the rest of the PNG.
  let bytes=try! Data(contentsOf:exportRoot.appendingPathComponent(stem+"-front.png"))
  let bitmap=NSBitmapImageRep(data:bytes)!
  precondition((bitmap.colorAt(x:1080,y:360)?.alphaComponent ?? 0)>0.95,"Missing rendered upper face: "+stem)
 }

 if kind == .psp {v.phase = .library;export(stem+"-back",area){v.drawMachine()};v.exportSpatialSurface=true;export(stem+"-spatial-back",area){v.drawMachine()};v.exportSpatialSurface=false;v.phase = .inserting;v.stageStart=CACurrentMediaTime()-0.6;export(stem+"-door",area){v.drawMachine()};v.phase = .playing}
 if kind == .nds || kind == .n3ds {
  export(stem+"-inner",CGRect(x:0,y:0,width:640,height:330)){v.innerLid()}
  export(stem+"-outer",CGRect(x:0,y:0,width:640,height:330)){v.outerLid()}
  func baseBody(){NSGraphicsContext.saveGraphicsState();let t=NSAffineTransform();t.translateX(by:-240,yBy:0);t.concat();v.drawBase();v.gradient(CGRect(x:285,y:403,width:630,height:21),v.keyHi,kind == .n3ds ? 0x171B20:v.shellLo,10);for (name,id,r) in v.buttons where !v.exportBareKeys && (id==10 || id==11) {v.shoulderKey(r,right:id==11,tint:v.keyHi,name:name,down:false,hover:false)};NSGraphicsContext.restoreGraphicsState()}
  export(stem+"-base",area){baseBody()};v.exportBareKeys=true;export(stem+"-base-body",area){baseBody()};v.exportBareKeys=false
 }
 export(stem+"-preview",CGRect(x:0,y:0,width:210,height:132)){v.themeThumbnail(theme).draw(in:CGRect(x:0,y:0,width:210,height:132))}
 let controls=v.buttons+v.dpad
 var defs:[String:Any]=[:]
 for (_,id,world) in controls {
  let r=world.offsetBy(dx:-240,dy:0),local=r.offsetBy(dx:-area.minX,dy:-area.minY);defs[String(id)]=jsonRect(local)
 }
 let power=(kind == .nds ? v.powerRect : kind == .n3ds ? v.modernPowerRect.offsetBy(dx:240,dy:0):kind == .psp ? v.modernPowerRect.offsetBy(dx:240,dy:0):v.classicPowerRect).offsetBy(dx:-240-area.minX,dy:-area.minY)
 let screens:[CGRect]=kind == .nds ? [CGRect(x:200,y:124,width:320,height:240),CGRect(x:200,y:454,width:320,height:240)]:kind == .n3ds ? [CGRect(x:160,y:124,width:400,height:240),CGRect(x:200,y:454,width:320,height:240)]:kind == .gba ? [CGRect(x:211,y:183,width:298,height:199)]:kind == .gbc ? [CGRect(x:254,y:169,width:212,height:191)]:[CGRect(x:192,y:133,width:336,height:190.4)]
 var data:[String:Any]=["size":[Double(area.width),Double(area.height)],"controls":defs,"power":jsonRect(power),"screens":screens.map{jsonRect($0.offsetBy(dx:-area.minX,dy:-area.minY))},"crop":jsonRect(area)]
 if kind == .psp || kind == .n3ds {data["stick"]=jsonRect(v.modernStickRect.offsetBy(dx:-area.minX,dy:-area.minY))}
 metadata[kind.rawValue]=data
 }}
try! JSONSerialization.data(withJSONObject:metadata,options:[.prettyPrinted,.sortedKeys]).write(to:exportRoot.appendingPathComponent("geometry.json"))
if CommandLine.arguments.contains("--workflow") {
    var checks:[String:Bool]=[:]
    func key(_ code:UInt16){if let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:code){v.keyDown(with:event)}}
    for (index,kind) in Handheld.allCases.enumerated(){v.handheld=kind;v.choosing=true;v.pickerPage = .models;v.pickerIndex=index
        key(36);checks[kind.rawValue+"_themes"]=v.choosing && v.pickerPage == .themes
        export("mac-"+kind.rawValue+"-themes",CGRect(x:0,y:0,width:720,height:780)){v.drawHandheldPicker()}
        key(124);let expected=v.pickerIndex;key(36);checks[kind.rawValue+"_library"] = !v.choosing && v.theme==expected && v.phase == .library
    }
    v.choosing=true;v.showModelPicker();export("mac-models",CGRect(x:0,y:0,width:720,height:780)){v.drawHandheldPicker()}
    try! JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys]).write(to:exportRoot.appendingPathComponent("mac-workflow.json"))
    precondition(checks.values.allSatisfy{$0})
}
