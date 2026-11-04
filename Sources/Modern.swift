import Cocoa
import QuartzCore

extension StudioView {
  var pspY: CGFloat { mix(408, 100, smooth(lid)) }
  var modernStickRect: CGRect {
    handheld == .psp ? CGRect(x:88,y:pspY+174,width:45,height:45) : CGRect(x:92,y:baseY+60,width:48,height:48)
  }
  var modernPowerRect: CGRect {
    handheld == .psp ? CGRect(x:667,y:pspY+169,width:15,height:42) : CGRect(x:627,y:baseY+293,width:30,height:18)
  }
  var modernButtons: [(String,Int,CGRect)] {
    let defs: [(String,Int,CGRect)]
    if handheld == .psp {
      let y=pspY
      defs=[("△",9,CGRect(x:610,y:y+67,width:30,height:30)),("○",8,CGRect(x:641,y:y+98,width:30,height:30)),("×",0,CGRect(x:610,y:y+129,width:30,height:30)),("□",1,CGRect(x:579,y:y+98,width:30,height:30)),("SELECT",2,CGRect(x:558,y:y+255,width:35,height:14)),("START",3,CGRect(x:602,y:y+255,width:35,height:14)),("L",10,CGRect(x:75,y:y+16,width:75,height:16)),("R",11,CGRect(x:570,y:y+16,width:75,height:16))]
    } else {
      let y=baseY
      defs=[("X",9,CGRect(x:590,y:y+78,width:32,height:32)),("A",8,CGRect(x:624,y:y+111,width:32,height:32)),("B",0,CGRect(x:590,y:y+144,width:32,height:32)),("Y",1,CGRect(x:556,y:y+111,width:32,height:32)),("START",3,CGRect(x:576,y:y+226,width:65,height:19)),("SELECT",2,CGRect(x:576,y:y+258,width:65,height:19)),("L",10,CGRect(x:51,y:y-7,width:83,height:24)),("R",11,CGRect(x:586,y:y-7,width:83,height:24))]
    }
    return defs.map {($0.0,$0.1,$0.2.offsetBy(dx:240,dy:0))}
  }
  var modernDpad: [(String,Int,CGRect)] {
    let x:CGFloat=handheld == .psp ? 70 : 85
    let y:CGFloat=handheld == .psp ? pspY+76 : baseY+164
    let w:CGFloat=handheld == .psp ? 24 : 23
    return [("",4,CGRect(x:x+w,y:y,width:w,height:w)),("",5,CGRect(x:x+w,y:y+2*w,width:w,height:w)),("",6,CGRect(x:x,y:y+w,width:w,height:w)),("",7,CGRect(x:x+2*w,y:y+w,width:w,height:w))].map {($0.0,$0.1,$0.2.offsetBy(dx:240,dy:0))}
  }
  func analogKey(_ code: UInt16,_ down: Bool) -> Bool {
    // I/J/K/L retain the established face/shoulder keyboard mapping.
    let map: [UInt16:(Int,Int)] = [34:(1,-1),40:(1,1),38:(0,-1),37:(0,1)]
    guard let (axis,direction)=map[code] else { return false }
    if axis == 0 { stickX=down ? CGFloat(direction) : 0 } else { stickY=down ? CGFloat(direction) : 0 }
    emu_axis(0,Int32(axis),Int32(down ? direction*32767 : 0)); needsDisplay=true; return true
  }
  func updateStick(_ p: CGPoint) {
    let r=modernStickRect
    let dx=(p.x-r.midX)/(r.width/2),dy=(p.y-r.midY)/(r.height/2)
    let length=max(1,sqrt(dx*dx+dy*dy));stickX=dx/length;stickY=dy/length
    emu_axis(0,0,Int32(stickX*32767));emu_axis(0,1,Int32(stickY*32767));needsDisplay=true
  }
  func drawStick(_ r: CGRect,_ tint: Int) {
    fill(r.insetBy(dx:-5,dy:-5),color(0x080B0C,0.65),r.width/2+5)
    stroke(r.insetBy(dx:-3,dy:-3),color(0xA4A7A8,0.4),r.width/2+3,1)
    let cap=plasticKey(r.offsetBy(dx:stickX*7,dy:stickY*7),tint:tint,radius:r.width/2,down:analogDrag)
    if handheld == .psp { for dy in stride(from:CGFloat(7),to:r.height-6,by:4) { line([CGPoint(x:cap.minX+9,y:cap.minY+dy),CGPoint(x:cap.maxX-9,y:cap.minY+dy)],color(0x000000,0.13),0.7) } } else {stroke(cap.insetBy(dx:8,dy:8),color(0xFFFFFF,0.14),cap.width/2,0.8)}
  }
  func modernKeys() {
    for (name,id,world) in modernButtons {
      let r=world.offsetBy(dx:-240,dy:0)
      let tint=handheld == .psp ? (theme == 0 ? 0xCBCED4 : 0x35363B) : 0x383C40
      if id == 10 || id == 11 { shoulderKey(r,right:id == 11,tint:handheld == .psp && theme == 1 ? 0xB49B54 : tint,name:name,down:held.contains(id),hover:controlHovered(id));continue }
      let cap=plasticKey(r,tint:tint,radius:id == 2 || id == 3 ? 8 : r.width/2,down:held.contains(id),hover:controlHovered(id),separable:true)
      if !omitControlCaps { centered(name,cap.midX,cap.midY-(id == 2 || id == 3 ? 4 : 9),id == 2 || id == 3 ? 6 : 17,color(theme == 0 && handheld == .psp ? 0x74797E : 0xE5E6E8),.medium) }
    }
    let r=modernDpad[0].2.offsetBy(dx:-240,dy:0)
    if handheld == .psp {
      let tint=theme == 0 ? 0xCDD1D6 : 0x34383E
      fill(CGRect(x:r.minX-r.width-7,y:r.minY-7,width:r.width*3+14,height:r.width*3+14),keyColor(tint,-0.28),r.width*1.5+7)
      for (i,item) in modernDpad.enumerated() {
        let cap=plasticKey(item.2.offsetBy(dx:-240,dy:0),tint:tint,radius:6,down:held.contains(item.1),hover:controlHovered(item.1),separable:true)
        if !omitControlCaps { centered(["▵","▿","◃","▹"][i],cap.midX,cap.midY-8,14,color(theme == 0 ? 0x68717A : 0xC8CFD6),.medium) }
      }
    } else { plasticDpad(CGRect(x:r.minX-r.width,y:r.minY,width:r.width*3,height:r.width*3),tint:0x34383E) }
    drawStick(modernStickRect,handheld == .psp && theme == 0 ? 0xC1C5CA : 0x797E84)
  }
  func reference(_ name: String, crop: CGRect, in r: CGRect, blend:NSCompositingOperation = .sourceOver) {
    if modernImages[name] == nil { modernImages[name]=NSImage(contentsOf:bundledAssets.appendingPathComponent("Skins/Modern/"+name+".png")) }
    guard let original=modernImages[name],let cg=original.cgImage(forProposedRect:nil,context:nil,hints:nil) else {return}
    let region=CGRect(x:crop.minX*CGFloat(cg.width),y:crop.minY*CGFloat(cg.height),width:crop.width*CGFloat(cg.width),height:crop.height*CGFloat(cg.height)).integral
    guard let image=cg.cropping(to:region) else {return}
    NSImage(cgImage:image,size:r.size).draw(in:r,from:.zero,operation:blend,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high.rawValue])
  }
  func drawPSPMachine() {
    let age=CGFloat(CACurrentMediaTime()-stageStart)
    let flip:CGFloat=phase == .library || phase == .focusing || phase == .inserting ? 1 : phase == .opening ? 1-smooth(age/0.45) : phase == .closing ? smooth(age/0.45) : 0
    let back=flip>0.5
    NSGraphicsContext.saveGraphicsState(); defer {NSGraphicsContext.restoreGraphicsState()}
    let tf=NSAffineTransform();tf.translateX(by:360,yBy:pspY+145);tf.scaleX(by:max(0.025,abs(cos(flip * .pi))),yBy:1);tf.translateX(by:-360,yBy:-pspY-145);tf.concat()

    let r=CGRect(x:30,y:pspY,width:660,height:290)
    let hi=theme == 0 ? 0xECEEF1 : theme == 1 ? 0x414249 : 0x18323E
    let lo=theme == 0 ? 0xB5BCC4 : theme == 1 ? 0x121519 : 0x06131E
    fill(r.offsetBy(dx:0,dy:12),color(0x000000,0.4),85)
    gradient(r.offsetBy(dx:0,dy:7),0x5A6066,lo,83)
    gradient(r,hi,lo,80)
    stroke(r.insetBy(dx:2,dy:2),color(0xE9EDF4,0.5),78,1.2)
    stroke(r.insetBy(dx:8,dy:6),color(0x000000,0.22),72,1)
    if back {
      // The UMD is loaded through the rear door, then the console returns face-up.
      let age=CGFloat((CACurrentMediaTime()-stageStart)/1.2)
      let door=smooth(min(1,age/0.3))*(1-smooth(max(0,(age-0.78)/0.22)))
      drawPSPBack(r,hi:hi,lo:lo)
      if phase == .inserting {
      NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current?.cgContext.setAlpha(door)
      gradient(CGRect(x:222,y:pspY+20,width:276,height:250),0x11161B,0x30363B,30)
      stroke(CGRect(x:222,y:pspY+20,width:276,height:250),color(0x80868C),30,1)
      fill(CGRect(x:271,y:pspY+53,width:178,height:178),color(0x080A0D),81)
      NSGraphicsContext.restoreGraphicsState()
      if door>0.01 {
        let hatch=CGRect(x:219,y:pspY+268,width:282,height:54*door)
        gradient(hatch,hi,lo,12);stroke(hatch,color(0x777F88),12,0.8)
        centered("UMD",360,hatch.midY-5,10,color(0x87919A),.light)
      }
      }
      return
    }
    fill(CGRect(x:186,y:pspY+22,width:348,height:237),color(0x090B0E),5)
    classicScreen(CGRect(x:192,y:pspY+33,width:336,height:190.4))
    if running {fill(CGRect(x:192,y:pspY+33,width:336,height:190.4),color(0x000000,screenDim),0)}
    let ink=color(theme == 0 ? 0x616B77 : 0xBFC6CC)
    text("SONY",88,pspY+22,10,ink,.bold)
    drawPSPMark(CGPoint(x:360,y:pspY+253),width:70,ink:ink)
    for x in [CGFloat(160),CGFloat(549)] { for dy in [CGFloat(54),CGFloat(65),CGFloat(76)] {fill(CGRect(x:x,y:pspY+dy,width:8,height:2),color(0x090C10),1)} }
    modernKeys()
    for (i,label) in ["⌂","−","+","♫","☀"].enumerated() {
      let key=pspUtilityRect(i)
      let cap=plasticKey(key,tint:theme == 0 ? 0xC9CFD3 : 0x323B41,radius:7)
      centered(label,cap.midX,cap.minY+1,8,ink)
    }
    fill(modernPowerRect,color(0x202C30),5)
    powerSymbol(CGPoint(x:modernPowerRect.midX,y:modernPowerRect.midY),5,color(0xC8D7CC))
    fill(CGRect(x:662,y:pspY+152,width:4,height:8),color(running ? 0x82D5A0 : 0x374C41),2)
    if theme == 0 {centered("FINAL FANTASY",612,pspY+210,6,ink,.bold);centered("20TH ANNIVERSARY",612,pspY+220,4,ink)}
    if theme == 1 {centered("HUNTER'S MODEL",612,pspY+217,6,color(0xB6A46C),.bold)}
    if theme == 2 {centered("Winning Eleven",612,pspY+217,7,ink,.bold);text("UEFA CHAMPIONS LEAGUE",541,pspY+220,4,ink)}
  }
  func pspSpatialInk(back:Bool)->NSImage {
    let image=NSImage(size:CGSize(width:720,height:350));image.lockFocusFlipped(true)
    NSGraphicsContext.saveGraphicsState();let tf=NSAffineTransform();tf.translateX(by:0,yBy:30-pspY);tf.concat();NSBezierPath(roundedRect:CGRect(x:30,y:pspY,width:660,height:290),xRadius:120,yRadius:120).addClip()
    let ink=color(theme==0 ? 0x7D8793:0xCCD2D4)
    if back {
      drawPSPMark(CGPoint(x:360,y:pspY+146),width:123,ink:ink)
      text("SONY",93,pspY+21,9,ink,.semibold);text("UMD",464,pspY+21,7,ink)
      if theme==0 {fantasyPrint("left",in:CGRect(x:80,y:pspY+45,width:132,height:195),inkOnly:true);fantasyPrint("right",in:CGRect(x:518,y:pspY+45,width:126,height:195),inkOnly:true)}
      else if theme==1 {drawHunterCrest(CGRect(x:87,y:pspY+43,width:118,height:208),mirrored:false);drawHunterCrest(CGRect(x:515,y:pspY+43,width:118,height:208),mirrored:true)}
      else {drawWinningElevenCrest(CGRect(x:75,y:pspY+78,width:112,height:108));text("Winning Eleven",77,pspY+187,12,ink,.bold);drawStarball(CGRect(x:539,y:pspY+44,width:26,height:26));centered("UEFA",552,pspY+73,6,ink);centered("CHAMPIONS",552,pspY+83,7.2,ink,.bold);centered("LEAGUE",552,pspY+94,5.3,ink);drawStarball(CGRect(x:519,y:pspY+108,width:145,height:145))}
    } else {
      text("SONY",91,pspY+42,10,ink,.bold);drawPSPMark(CGPoint(x:360,y:pspY+268),width:76,ink:ink)
      text("POWER",650,pspY+150,4,ink);text("HOLD",650,pspY+180,4,ink)
      if theme==0 {centered("FINAL FANTASY",612,pspY+210,6,ink,.bold);centered("20TH ANNIVERSARY",612,pspY+220,4,ink)}
      if theme==1 {centered("HUNTER'S MODEL",612,pspY+217,6,color(0xB6A46C),.bold)}
      if theme==2 {centered("Winning Eleven",612,pspY+217,7,ink,.bold)}
    }
    NSGraphicsContext.restoreGraphicsState();image.unlockFocus();return image
  }
  func drawPSPBack(_ r:CGRect,hi:Int,lo:Int) {
    NSGraphicsContext.saveGraphicsState();defer {NSGraphicsContext.restoreGraphicsState()}
    NSBezierPath(roundedRect:r.insetBy(dx:6,dy:5),xRadius:76,yRadius:76).addClip()
    gradient(r.insetBy(dx:7,dy:6),hi,lo,74)
    // Continuous shell shading; avoid bounded grip highlights that read as separate panels.
    if theme == 1 && !exportSpatialSurface { drawHunterGoldTrim(r) }
    let plate=CGRect(x:216,y:pspY+8,width:288,height:274)
    gradient(plate,hi,lo,5)
    if theme == 2 {footballShellReflections(r)}
    // Only the physical UMD door seams are drawn; no nested rectangular frames.
    for x in [plate.minX,plate.maxX] {
      line([CGPoint(x:x,y:plate.minY+2),CGPoint(x:x,y:plate.maxY-3)],color(0x080C13,theme == 0 ? 0.32 : 0.50),0.85)
      line([CGPoint(x:x+1,y:plate.minY+3),CGPoint(x:x+1,y:plate.maxY-4)],color(0xFFFFFF,theme == 0 ? 0.48 : 0.13),0.6)
    }
    line([CGPoint(x:plate.minX+2,y:plate.maxY),CGPoint(x:plate.maxX-2,y:plate.maxY)],color(0x080C13,0.38),1)
    line([CGPoint(x:plate.minX+3,y:plate.maxY+1),CGPoint(x:plate.maxX-3,y:plate.maxY+1)],color(0xFFFFFF,0.26),0.65)
    let latch=CGRect(x:462,y:pspY+9,width:19,height:2.5)
    fill(latch,color(0x111820,0.65),1)
    let diameter:CGFloat=theme == 1 ? 210 : theme == 2 ? 216:200
    let bezel=CGRect(x:360-diameter/2,y:pspY+146-diameter/2,width:diameter,height:diameter)
    let lip:CGFloat=theme == 1 ? 6.5 : theme == 2 ? 9:8
    let silver=theme == 1 ? 0xC5AE63 : theme == 0 ? 0xADB3BB : 0xBAC8D4
    if !exportSpatialSurface {
    let ring=NSBezierPath(ovalIn:bezel);ring.appendOval(in:bezel.insetBy(dx:lip,dy:lip));ring.windingRule = .evenOdd
    NSGraphicsContext.saveGraphicsState();ring.addClip()
    if theme == 2 {
      NSGradient(colorsAndLocations:(color(0xECF7FC),0),(color(0xA8C2D1),0.18),(color(0x536D7E),0.44),(color(0xD4E7F1),0.51),(color(0x9DB9C9),0.72),(color(0xE5F0F6),1))?.draw(in:bezel,angle:122)
      for i in 0..<42 {let x=bezel.minX+CGFloat(i)*5.4;line([CGPoint(x:x,y:bezel.minY),CGPoint(x:x+11,y:bezel.maxY)],color(0xFFFFFF,0.045),0.35)}
    } else {NSGradient(colorsAndLocations:(keyColor(silver,0.42),0),(color(silver),0.28),(keyColor(silver,-0.17),0.64),(keyColor(silver,0.29),1))?.draw(in:bezel,angle:125)}
    NSGraphicsContext.restoreGraphicsState()
    stroke(bezel,color(0x0C1420,theme == 0 ? 0.18 : 0.35),diameter/2,0.8)
    stroke(bezel.insetBy(dx:lip,dy:lip),color(0xFFFFFF,0.32),(diameter-2*lip)/2,0.8)
    }
    drawPSPMark(CGPoint(x:360,y:pspY+146),width:123,ink:color(theme == 1 ? 0xA1A6A7 : theme == 0 ? 0x8E98A3 : 0xA4AFBA))
    text("SONY",theme != 0 ? 154 : 93,pspY+21,9,color(theme == 0 ? 0x929BA4 : 0xADB3B6),.semibold)
    text("UMD",464,pspY+21,7,color(theme == 0 ? 0x929BA4 : 0xADB3B6))
    if theme == 0 {
      fantasyPrint("left",in:CGRect(x:80,y:pspY+45,width:132,height:195))
      fantasyPrint("right",in:CGRect(x:518,y:pspY+45,width:126,height:195))
    } else if theme == 1 {
      drawHunterCrest(CGRect(x:87,y:pspY+43,width:118,height:208),mirrored:false)
      drawHunterCrest(CGRect(x:515,y:pspY+43,width:118,height:208),mirrored:true)
    } else {
      drawWinningElevenCrest(CGRect(x:75,y:pspY+78,width:112,height:108))
      let style:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:12,weight:.heavy),.foregroundColor:color(0xD9E9F1),.obliqueness:0.17]
      let label="Winning Eleven" as NSString,extent=label.size(withAttributes:style)
      label.draw(at:CGPoint(x:131-extent.width/2,y:pspY+187),withAttributes:style)
      drawStarball(CGRect(x:539,y:pspY+44,width:26,height:26))
      centered("UEFA",552,pspY+73,6,color(0xDDECF3),.semibold)
      centered("CHAMPIONS",552,pspY+83,7.2,color(0xDFEDF4),.bold)
      centered("LEAGUE",552,pspY+94,5.3,color(0xDFEDF4),.semibold)
      drawStarball(CGRect(x:519,y:pspY+108,width:145,height:145))
    }
    for x in [CGFloat(645)] {for y in [CGFloat(48),CGFloat(241)] {
      let screw=CGRect(x:x,y:pspY+y,width:6,height:6)
      fill(screw.insetBy(dx:-1,dy:-1),color(0xFFFFFF,0.10),4)
      fill(screw,color(0x070B10),3)
      line([CGPoint(x:screw.minX+1.5,y:screw.midY),CGPoint(x:screw.maxX-1.5,y:screw.midY)],color(0x606972,0.45),0.6)
    }}
  }
  func footballShellReflections(_ r:CGRect) {
    // Polished midnight-blue polycarbonate: broad, curved reflections follow the grips.
    let sweep=NSBezierPath();sweep.move(to:CGPoint(x:38,y:r.minY+47));sweep.curve(to:CGPoint(x:211,y:r.minY+16),controlPoint1:CGPoint(x:82,y:r.minY-3),controlPoint2:CGPoint(x:167,y:r.minY+7));sweep.line(to:CGPoint(x:211,y:r.minY+37));sweep.curve(to:CGPoint(x:41,y:r.minY+102),controlPoint1:CGPoint(x:127,y:r.minY+18),controlPoint2:CGPoint(x:58,y:r.minY+78));sweep.close()
    NSGradient(starting:color(0xACD6EE,0.16),ending:color(0x40697F,0.005))?.draw(in:sweep,angle:95)
    let glint=NSBezierPath();glint.move(to:CGPoint(x:51,y:r.minY+77));glint.curve(to:CGPoint(x:62,y:r.maxY-48),controlPoint1:CGPoint(x:25,y:r.midY-21),controlPoint2:CGPoint(x:27,y:r.midY+48));color(0x9FCADD,0.2).setStroke();glint.lineWidth=2.2;glint.stroke()
    let lower=NSBezierPath();lower.move(to:CGPoint(x:69,y:r.maxY-23));lower.curve(to:CGPoint(x:205,y:r.maxY-15),controlPoint1:CGPoint(x:104,y:r.maxY-11),controlPoint2:CGPoint(x:170,y:r.maxY-18));color(0x9EBCCB,0.16).setStroke();lower.lineWidth=1;lower.stroke()
    line([CGPoint(x:221,y:r.minY+12),CGPoint(x:495,y:r.minY+12)],color(0x91B4C9,0.12),0.8)
    line([CGPoint(x:225,y:r.maxY-14),CGPoint(x:493,y:r.maxY-14)],color(0x02070B,0.7),1.5)
  }
  func drawWinningElevenCrest(_ r:CGRect){
    NSGraphicsContext.saveGraphicsState();defer{NSGraphicsContext.restoreGraphicsState()};let t=NSAffineTransform();t.translateX(by:r.minX,yBy:r.minY);t.scaleX(by:r.width/120,yBy:r.height/120);t.concat()
    func plate(_ points:[CGFloat]){let p=NSBezierPath();for i in stride(from:0,to:points.count,by:2){let q=CGPoint(x:points[i],y:points[i+1]);if i==0{p.move(to:q)}else{p.line(to:q)}};p.close();color(0xD9EAF3).setFill();p.fill()}
    // Crown, winged monogram and pedestal are independent die-cut print shapes.
    plate([35,2,49,2,52,24,59,24,59,0,73,0,73,24,80,24,85,2,99,2,93,38,42,38])
    plate([4,35,38,35,41,49,19,49,29,66,17,72,0,45])
    plate([96,35,119,35,113,49,103,49,94,66,83,61,95,46])
    plate([42,45,93,45,88,58,62,58,59,69,83,69,74,82,55,82,53,93,83,93,75,107,35,107,41,86,25,74,34,62,43,64])
    plate([32,111,79,111,85,120,28,120])
    // Small cut-outs retain the original angular letter spacing at thumbnail scale.
    plate([20,80,31,83,24,96,34,107,23,107,10,94])
  }
  func drawStarball(_ r:CGRect){
    NSGraphicsContext.saveGraphicsState();defer{NSGraphicsContext.restoreGraphicsState()};let t=NSAffineTransform();t.translateX(by:r.minX,yBy:r.minY);t.scaleX(by:r.width/160,yBy:r.height/160);t.concat()
    NSBezierPath(ovalIn:CGRect(x:0,y:0,width:160,height:160)).addClip()
    let ink=color(0xD5E6EF)
    func star(_ points:[CGFloat]){let p=NSBezierPath();for i in stride(from:0,to:points.count,by:2){let q=CGPoint(x:points[i],y:points[i+1]);if i==0{p.move(to:q)}else{p.line(to:q)}};p.close();ink.setFill();p.fill()}
    // White stars on transparent shell, separated by dark pentagonal channels.
    // The limb stars are clipped and foreshortened; no flat white disc is underneath.
    star([104,36,119,67,155,67,128,91,139,127,108,107,77,130,85,94,56,75,93,71])
    star([51,0,73,5,66,18,89,21,62,34,50,58,43,34,18,33,38,22,34,10])
    star([-10,65,19,63,29,38,39,63,65,72,42,84,43,112,23,94,-2,106,9,82])
    star([49,107,62,132,91,139,65,151,56,177,41,151,12,146,36,130,34,110])
    star([159,91,183,105,180,133,164,121,150,153,147,125,129,115,145,109,149,87])
    star([129,-10,144,5,172,9,154,23,156,53,134,37,109,49,118,23,100,3,127,9])
    let arc=NSBezierPath();arc.move(to:CGPoint(x:7,y:49));arc.curve(to:CGPoint(x:145,y:17),controlPoint1:CGPoint(x:43,y:-2),controlPoint2:CGPoint(x:108,y:-8));color(0xEBF5FA,0.8).setStroke();arc.lineWidth=2.3;arc.stroke()
  }
  func fantasyPrint(_ side:String,in r:CGRect,inkOnly:Bool=false) {
    let key="ff-"+side
    if modernImages[key] == nil {modernImages[key]=NSImage(contentsOf:bundledAssets.appendingPathComponent("Skins/Modern/ff-"+side+"-ink.png"))}
    guard let image=modernImages[key],let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil),let ctx=NSGraphicsContext.current?.cgContext else {return}
    if inkOnly {
      let source=CIImage(cgImage:cg),alpha=source.applyingFilter("CIColorInvert").applyingFilter("CIMaskToAlpha")
      let mask=CIImage(color:CIColor(red:0.38,green:0.42,blue:0.47,alpha:1)).cropped(to:source.extent).applyingFilter("CISourceInCompositing",parameters:[kCIInputBackgroundImageKey:alpha])
      if let transparent=CIContext().createCGImage(mask,from:source.extent){ctx.saveGState();ctx.setAlpha(side == "left" ? 0.60:0.50);ctx.translateBy(x:r.minX,y:r.maxY);ctx.scaleBy(x:1,y:-1);ctx.draw(transparent,in:CGRect(origin:.zero,size:r.size));ctx.restoreGState()}
      return
    }
    // Screen-print ink modulates the existing silver material; paper white contributes nothing.
    ctx.saveGState();ctx.setBlendMode(.multiply);ctx.setAlpha(side == "left" ? 0.44 : 0.32)
    ctx.translateBy(x:r.minX,y:r.maxY);ctx.scaleBy(x:1,y:-1)
    ctx.interpolationQuality = .high
    ctx.draw(cg,in:CGRect(origin:.zero,size:r.size));ctx.restoreGState()
  }
  func keyColorInt(_ tint:Int,_ amount:CGFloat) -> Int {
    let c=keyColor(tint,amount).usingColorSpace(.sRGB) ?? color(tint)
    return (Int(c.redComponent*255)<<16)|(Int(c.greenComponent*255)<<8)|Int(c.blueComponent*255)
  }
  func drawHunterGoldTrim(_ r:CGRect) {
    for (right,bottom) in [(false,false),(true,false),(false,true),(true,true)] {
      NSGraphicsContext.saveGraphicsState()
      let tr=NSAffineTransform();tr.translateX(by:right ? r.maxX-13 : r.minX+13,yBy:bottom ? r.maxY-8 : r.minY+8);tr.scaleX(by:right ? -1 : 1,yBy:bottom ? -1 : 1);tr.concat()
      let p=NSBezierPath();p.move(to:CGPoint(x:4,y:39));p.curve(to:CGPoint(x:83,y:0),controlPoint1:CGPoint(x:19,y:7),controlPoint2:CGPoint(x:42,y:0));p.line(to:CGPoint(x:103,y:0));p.line(to:CGPoint(x:91,y:13));p.curve(to:CGPoint(x:21,y:52),controlPoint1:CGPoint(x:54,y:13),controlPoint2:CGPoint(x:30,y:25));p.close()
      NSGradient(colorsAndLocations:(color(0xE3D394),0),(color(0xB4A166),0.38),(color(0x786132),0.8),(color(0xC6B16D),1))?.draw(in:p,angle:80)
      color(0x3E3424).setStroke();p.lineWidth=1;p.stroke()
      line([CGPoint(x:24,y:29),CGPoint(x:43,y:17),CGPoint(x:75,y:8)],color(0xF5E6B4,0.52),0.8)
      NSGraphicsContext.restoreGraphicsState()
    }
  }
  func draw3DSMark(_ center:CGPoint,size:CGFloat,ink:NSColor) {
    let word=NSMutableAttributedString(string:"NINTENDO ",attributes:[.font:NSFont.systemFont(ofSize:size*0.82,weight:.medium),.foregroundColor:ink])
    word.append(NSAttributedString(string:"3",attributes:[.font:NSFont.systemFont(ofSize:size,weight:.bold),.foregroundColor:color(0xCE292C)]))
    word.append(NSAttributedString(string:"DS",attributes:[.font:NSFont.systemFont(ofSize:size,weight:.bold),.foregroundColor:ink]))
    let extent=word.size();word.draw(at:CGPoint(x:center.x-extent.width/2,y:center.y-extent.height/2))
  }
  func drawPSPMark(_ center:CGPoint,width:CGFloat,ink:NSColor) {
    NSGraphicsContext.saveGraphicsState();defer{NSGraphicsContext.restoreGraphicsState()}
    let t=NSAffineTransform();t.translateX(by:center.x-width/2,yBy:center.y-width*52/240/2);t.scale(by:width/240);t.concat()
    let paths:[[CGPoint]]=[
      [CGPoint(x:0,y:52),CGPoint(x:0,y:0),CGPoint(x:64,y:0),CGPoint(x:64,y:25),CGPoint(x:0,y:25)],
      [CGPoint(x:152,y:0),CGPoint(x:88,y:0),CGPoint(x:88,y:26),CGPoint(x:152,y:26),CGPoint(x:152,y:52),CGPoint(x:88,y:52)],
      [CGPoint(x:176,y:52),CGPoint(x:176,y:0),CGPoint(x:240,y:0),CGPoint(x:240,y:25),CGPoint(x:176,y:25)]]
    for path in paths {line(path,ink,3)}
  }
  func drawHunterCrest(_ r:CGRect,mirrored:Bool) {
    // Hand-built vector paths from the reference: swept horns, open jaws,
    // angular neck scales and a spiral cheek. No raster decal is used.
    NSGraphicsContext.saveGraphicsState();defer{NSGraphicsContext.restoreGraphicsState()}
    let t=NSAffineTransform();t.translateX(by:mirrored ? r.maxX : r.minX,yBy:r.minY);t.scaleX(by:(mirrored ? -1 : 1)*r.width/160,yBy:r.height/220);t.concat()
    func shape(_ points:[CGPoint],_ ink:NSColor) {
      let p=NSBezierPath();for (i,q) in points.enumerated(){if i==0 {p.move(to:q)}else{p.line(to:q)}};p.close();ink.setFill();p.fill()
    }
    func polygon(_ xy:[CGFloat],_ ink:NSColor) {var points:[CGPoint]=[];for i in stride(from:0,to:xy.count,by:2){points.append(CGPoint(x:xy[i],y:xy[i+1]))};shape(points,ink)}
    let silver=color(0xB2B5AF,0.88),dark=color(0x303238)
    // Rear mane: individually stepped, pointed scales rather than a blurred outline.
    polygon([91,62,143,23,122,65,155,48,131,81,160,73,137,99,158,96,137,115,156,119,129,129,151,145,122,146,139,169,111,159,119,191,98,174,93,218,80,174,62,195,65,159,46,173,54,140,34,151,49,118,71,104],silver)
    polygon([68,75,30,4,92,62,126,43,105,79,76,95],silver)
    // Brow and upper jaw, with the pointed muzzle and a serrated line of teeth.
    polygon([7,55,25,79,61,86,93,74,119,67,91,97,72,101,57,111,38,108,31,116,26,103,21,109,17,94,10,94,6,79],silver)
    polygon([59,91,91,81,75,96,65,98],dark)
    polygon([18,83,30,88,27,92,16,88],dark)
    // Separated lower jaw keeps the black open mouth clear at small sizes.
    polygon([61,112,77,111,73,128,61,134,52,133,40,146,5,179,27,138,35,124,42,133,45,119,50,126,54,114],silver)
    polygon([30,139,45,137,17,164],dark)
    // Engraved cheek spiral and the long chin spur.
    polygon([76,105,94,101,104,115,94,134,80,140,91,156,83,180,72,154,63,147,69,134,89,129,94,116,87,109,79,113,78,122,85,123,87,117,90,120,87,128,75,128,70,119],silver)
    polygon([74,151,82,162,77,180,73,170],dark)
    // Negative-space channels separate the scales like the original silver print.
    for xy in [[108,79,129,61,115,85,98,96],[119,102,142,88,126,109,107,116],[114,127,137,130,115,136,99,130],[102,147,122,157,105,153,95,143],[94,166,102,179,93,172]] as [[CGFloat]] {polygon(xy,dark)}
    line([CGPoint(x:57,y:72),CGPoint(x:42,y:29),CGPoint(x:80,y:65)],color(0xD1D1C9,0.35),0.8)
  }
  func draw3DSLidPrint() {
    func polygon(_ coordinates:[CGFloat],_ ink:NSColor,filled:Bool=false) {
      let p=NSBezierPath();for i in stride(from:0,to:coordinates.count,by:2){let q=CGPoint(x:coordinates[i],y:coordinates[i+1]);if i==0{p.move(to:q)}else{p.line(to:q)}};p.close();if filled {ink.setFill();p.fill()}else{ink.setStroke();p.lineWidth=1.3;p.stroke()}
    }
    if theme == 0 {
      let gold=color(0xE5BD5E,0.85)
      // Hylian crest: the Triforce, spreading wings and ornamental border are vector layers.
      for p in [[320,39,287,96,353,96],[287,96,254,153,320,153],[353,96,320,153,386,153]] as [[CGFloat]] {polygon(p,gold,filled:true)}
      for side in [-1,1] {
        let d=CGFloat(side)
        for i in 0..<5 {let y=CGFloat(i)*16+111;let far=CGFloat(95+i*13);polygon([320+d*53,y,320+d*far,y-38,320+d*(far-17),y-4,320+d*49,y+13],gold,filled:true)}
        line([CGPoint(x:320+d*45,y:174),CGPoint(x:320+d*91,y:204),CGPoint(x:320+d*56,y:204),CGPoint(x:320+d*77,y:232),CGPoint(x:320+d*39,y:220),CGPoint(x:320+d*24,y:259)],gold,3)
        let base:CGFloat=side == -1 ? 42 : 598
        for row in 0..<4 {let inset=CGFloat(row)*10;let y:CGFloat=257+CGFloat(row)*12
          line([CGPoint(x:base-d*inset,y:225+CGFloat(row)*6),CGPoint(x:base-d*inset,y:y),CGPoint(x:base-d*(75+inset),y:y)],gold,2)
        }
      }
      polygon([320,161,300,183,307,213,320,240,333,213,340,183],gold)
      polygon([320,198,306,232,320,292,334,232],gold)
      stroke(CGRect(x:309,y:173,width:22,height:22),gold,11,2)
      for y in [CGFloat(214),234,254] {polygon([320,y-7,315,y,320,y+7,325,y],gold)}
    } else {
      drawSunMoonSilk()
    }
  }
  // Clean vector ink traced and simplified from the supplied flat lid reference.
  // It is a white silk-print layer on molded black resin, never embossed geometry.
  func sunMoonSilkPath(_ section:String="lid")->NSBezierPath {
    let path=NSBezierPath();path.windingRule = .evenOdd
    guard let data=try? Data(contentsOf:bundledAssets.appendingPathComponent("Patterns/3ds-sunmoon-silk.json")),let document=(try? JSONSerialization.jsonObject(with:data)) as? [String:[[Double]]],let commands=document[section] else{return path}
    for c in commands{switch Int(c[0]){case 0:path.move(to:CGPoint(x:c[1],y:c[2]));case 1:path.line(to:CGPoint(x:c[1],y:c[2]));default:path.close()}}
    return path
  }
  func drawSunMoonSilk(){color(0xE7EBE8,0.95).setFill();sunMoonSilkPath().fill()}
  func draw3DSOuter() {
    gradient(CGRect(x:0,y:0,width:640,height:330),shellHi,shellLo,23)
    if theme == 2 {
      NSGraphicsContext.saveGraphicsState();NSBezierPath(roundedRect:CGRect(x:3,y:3,width:634,height:324),xRadius:48,yRadius:48).addClip()
      reference("3ds-2",crop:CGRect(x:0.075,y:0.33,width:0.85,height:0.432),in:CGRect(x:0,y:0,width:640,height:330))
      NSGraphicsContext.restoreGraphicsState()
    } else {
      draw3DSLidPrint()
      for x in (theme == 0 ? [CGFloat(250),390] : [CGFloat(320)]) {
        fill(CGRect(x:x-8,y:302,width:16,height:16),color(0x080B0E),8)
        stroke(CGRect(x:x-8,y:302,width:16,height:16),color(0x69727C,0.7),8,1)
        fill(CGRect(x:x-3,y:307,width:6,height:6),color(0x233442),3)
        fill(CGRect(x:x-2,y:307,width:2,height:2),color(0xB7D1DF,0.4),1)
      }
    }
    stroke(CGRect(x:2,y:2,width:636,height:326),color(0xFFFFFF,0.4),22,1)
  }
  func draw3DSInner() {
    gradient(CGRect(x:0,y:0,width:640,height:330),0x292B30,0x111316,22)
    stroke(CGRect(x:3,y:3,width:634,height:324),color(0x55575A),20,1)
    screen(CGRect(x:120,y:44,width:400,height:240),0)
    for x in [CGFloat(60),CGFloat(573)] { for y in stride(from:CGFloat(128),through:176,by:9) {fill(CGRect(x:x,y:y,width:5,height:3),color(0x050608),2)} }
    for x in [CGFloat(301),CGFloat(329)] {fill(CGRect(x:x,y:16,width:9,height:9),color(0x05080A),5);stroke(CGRect(x:x,y:16,width:9,height:9),color(0x454B51),5,0.7)}
    text("3D",575,49,7,color(0x838C92))
  }
  func draw3DSBase() {
    NSGraphicsContext.saveGraphicsState();let tr=NSAffineTransform();tr.translateX(by:240,yBy:0);tr.concat()
    let r=CGRect(x:40,y:baseY,width:640,height:330)
    fill(r.offsetBy(dx:0,dy:11),color(0x000000,0.42),24)
    gradient(r.offsetBy(dx:0,dy:6),shellLo,0x080B0F,23)
    gradient(r,0x32363C,0x171B20,23)
    stroke(r.insetBy(dx:2,dy:2),color(0x6C7075),21,1)
    screen(CGRect(x:200,y:baseY+44,width:320,height:240),1)
    modernKeys()
    let cap=plasticKey(modernPowerRect,tint:0x3C444D,radius:7)
    powerSymbol(CGPoint(x:cap.midX,y:cap.midY),5,color(0xBFC6CC))
    let home=CGRect(x:343,y:baseY+300,width:34,height:15)
    let hcap=plasticKey(home,tint:0x363C42,radius:5);centered("⌂",hcap.midX,hcap.minY+1,10,color(0xADB8C1))
    fill(CGRect(x:584,y:baseY+320,width:5,height:6),color(running ? 0x5FB5F2 : 0x233749),2)
    text("HOME",360,baseY+321,5,color(0x8E999F))
    NSGraphicsContext.restoreGraphicsState()
  }
  func drawModernMedia(_ game:Game,_ r:CGRect,_ active:Bool) {
    NSGraphicsContext.saveGraphicsState();let t=NSAffineTransform();t.translateX(by:r.minX,yBy:r.minY);t.scale(by:r.width/160);t.concat()
    let tint=cartridgeTint(game)
    let body=NSBezierPath()
    if handheld == .n3ds {
      body.move(to:CGPoint(x:6,y:3));for p in [CGPoint(x:158,y:3),CGPoint(x:158,y:30),CGPoint(x:150,y:30),CGPoint(x:150,y:150),CGPoint(x:141,y:157),CGPoint(x:9,y:157),CGPoint(x:2,y:148),CGPoint(x:2,y:9)] {body.line(to:p)};body.close()
    } else {
      body.appendRoundedRect(CGRect(x:2,y:2,width:156,height:155),xRadius:36,yRadius:36)
    }
    let shadow=NSShadow();shadow.shadowColor=color(0x000000,0.5);shadow.shadowBlurRadius=7;shadow.shadowOffset=NSSize(width:0,height:-5);shadow.set()
    color(handheld == .psp ? 0xE2E2D8 : 0xD3D4CF).setFill();body.fill();NSShadow().set()
    color(tint,handheld == .psp ? 0.15 : 0.40).setFill();body.fill()
    color(active ? 0xE8DBAF : 0x9B9D94).setStroke();body.lineWidth=active ? 1.5 : 0.8;body.stroke()
    if handheld == .psp {
      let disc=CGRect(x:11,y:6,width:138,height:138)
      NSGraphicsContext.saveGraphicsState();NSBezierPath(ovalIn:disc).addClip()
      if let cover=game.cover {cover.draw(in:disc)} else {gradient(disc,tint,0x141C21,0);centered(game.title,80,40,9,color(0xFFFFFF),.bold)}
      NSGraphicsContext.restoreGraphicsState();stroke(disc,color(0xB4B6AE),69,2)
      fill(CGRect(x:51,y:46,width:58,height:58),color(0xE5E6DF),29);centered("UMD",80,62,17,color(0x597AB3),.light);centered("UNIVERSAL MEDIA DISC",80,83,3.5,color(0x686D71))
      drawPSPMark(CGPoint(x:33,y:148),width:31,ink:color(0x737D86));text("◉",133,142,9,color(0x7B8485))
    } else {
      fill(CGRect(x:16,y:14,width:120,height:132),color(0xF3F3EC),6)
      if let cover=game.cover {cover.draw(in:CGRect(x:19,y:34,width:114,height:100))} else {gradient(CGRect(x:19,y:34,width:114,height:100),tint,0x182523,0);centered(game.title,76,62,8,color(0xFFFFFF),.bold)}
      draw3DSMark(CGPoint(x:76,y:26),size:10,ink:color(0x242629))
      centered("LNA-CTR · "+String(game.code.suffix(5)),76,137,5,color(0x4E5251),.medium)
      line([CGPoint(x:8,y:31),CGPoint(x:8,y:137)],color(0x8F9690,0.6),0.8)
    }
    NSGraphicsContext.restoreGraphicsState()
  }
  func drawModernFlyingMedia() {
    guard phase == .inserting,let game=selected else{return}
    let age=CGFloat(min(1,(CACurrentMediaTime()-stageStart)/1.2)),t=smooth(min(1,age/0.72))
    let source=cardRect(selectedIndex),w=mix(source.width,handheld == .psp ? 154 : mediaSlots["3ds"]!.cardWidth,t)
    let targetY=handheld == .psp ? pspY+61 : baseY-mediaSlots["3ds"]!.cardWidth-8
    var y=mix(source.minY,targetY,t)-sin(t * .pi)*26
    if age>0.72 && handheld == .n3ds {y+=smooth((age-0.72)/0.28)*(mediaSlots["3ds"]!.cardWidth+15)}
    NSGraphicsContext.saveGraphicsState()
    if handheld == .n3ds {NSBezierPath(rect:CGRect(x:0,y:0,width:720,height:baseY-4)).addClip()}
    if handheld == .psp {NSGraphicsContext.current?.cgContext.setAlpha(1-smooth(max(0,(age-0.8)/0.2)))}
    drawModernMedia(game,CGRect(x:mix(source.midX,360,t)-w/2,y:y,width:w,height:w),false)
    NSGraphicsContext.restoreGraphicsState()
  }
  func pspUtilityRect(_ i:Int) -> CGRect { CGRect(x:[CGFloat(192),228,264,460,424][i],y:pspY+257.5,width:25,height:15) }
  var modernUtilities: [(CGRect,String)] {
    if handheld == .n3ds {return [(CGRect(x:343,y:baseY+300,width:34,height:15),"HOME · 保存退出，返回选卡")]}
    return ["HOME · 保存退出，返回选盘","降低音量","提高音量",muted ? "恢复声音" : "静音","切换屏幕亮度"].enumerated().map {(pspUtilityRect($0.offset),$0.element)}
  }
  func handleModernUtility(_ p:CGPoint) -> Bool {
    guard lid>0.99, let index=modernUtilities.firstIndex(where:{$0.0.contains(p)}) else{return false}
    if handheld == .n3ds || index == 0 {handlePower();return true}
    if index == 1 {volumeLevel=max(0,volumeLevel-0.1)}
    if index == 2 {volumeLevel=min(1,volumeLevel+0.1)}
    if index == 3 {muted.toggle()}
    if index == 4 {screenDim=screenDim<0.3 ? screenDim+0.15 : 0}
    emu_volume(muted ? 0 : volumeLevel);tooltipSignature="";needsDisplay=true;return true
  }
  func drawModernSketch(_ kind:Handheld,in r:CGRect) {
    NSGraphicsContext.saveGraphicsState();let t=NSAffineTransform();t.translateX(by:r.minX,yBy:r.minY);t.scaleX(by:r.width/200,yBy:r.height/120);t.concat()
    let ink=color(0xB8C9AD)
    if kind == .psp {
      stroke(CGRect(x:1,y:20,width:198,height:84),ink,30,1.2);stroke(CGRect(x:50,y:29,width:100,height:58),ink,2,1)
      stroke(CGRect(x:14,y:41,width:22,height:22),ink,6,1)
      for p in [CGPoint(x:172,y:40),CGPoint(x:183,y:52),CGPoint(x:160,y:52),CGPoint(x:172,y:64)] {stroke(CGRect(x:p.x,y:p.y,width:7,height:7),ink,4,1)}
      stroke(CGRect(x:22,y:75,width:14,height:14),ink,7,1)
    } else {
      stroke(CGRect(x:42,y:0,width:116,height:55),ink,8,1.2);stroke(CGRect(x:42,y:61,width:116,height:57),ink,8,1.2)
      stroke(CGRect(x:60,y:8,width:80,height:42),ink,2,1);stroke(CGRect(x:69,y:68,width:62,height:44),ink,2,1)
      line([CGPoint(x:45,y:58),CGPoint(x:155,y:58)],ink,3)
      stroke(CGRect(x:48,y:68,width:12,height:12),ink,6,1)
      line([CGPoint(x:54,y:88),CGPoint(x:54,y:105)],ink,4);line([CGPoint(x:47,y:96),CGPoint(x:61,y:96)],ink,4)
      for p in [CGPoint(x:143,y:77),CGPoint(x:150,y:84),CGPoint(x:136,y:84),CGPoint(x:143,y:91)] {stroke(CGRect(x:p.x,y:p.y,width:4,height:4),ink,2,1)}
    }
    NSGraphicsContext.restoreGraphicsState()
  }
}
