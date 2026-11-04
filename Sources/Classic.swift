import Cocoa
import QuartzCore

extension StudioView {
  func rawGameCode(_ url: URL) -> String {
    let name = url.lastPathComponent.lowercased()
    if name.contains("gold version") { return "GB_GOLD" }
    if name.contains("silver version") { return "GB_SILVER" }
    var hash: UInt64 = 1_469_598_103_934_665_603
    for byte in name.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
    return "GB_" + String(hash, radix: 16)
  }
  func modelRect(_ i: Int) -> CGRect {
    themeRect(i)
  }
  func selectHandheld(_ kind: Handheld) {
    guard kind != handheld else { return }
    if running {
      CoreDriver.shared.save()
      CoreDriver.shared.stop()
      running = false
      videoFrame = nil
    }
    releaseAll()
    handheld = kind
    theme = UserDefaults.standard.integer(forKey: "theme." + kind.rawValue)
    theme = min(handheld.editions.count-1, max(0, theme))
    lid = 0
    pose = 0
    bookMode = false
    inserted = false
    phaseTo(.library)
    scan()
    selectedIndex = games.count / 2
    carousel = CGFloat(selectedIndex)
    tooltipSignature = ""
    resizeForMachine()
    needsDisplay = true
  }
  func resizeForMachine() {
    guard let window else { return }
    // AppKit owns the full-screen frame, including both transition animations.
    // A phase change (insert/eject/home) must never shrink that frame.
    guard !fullScreenTransition, !window.styleMask.contains(.fullScreen) else {
      needsDisplay = true
      return
    }
    let height = canvasHeight
    let size = NSSize(width: 720, height: height)
    window.contentMinSize = size
    let top = window.frame.maxY
    let frame = window.frameRect(forContentRect: CGRect(origin: .zero, size: size))
    window.setFrame(
      CGRect(x: window.frame.minX, y: top - frame.height, width: frame.width, height: frame.height),
      display: true)
  }
  var classicT: CGFloat { smooth(lid) }
  var classicScale: CGFloat { handheld == .gbc ? mix(0.62, 1, classicT) : 1 }
  var classicOrigin: CGPoint {
    handheld == .gba
      ? CGPoint(x: 40, y: mix(390, 140, classicT))
      : CGPoint(x: 360 - 175 * classicScale, y: mix(380, 110, classicT))
  }
  func classicRect(_ local: CGRect) -> CGRect {
    CGRect(
      x: classicOrigin.x + local.minX * classicScale,
      y: classicOrigin.y + local.minY * classicScale, width: local.width * classicScale,
      height: local.height * classicScale)
  }
  var classicPowerRect: CGRect {
    classicRect(
      handheld == .gba
        ? CGRect(x: 572, y: 285, width: 36, height: 17)
        : CGRect(x: 347, y: 83, width: 13, height: 38)
    ).offsetBy(dx: 240, dy: 0)
  }
  var classicButtons: [(String, Int, CGRect)] {
    let defs: [(String, Int, CGRect)] =
      handheld == .gba
      ? [
        ("A", 8, CGRect(x: 572, y: 111, width: 40, height: 40)),
        ("B", 0, CGRect(x: 528, y: 151, width: 40, height: 40)),
        ("START", 3, CGRect(x: 90, y: 252, width: 14, height: 14)),
        ("SELECT", 2, CGRect(x: 84, y: 278, width: 14, height: 14)),
        ("L", 10, CGRect(x: 14, y: -7, width: 101, height: 31)),
        ("R", 11, CGRect(x: 525, y: -7, width: 101, height: 31)),
      ]
      : [
        ("A", 8, CGRect(x: 263, y: 352, width: 44, height: 44)),
        ("B", 0, CGRect(x: 207, y: 378, width: 44, height: 44)),
        ("SELECT", 2, CGRect(x: 115, y: 466, width: 39, height: 14)),
        ("START", 3, CGRect(x: 170, y: 466, width: 39, height: 14)),
      ]
    return defs.map { ($0.0, $0.1, classicRect($0.2).offsetBy(dx: 240, dy: 0)) }
  }
  var classicDpad: [(String, Int, CGRect)] {
    let x: CGFloat = handheld == .gba ? 33 : 35
    let y: CGFloat = handheld == .gba ? 124 : 340
    let w: CGFloat = 28
    return [
      ("", 4, CGRect(x: x + w, y: y, width: w, height: w)),
      ("", 5, CGRect(x: x + w, y: y + 2 * w, width: w, height: w)),
      ("", 6, CGRect(x: x, y: y + w, width: w, height: w)),
      ("", 7, CGRect(x: x + 2 * w, y: y + w, width: w, height: w)),
    ].map { ($0.0, $0.1, classicRect($0.2).offsetBy(dx: 240, dy: 0)) }
  }
  func showModelPicker() {
    pickerPage = .models
    pickerIndex = Handheld.allCases.firstIndex(of: handheld) ?? 0
    modelPosition=CGFloat(pickerIndex)
    needsDisplay = true
    report()
  }
  func chooseMachine(_ kind: Handheld) {
    selectHandheld(kind);gbcThemePosition=CGFloat(theme);choosing=true;pickerPage = .themes;pickerIndex=theme;hoverLabel=nil;tooltipSignature="";resizeForMachine();needsDisplay=true;report()
  }
  func themeGridRect(_ index:Int)->CGRect {CGRect(x:48+CGFloat(index)*216,y:255,width:192,height:245)}
  func confirmTheme(_ index:Int){
    theme=index;UserDefaults.standard.set(index,forKey:"theme."+handheld.rawValue);choosing=false;hoverLabel=nil;tooltipSignature="";lid=0;phaseTo(.library);resizeForMachine();scan();needsDisplay=true;report()
  }
  func themeThumbnail(_ value:Int)->NSImage {
    let cacheKey=handheld.rawValue+"-"+String(value);if let cached=themePreviews[cacheKey]{return cached}
    if !CommandLine.arguments.contains("--render-source"),let image=NSImage(contentsOf:bundledAssets.appendingPathComponent("Skins/ThemePreviews/"+cacheKey+".png")){themePreviews[cacheKey]=image;return image}
    let previous=(theme,lid,phase,running);theme=value;lid=handheld == .gba || handheld == .gbc ? 1:0;phase = .library;running=false
    func snapshot(_ crop:CGRect)->NSImage {
      let image=NSImage(size:crop.size);image.lockFocusFlipped(true);NSGraphicsContext.saveGraphicsState();let transform=NSAffineTransform();transform.translateX(by:-crop.minX,yBy:-crop.minY);transform.concat();drawMachine();NSGraphicsContext.restoreGraphicsState();image.unlockFocus();return image
    }
    let crop:CGRect=handheld == .gba ? CGRect(x:30,y:120,width:660,height:370):handheld == .gbc ? CGRect(x:175,y:90,width:380,height:620):handheld == .psp ? CGRect(x:0,y:388,width:720,height:350):CGRect(x:30,y:397,width:660,height:365)
    let closed=snapshot(crop),image=NSImage(size:CGSize(width:210,height:132))
    image.lockFocusFlipped(true)
    func fit(_ image:NSImage,_ rect:CGRect){let q=min(rect.width/image.size.width,rect.height/image.size.height);image.draw(in:CGRect(x:rect.midX-image.size.width*q/2,y:rect.midY-image.size.height*q/2,width:image.size.width*q,height:image.size.height*q))}
    fit(closed,CGRect(x:8,y:2,width:194,height:handheld == .gba || handheld == .gbc ? 128:90))
    if handheld == .nds || handheld == .n3ds || handheld == .psp {
      image.unlockFocus();lid=1;phase = .playing
      let open=snapshot(handheld == .psp ? CGRect(x:0,y:70,width:720,height:350):CGRect(x:0,y:50,width:720,height:730))
      image.lockFocusFlipped(true);fit(open,CGRect(x:101,y:62,width:103,height:66))
    }
    image.unlockFocus()
    (theme,lid,phase,running)=previous;themePreviews[cacheKey]=image;return image
  }
  func drawHandheldPicker() {
    fill(CGRect(x:0,y:0,width:720,height:780),color(0x191E1D))
    if usesGBC3D{drawSpatialPicker();return}
    if pickerPage == .themes {
      pill("‹  选择机型",CGRect(x:28,y:28,width:160,height:40))
      centered(handheld.name,360,145,25,color(0xF0EAD9),.semibold)
      centered("选择机身主题",360,190,12,color(0x91A08F))
      for i in 0..<3 {let r=themeGridRect(i),active=i==pickerIndex;fill(r,color(active ? 0x2D3731:0x222A26),18);stroke(r,color(active ? 0xA8BA9D:0x3D4B41),18,active ? 1.5:0.6)
        let image=themeThumbnail(i),area=CGRect(x:r.minX+12,y:r.minY+25,width:r.width-24,height:145),q=min(area.width/image.size.width,area.height/image.size.height)
        image.draw(in:CGRect(x:area.midX-image.size.width*q/2,y:area.midY-image.size.height*q/2,width:image.size.width*q,height:image.size.height*q))
        centered(handheld.editions[i],r.midX,r.maxY-47,12,color(0xD8DFD4),.medium)
      }
      centered("方向键切换 · 回车确认 · Esc 返回",360,715,11,color(0x91A08F));return
    }
    centered("选择你的掌机",360,85,25,color(0xF0EAD9),.semibold);centered("HOME",360,137,10,color(0x7B8D80))
    for (i,kind) in Handheld.allCases.enumerated(){let r=modelRect(i),active=i==pickerIndex;fill(r,color(active ? 0x2D3731:0x222A26),18);stroke(r,color(active ? 0xA8BA9D:0x3D4B41),18,active ? 1.5:0.6);if kind != .gbc || CommandLine.arguments.contains("--render-source"){drawMachineSketch(kind,in:CGRect(x:r.minX+20,y:r.minY+15,width:164,height:115))};drawClassicWordmark(kind,x:r.midX,y:r.minY+151);centered(kind.name,r.midX,r.minY+180,12,color(0xD8DFD4),.medium)}
    centered("方向键切换 · 回车选择机型",360,752,10,color(0x718477))
  }
  func drawClassicWordmark(_ kind: Handheld, x: CGFloat, y: CGFloat) {
    if kind == .psp { drawPSPMark(CGPoint(x:x,y:y+8),width:87,ink:color(0xDEE4DA)); return }
    if kind == .n3ds { draw3DSMark(CGPoint(x:x,y:y+8),size:17,ink:color(0xDCE4D8)); return }
    if machineLogos[kind] == nil {
      machineLogos[kind] = NSImage(contentsOf: Bundle.main.resourceURL!.appendingPathComponent("Assets/Logos/" + kind.rawValue + "-dark.svg"))
    }
    if let logo = machineLogos[kind] {
      let factor = min(164 / logo.size.width, 36 / logo.size.height)
      let size = CGSize(width: logo.size.width * factor, height: logo.size.height * factor)
      logo.draw(in: CGRect(x: x - size.width / 2, y: y + 4 - size.height / 2, width: size.width, height: size.height))
      return
    }
    let ink = color(0xD5DDD0)
    if kind == .nds {
      centered("Nintendo DS", x, y, 20, ink, .semibold)
      stroke(CGRect(x: x - 8, y: y - 23, width: 13, height: 8), ink, 1, 1)
      stroke(CGRect(x: x - 8, y: y - 13, width: 13, height: 8), ink, 1, 1)
    } else {
      centered("GAME BOY", x, y - 8, 19, ink, .heavy)
      if kind == .gba { centered("ADVANCE", x, y + 16, 10, ink, .bold) }
      else {
        let colors = [0xDA4964, 0x8275B6, 0x80AD46, 0xE4C851, 0x4CACC2]
        for (i, letter) in Array("COLOR").enumerated() {
          centered(String(letter), x - 28 + CGFloat(i) * 14, y + 16, 13, color(colors[i]), .heavy)
        }
      }
    }
  }
  func drawMachineSketch(_ kind: Handheld, in area: CGRect) {
    if kind == .psp || kind == .n3ds { drawModernSketch(kind,in:area); return }
    let size: CGSize = kind == .nds ? CGSize(width: 180, height: 190) : kind == .gba ? CGSize(width: 230, height: 130) : CGSize(width: 120, height: 195)
    let factor = min(area.width / size.width, area.height / size.height)
    NSGraphicsContext.saveGraphicsState()
    let tf = NSAffineTransform()
    tf.translateX(by: area.midX - size.width * factor / 2, yBy: area.midY - size.height * factor / 2)
    tf.scale(by: factor)
    tf.concat()
    let ink = color(0xC0CDB7)
    func outline(_ r: CGRect, _ radius: CGFloat = 3) {
      stroke(r, ink, radius, 1.1)
      stroke(r.offsetBy(dx: 1.3, dy: -0.7), color(0xADBF9B, 0.20), radius, 0.5)
    }
    func cross(_ x: CGFloat, _ y: CGFloat) {
      line([CGPoint(x: x + 9, y: y), CGPoint(x: x + 9, y: y + 27)], ink, 6)
      line([CGPoint(x: x - 4, y: y + 13), CGPoint(x: x + 22, y: y + 13)], ink, 6)
    }
    if kind == .nds {
      outline(CGRect(x: 0, y: 0, width: 180, height: 90), 8)
      outline(CGRect(x: 0, y: 100, width: 180, height: 90), 8)
      outline(CGRect(x: 2, y: 91, width: 176, height: 8), 4)
      for y in [CGFloat(14), CGFloat(112)] { outline(CGRect(x: 45, y: y, width: 90, height: 65), 2) }
      cross(13, 131)
      for p in [CGPoint(x: 155,y: 127),CGPoint(x: 168,y: 140),CGPoint(x: 142,y: 140),CGPoint(x: 155,y: 153)] { outline(CGRect(x: p.x - 4,y: p.y - 4,width: 8,height: 8),4) }
      for x in [CGFloat(20), CGFloat(157)] { for y in [CGFloat(35),CGFloat(43),CGFloat(51)] { outline(CGRect(x: x,y: y,width: 2,height: 2),1) } }
    } else if kind == .gba {
      outline(CGRect(x: 0, y: 0, width: 230, height: 130), 35)
      outline(CGRect(x: 53, y: 10, width: 124, height: 106), 17)
      outline(CGRect(x: 62, y: 22, width: 106, height: 71), 2)
      cross(16, 45)
      for p in [CGPoint(x: 210,y: 48),CGPoint(x: 190,y: 64)] { outline(CGRect(x:p.x-7,y:p.y-7,width:14,height:14),7) }
      for y in [CGFloat(91), CGFloat(99)] { outline(CGRect(x: 22,y:y,width:15,height:3),2) }
      for y in stride(from: CGFloat(91), through: 111, by: 5) { outline(CGRect(x: 191,y:y,width:22,height:1),0) }
    } else {
      outline(CGRect(x: 0, y: 0, width: 120, height: 195), 15)
      outline(CGRect(x: 10,y: 12,width:100,height:83),8)
      outline(CGRect(x: 26,y: 22,width:68,height:61),1)
      cross(18, 117)
      for p in [CGPoint(x: 98,y: 119),CGPoint(x: 78,y: 130)] { outline(CGRect(x:p.x-7,y:p.y-7,width:14,height:14),7) }
      for x in [CGFloat(40), CGFloat(60)] { outline(CGRect(x:x,y:163,width:14,height:4),2) }
      for x in stride(from: CGFloat(85), through: 105, by: 5) { for y in stride(from: CGFloat(165), through: 180, by: 5) { outline(CGRect(x:x,y:y,width:1,height:1),0.5) } }
    }
    NSGraphicsContext.restoreGraphicsState()
  }
  func classicScreen(_ r: CGRect, _ preview: Bool = false) {
    fill(r.insetBy(dx: -6, dy: -6), color(0x06090A), 4)
    if running && !preview, let image = videoFrame {
      NSGraphicsContext.current?.imageInterpolation = .none
      NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height)).draw(in: r)
    } else {
      gradient(r, 0x242B29, 0x101814, 2)
      fill(
        CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.45),
        color(0xFFFFFF, 0.025), 2)
    }
  }
  func drawClassicMachine() {
    NSGraphicsContext.saveGraphicsState()
    let tr = NSAffineTransform()
    tr.translateX(by: classicOrigin.x, yBy: classicOrigin.y)
    tr.scale(by: classicScale)
    tr.concat()
    if handheld == .gba { drawGBABody() } else { drawGBCBody() }
    NSGraphicsContext.restoreGraphicsState()
  }
  func drawCross(_ x: CGFloat, _ y: CGFloat, _ tint: Int) {
    plasticDpad(CGRect(x:x,y:y,width:84,height:84),tint:tint)
  }
  func drawClassicKeys(_ preview: Bool) {
    for (name, id, world) in classicButtons {
      let r = CGRect(x:(world.minX-240-classicOrigin.x)/classicScale,y:(world.minY-classicOrigin.y)/classicScale,width:world.width/classicScale,height:world.height/classicScale)
      let down = !preview && held.contains(id)
      let hover = !preview && controlHovered(id)
      if id == 8 || id == 0 {
        let tint = handheld == .gba ? 0x316A80 : (theme == 0 ? (id == 8 ? 0xC71632 : 0x14895B) : (theme == 1 ? 0x9F164F : 0x343B3A))
        let cap=plasticKey(r,tint:tint,radius:r.width/2,down:down,hover:hover,separable:true)
        if !omitControlCaps { centered(name,cap.midX,cap.midY-10,17,color(0xFFFFFF,0.82),.semibold) }
      } else if id == 10 || id == 11 {
        let tint=[0x6C7C79,0xB8C7C0,0x85A98C][min(2,max(0,theme))]
        shoulderKey(r,right:id == 11,tint:tint,name:name,down:down,hover:hover)
      } else {
        _=plasticKey(r,tint:0x66796A,radius:7,down:down,hover:hover,separable:true)
        if handheld == .gba {
          text(name,r.maxX+9,r.minY+3,7,color(0x53654F),.semibold)
        } else {
          centered(name,r.midX,r.maxY+7,6,color(theme == 0 ? 0x8C470A : 0x56644F),.semibold)
        }
      }
    }
  }
  func drawGBABody(preview: Bool = false) {
    let body = NSBezierPath()
    body.move(to: CGPoint(x: 22, y: 7))
    body.curve(
      to: CGPoint(x: 618, y: 7), controlPoint1: CGPoint(x: 180, y: -12),
      controlPoint2: CGPoint(x: 470, y: -12))
    body.curve(
      to: CGPoint(x: 630, y: 290), controlPoint1: CGPoint(x: 650, y: 65),
      controlPoint2: CGPoint(x: 650, y: 220))
    body.curve(
      to: CGPoint(x: 10, y: 290), controlPoint1: CGPoint(x: 520, y: 368),
      controlPoint2: CGPoint(x: 110, y: 368))
    body.curve(
      to: CGPoint(x: 22, y: 7), controlPoint1: CGPoint(x: -8, y: 220),
      controlPoint2: CGPoint(x: -6, y: 66))
    body.close()
    let high = [0xFFC02C, 0x2363AD, 0x6026A0, 0xEFF2F1][min(3,max(0,theme))]
    let low = [0xD38D12, 0x123C77, 0x351257, 0xB8C4CB][min(3,max(0,theme))]
    gbaRearHousing(body,high:high,low:low)
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.4)
    shadow.shadowBlurRadius = 18
    shadow.shadowOffset = NSSize(width: 0, height: -9)
    shadow.set()
    color(low).setFill()
    body.fill()
    NSShadow().set()
    NSGradient(starting: color(high), ending: color(low))!.draw(in: body, angle: 90)
    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    // PCB traces and fasteners remain visible beneath the frosted polycarbonate.
    for i in 0..<16 {
      let y = CGFloat(40 + i * 17)
      line(
        [
          CGPoint(x: 18, y: y), CGPoint(x: 120 + CGFloat(i % 3) * 10, y: y),
          CGPoint(x: 150, y: y + 13), CGPoint(x: 490, y: y + 13), CGPoint(x: 515, y: y),
          CGPoint(x: 625, y: y),
        ], color(0x0A3027, theme == 1 ? 0.10 : 0.23), 2)
    }
    for x in [CGFloat(35), CGFloat(605)] {
      for y in [CGFloat(60), CGFloat(258)] {
        fill(CGRect(x: x, y: y, width: 14, height: 14), color(0x152C23, 0.35), 7)
        line([CGPoint(x: x + 3, y: y + 7), CGPoint(x: x + 11, y: y + 7)], color(0xB5CCC0, 0.5), 1)
      }
    }
    for i in 0..<280 {
      fill(
        CGRect(x: CGFloat((i * 149) % 635), y: CGFloat((i * 71) % 335), width: 0.8, height: 0.8),
        color(0xFFFFFF, 0.11))
    }
    NSGraphicsContext.restoreGraphicsState()
    color(0xD2E3D5, 0.45).setStroke()
    body.lineWidth = 2
    body.stroke()
    if !exportSpatialSurface {
    let slot=mediaSlots["gba"]!
    fill(CGRect(x:slot.x-40-3,y:-2,width:slot.width+6,height:slot.height+4),color(0xC7D7CF,0.3),4)
    fill(CGRect(x:slot.x-40,y:0,width:slot.width,height:slot.height),color(0x0A1713),3)
    if inserted { fill(CGRect(x:slot.x-40+(slot.width-slot.cardWidth)/2,y:-7,width:slot.cardWidth,height:8), color(selected.map {cartridgeTint($0)} ?? 0x3C4141,cartridgeShellOpacity), 2) }
    }
    fill(CGRect(x: 151, y: 23, width: 338, height: 270), color(0x0A1010), 29)
    stroke(CGRect(x: 152, y: 24, width: 336, height: 268), color(0xC7D7CF, 0.35), 28)
    classicScreen(CGRect(x: 171, y: 43, width: 298, height: 199), preview)
    centered("GAME BOY ADVANCE", 320, 259, 17, color(0xC8D6CB), .bold)
    centered("Nintendo", 320, 9, 9, color(0xD5E4D9, 0.55), .bold)
    drawCross(33, 124, 0xCD741C)
    drawClassicKeys(preview)
    fill(
      CGRect(x: 528, y: 75, width: 8, height: 8), color(running && !preview ? 0xB7F26B : 0x384B39),
      4)
    text("POWER", 542, 75, 6, color(0xBDD0BB))
    for row in 0..<6 {
      let y = CGFloat(218 + row * 11)
      fill(CGRect(x: 514, y: y, width: 76, height: 4), color(0x172D24, 0.85), 2)
      line([CGPoint(x: 516, y: y + 4), CGPoint(x: 587, y: y + 4)], color(0xD8E7DC, 0.45), 0.7)
    }
    let powerCap=plasticKey(CGRect(x:572,y:285,width:36,height:17),tint:0x344C3A,radius:7)
    powerSymbol(CGPoint(x:powerCap.midX,y:powerCap.midY),5,color(0xD8E5CF))
    text("VOL", 26, 264, 5, color(0x9BAF9E))
    let dial=plasticKey(CGRect(x:21,y:276,width:11,height:24),tint:0x536952,radius:4,down:muted)
    for y in stride(from:dial.minY+4,through:dial.maxY-3,by:4) { line([CGPoint(x:dial.minX+2,y:y),CGPoint(x:dial.maxX-2,y:y)],color(0xD1DCC6,0.45),0.7) }
  }
  func drawGBCBody(preview: Bool = false) {
    let high = [0xFFA52A, 0xE2E0CF, 0xEECB25][min(2,max(0,theme))]
    let low = [0xEA7908, 0xB2B29D, 0xD2A91A][min(2,max(0,theme))]
    gbcRearHousing(high:high,low:low)
    fill(CGRect(x: 3, y: 8, width: 350, height: 568), color(0x000000, 0.35), 28)
    gradient(CGRect(x: 0, y: 0, width: 350, height: 570), high, low, 28)
    stroke(CGRect(x: 4, y: 4, width: 342, height: 562), color(0xFFFFFF, 0.30), 25, 1.5)
    let slot=mediaSlots["gbc"]!
    fill(CGRect(x:slot.x-15,y:0,width:slot.width,height:slot.height),color(0x343B33),2)
    if inserted {
      fill(
        CGRect(x:slot.x-15+(slot.width-slot.cardWidth)/2,y:-14,width:slot.cardWidth,height:17),
        color(selected.map {cartridgeTint($0)} ?? 0xA6ABAA,cartridgeShellOpacity), 4)
    }
    let bezel = CGRect(x: 25, y: 26, width: 300, height: 274)
    gradient(bezel, theme == 1 ? 0x8A8C8C : 0x293134, 0x171F20, 14)
    stroke(bezel.insetBy(dx: 1, dy: 1), color(0x4C5753), 13)
    classicScreen(CGRect(x: 69, y: 59, width: 212, height: 191), preview)
    centered("GAME BOY", 147, 269, 15, color(0xA8B8AF), .bold)
    let letters = Array("COLOR")
    let tints = [0xD7357A, 0x615CB2, 0x7EBE34, 0xDCB929, 0x269CBA]
    for (i, letter) in letters.enumerated() {
      text(String(letter), 195 + CGFloat(i) * 13, 269, 15, color(tints[i]), .bold)
    }
    fill(
      CGRect(x: 39, y: 89, width: 5, height: 5), color(running && !preview ? 0xDB4141 : 0x633B3A), 3
    )
    text("POWER", 30, 101, 4, color(0x8F9F96))
    if theme == 0 { drawPKCDecal() }
    if theme == 1 {
      line([CGPoint(x: 38, y: 40), CGPoint(x: 124, y: 40)], color(0x722855), 2)
      line([CGPoint(x: 38, y: 44), CGPoint(x: 124, y: 44)], color(0x334775), 1)
      text("DOT MATRIX WITH STEREO SOUND", 132, 39, 5, color(0xCDD3C9))
    }
    stroke(CGRect(x: 124, y: 319, width: 102, height: 25), color(low), 12, 2)
    centered("Nintendo", 175, 324, 11, color(theme == 0 ? 0xBB660B : 0x9B9C83), .bold)
    drawCross(35, 340, theme == 0 ? 0x147DA3 : 0x303737)
    drawClassicKeys(preview)
    for row in 0..<7 {
      for col in 0..<7 {
        let x = CGFloat(250 + col * 9)
        let y = CGFloat(464 + row * 9) - CGFloat(col) * 2
        fill(CGRect(x: x, y: y, width: 3.5, height: 3.5), color(0x263B29, 0.7), 2)
      }
    }
    if theme == 0 { centered("◉ POKÉMON CENTER", 156, 535, 10, color(0x263A47), .bold) }
    let powerCap=plasticKey(CGRect(x:347,y:83,width:13,height:38),tint:0x4A5B42,radius:5)
    powerSymbol(CGPoint(x:powerCap.midX,y:powerCap.midY),4,color(0xDDE7D2))
  }
  func drawPKCDecal() {
    // Small screen-printed character motifs sit in the bezel margins.
    func eye(_ x: CGFloat, _ y: CGFloat) {
      fill(CGRect(x: x, y: y, width: 2, height: 3), color(0x182A29), 1)
    }
    func head(_ x: CGFloat, _ y: CGFloat, _ tint: Int) {
      fill(CGRect(x: x - 11, y: y - 10, width: 22, height: 21), color(0x152A28), 11)
      fill(CGRect(x: x - 10, y: y - 9, width: 20, height: 19), color(tint), 10)
      eye(x - 5, y - 2)
      eye(x + 4, y - 2)
      line([CGPoint(x: x - 2, y: y + 5), CGPoint(x: x + 2, y: y + 5)], color(0x314638), 1)
    }
    fill(CGRect(x: 38, y: 169, width: 22, height: 21), color(0xEE8734), 10)
    line(
      [CGPoint(x: 39, y: 181), CGPoint(x: 29, y: 173), CGPoint(x: 30, y: 163)], color(0xEA8A34), 5)
    fill(CGRect(x: 26, y: 158, width: 7, height: 12), color(0xE43C21), 4)
    fill(CGRect(x: 28, y: 161, width: 3, height: 7), color(0xFBDD36), 2)
    head(49, 163, 0xF19840)
    fill(CGRect(x: 37, y: 202, width: 24, height: 22), color(0x479DAA), 10)
    fill(CGRect(x: 42, y: 205, width: 15, height: 18), color(0xE1C590), 7)
    head(49, 194, 0x6FC3CF)
    fill(CGRect(x: 37, y: 236, width: 25, height: 19), color(0x3BA494), 8)
    head(48, 229, 0x5BC1A5)
    let bulb = NSBezierPath()
    bulb.move(to: CGPoint(x: 51, y: 219))
    bulb.line(to: CGPoint(x: 48, y: 204))
    bulb.line(to: CGPoint(x: 57, y: 210))
    bulb.line(to: CGPoint(x: 65, y: 208))
    bulb.line(to: CGPoint(x: 61, y: 223))
    bulb.close()
    color(0x417C49).setFill()
    bulb.fill()
    fill(CGRect(x: 42, y: 235, width: 4, height: 3), color(0x247D70), 1)
    let ears = NSBezierPath()
    for points in [
      [CGPoint(x: 291, y: 251), CGPoint(x: 284, y: 227), CGPoint(x: 299, y: 244)],
      [CGPoint(x: 305, y: 246), CGPoint(x: 319, y: 225), CGPoint(x: 314, y: 254)],
    ] {
      ears.move(to: points[0])
      ears.line(to: points[1])
      ears.line(to: points[2])
      ears.close()
    }
    color(0xEECF36).setFill()
    ears.fill()
    line([CGPoint(x: 284, y: 227), CGPoint(x: 289, y: 237)], color(0x27362C), 4)
    line([CGPoint(x: 319, y: 225), CGPoint(x: 316, y: 237)], color(0x27362C), 4)
    fill(CGRect(x: 289, y: 258, width: 29, height: 29), color(0xECCD35), 12)
    head(302, 254, 0xF1D948)
    for x in [CGFloat(293), CGFloat(310)] {
      fill(CGRect(x: x, y: 257, width: 4, height: 4), color(0xD94931), 2)
    }
  }
  func drawClassicCard(_ game: Game, _ r: CGRect, _ highlighted: Bool) {
    let wide = handheld == .gba
    let w: CGFloat = wide ? 180 : 132
    let h: CGFloat = wide ? 104 : 150
    NSGraphicsContext.saveGraphicsState()
    let tr = NSAffineTransform()
    tr.translateX(by: r.minX, yBy: r.minY)
    tr.scaleX(by: r.width / w, yBy: r.height / h)
    tr.concat()
    let shell = cartridgeTint(game)
    let ink = cartridgeInk(shell)
    fill(CGRect(x: 0, y: 3, width: w, height: h - 3), color(0x000000, 0.4), 8)
    translucentCartridge(NSBezierPath(roundedRect:CGRect(x:1,y:0,width:w-2,height:h-5),xRadius:7,yRadius:7),tint:shell)
    stroke(
      CGRect(x: 2, y: 1, width: w - 4, height: h - 7), color(highlighted ? 0xE6D4A5 : 0x717D77), 6,
      highlighted ? 1.8 : 0.6)
    if wide {
      fill(CGRect(x: 4, y: 1, width: 21, height: 12), keyColor(shell,-0.30).withAlphaComponent(0.6), 2)
      fill(CGRect(x: w - 25, y: 1, width: 21, height: 12), keyColor(shell,-0.30).withAlphaComponent(0.6), 2)
      centered("GAME BOY ADVANCE", w / 2, 8, 7, ink, .bold)
    } else {
      fill(CGRect(x: 7, y: 10, width: w - 14, height: 22), color(0xFFFFFF, 0.08), 5)
      centered("GAME BOY", w / 2, 16, 10, ink, .bold)
      for y in [CGFloat(38), CGFloat(44), CGFloat(50)] {
        line([CGPoint(x: 3, y: y), CGPoint(x: 14, y: y)], ink.withAlphaComponent(0.4), 1)
        line([CGPoint(x: w - 14, y: y), CGPoint(x: w - 3, y: y)], ink.withAlphaComponent(0.4), 1)
      }
    }
    let label =
      wide
      ? CGRect(x: 21, y: 26, width: 138, height: 62) : CGRect(x: 17, y: 43, width: 98, height: 88)
    fill(label.insetBy(dx: -2, dy: -2), color(0x222D28), 4)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: label, xRadius: 2, yRadius: 2).addClip()
    if let image = game.cover {
      image.draw(in: label)
    } else {
      fill(label, color(0xD3D9BE))
      centered(game.title, w / 2, label.midY - 4, 9, color(0x28382C), .bold)
    }
    NSGraphicsContext.restoreGraphicsState()
    centered(wide ? "AGB-002" : "CGB-002", w / 2, h - 13, 5, ink, .bold)
    NSGraphicsContext.restoreGraphicsState()
  }
  func drawClassicFlyingCard() {
    guard phase == .inserting, let game = selected else { return }
    let time = CGFloat(min(1, (CACurrentMediaTime() - stageStart) / 1.2))
    let t = smooth(min(1, time / 0.65))
    let source = cardRect(selectedIndex)
    let slot=mediaSlots[handheld.rawValue]!
    let width = mix(source.width,slot.cardWidth*classicScale,t)
    let height = width * slot.ratio
    var y = mix(source.minY, classicOrigin.y - height - 10, t) - sin(t * CGFloat.pi) * 25
    if time > 0.65 { y += smooth((time - 0.65) / 0.35) * (height + 8) }
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: CGRect(x: 0, y: 0, width: 720, height: classicOrigin.y + 4)).addClip()
    drawClassicCard(
      game, CGRect(x: mix(source.midX, 360, t) - width / 2, y: y, width: width, height: height),
      false)
    NSGraphicsContext.restoreGraphicsState()
  }
}
