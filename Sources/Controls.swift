import Cocoa

extension StudioView {
  func keyColor(_ tint: Int, _ white: CGFloat) -> NSColor {
    color(tint).blended(withFraction: abs(white), of: white >= 0 ? .white : .black) ?? color(tint)
  }
  func controlHovered(_ id: Int) -> Bool {
    guard hoverLabel != nil, !choosing else { return false }
    return (buttons + dpad).contains { $0.1 == id && displayRect($0.2.offsetBy(dx: -240, dy: 0)).contains(hoverPoint) }
  }
  @discardableResult
  func plasticKey(_ r: CGRect, tint: Int, radius: CGFloat, down: Bool = false, hover: Bool = false, separable:Bool = false) -> CGRect {
    let cap = r.offsetBy(dx: 0, dy: down ? 2.5 : -1.5)
    // Socket, sidewall and cap are separate surfaces, so a press actually reduces travel.
    fill(r.insetBy(dx: -2.5, dy: -2).offsetBy(dx: 0, dy: 2), color(0x080C0D, 0.82), radius + 2)
    stroke(r.insetBy(dx: -3, dy: -2.5).offsetBy(dx: 0, dy: 2), color(0xFFFFFF, 0.12), radius + 2, 0.7)
    if omitControlCaps && separable { return cap }
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, down ? 0.2 : 0.48)
    shadow.shadowBlurRadius = down ? 1 : 4
    shadow.shadowOffset = NSSize(width: 0, height: -3)
    shadow.set()
    fill(r.offsetBy(dx: 0, dy: 4), keyColor(tint, -0.55), radius)
    NSGraphicsContext.restoreGraphicsState()
    let path = NSBezierPath(roundedRect: cap, xRadius: radius, yRadius: radius)
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(colorsAndLocations:
      (keyColor(tint, down ? 0.08 : 0.35), 0),
      (keyColor(tint, down ? -0.03 : 0.11), 0.27),
      (keyColor(tint, -0.06), 0.65),
      (keyColor(tint, down ? -0.25 : -0.29), 1))?.draw(in: cap, angle: 90)
    let gloss = CGRect(x: cap.minX + cap.width * 0.12, y: cap.minY + 1, width: cap.width * 0.76, height: cap.height * 0.42)
    color(0xFFFFFF, down ? 0.025 : 0.11).setFill()
    NSBezierPath(ovalIn: gloss).fill()
    let rim = NSBezierPath(roundedRect: cap.insetBy(dx: 1.2, dy: 1.2), xRadius: max(1, radius - 1), yRadius: max(1, radius - 1))
    color(0xFFFFFF, down ? 0.12 : 0.30).setStroke(); rim.lineWidth = 0.8; rim.stroke()
    NSGraphicsContext.restoreGraphicsState()
    stroke(cap, keyColor(tint, -0.52), radius, 0.9)
    if hover { stroke(r.insetBy(dx: -3.5, dy: -3).offsetBy(dx: 0, dy: 2), color(0xD4E3C7, 0.65), radius + 3, 1) }
    return cap
  }
  func plasticDpad(_ r: CGRect, tint: Int, preview: Bool = false) {
    let w = r.width / 3
    // One rigid cap rotates around a central pivot. Opposite directions cancel.
    let vertical:CGFloat = preview ? 0:CGFloat((held.contains(5) ? 1:0)-(held.contains(4) ? 1:0))
    let horizontal:CGFloat = preview ? 0:CGFloat((held.contains(7) ? 1:0)-(held.contains(6) ? 1:0))
    let length=max(1,sqrt(vertical*vertical+horizontal*horizontal))
    let rx = -vertical/length*0.14, ry = -horizontal/length*0.14
    func project(_ x:CGFloat,_ y:CGFloat,_ z:CGFloat)->CGPoint {
      let px=x-r.midX,py=y-r.midY
      let yy=py*cos(rx)-z*sin(rx), zz=py*sin(rx)+z*cos(rx)
      let xx=px*cos(ry)+zz*sin(ry), depth = -px*sin(ry)+zz*cos(ry)
      let perspective=500/(500-depth)
      return CGPoint(x:r.midX+xx*perspective,y:r.midY+yy*perspective-depth*0.38)
    }
    let p = NSBezierPath()
    p.move(to: CGPoint(x: r.minX + w, y: r.minY))
    for q in [CGPoint(x:2*w,y:0),CGPoint(x:2*w,y:w),CGPoint(x:3*w,y:w),CGPoint(x:3*w,y:2*w),CGPoint(x:2*w,y:2*w),CGPoint(x:2*w,y:3*w),CGPoint(x:w,y:3*w),CGPoint(x:w,y:2*w),CGPoint(x:0,y:2*w),CGPoint(x:0,y:w),CGPoint(x:w,y:w)] {
      p.line(to: CGPoint(x:r.minX+q.x,y:r.minY+q.y))
    }
    p.close(); p.lineJoinStyle = .round
    func moved(_ dy: CGFloat) -> NSBezierPath {
      let copy = p.copy() as! NSBezierPath
      let t = AffineTransform(translationByX: 0, byY: dy); copy.transform(using: t)
      return copy
    }
    let socket = moved(3)
    color(0x060A0B, 0.82).setStroke(); socket.lineWidth = 6; socket.stroke()
    if omitControlCaps { return }
    let vertices=[CGPoint(x:w,y:0),CGPoint(x:2*w,y:0),CGPoint(x:2*w,y:w),CGPoint(x:3*w,y:w),CGPoint(x:3*w,y:2*w),CGPoint(x:2*w,y:2*w),CGPoint(x:2*w,y:3*w),CGPoint(x:w,y:3*w),CGPoint(x:w,y:2*w),CGPoint(x:0,y:2*w),CGPoint(x:0,y:w),CGPoint(x:w,y:w)].map{CGPoint(x:r.minX+$0.x,y:r.minY+$0.y)}
    let top=vertices.map{project($0.x,$0.y,5)},bottom=vertices.map{project($0.x,$0.y,-4)}
    func polygon(_ points:[CGPoint])->NSBezierPath {let path=NSBezierPath();path.move(to:points[0]);for point in points.dropFirst(){path.line(to:point)};path.close();path.lineJoinStyle = .round;return path}
    // Draw the extrusion before the face; all grooves share the same transform.
    for i in vertices.indices {let j=(i+1)%vertices.count;let side=polygon([bottom[i],bottom[j],top[j],top[i]]);keyColor(tint,-0.5).setFill();side.fill()}
    let face=polygon(top)
    NSGraphicsContext.saveGraphicsState();face.addClip()
    NSGradient(colorsAndLocations:(keyColor(tint,0.33),0),(keyColor(tint,0.06),0.35),(keyColor(tint,-0.22),1))?.draw(in:r.insetBy(dx:-8,dy:-8),angle:90)
    NSGraphicsContext.restoreGraphicsState()
    keyColor(tint,-0.55).setStroke();face.lineWidth=1;face.stroke()
    for (a,b) in [(CGPoint(x:r.midX,y:r.minY+w*0.27),CGPoint(x:r.midX,y:r.minY+w*0.73)),(CGPoint(x:r.midX,y:r.minY+w*2.27),CGPoint(x:r.midX,y:r.minY+w*2.73)),(CGPoint(x:r.minX+w*0.27,y:r.midY),CGPoint(x:r.minX+w*0.73,y:r.midY)),(CGPoint(x:r.minX+w*2.27,y:r.midY),CGPoint(x:r.minX+w*2.73,y:r.midY))] {
      line([project(a.x,a.y,5),project(b.x,b.y,5)],keyColor(tint,-0.46),2.2)
      line([project(a.x,a.y+1,5),project(b.x,b.y+1,5)],color(0xFFFFFF,0.2),0.7)
    }
    let center=project(r.midX,r.midY,5),dimple=CGRect(x:center.x-4,y:center.y-4,width:8,height:8)
    fill(dimple,keyColor(tint,-0.22),4);stroke(dimple,color(0xFFFFFF,0.12),4,0.7)
    if !preview && [4,5,6,7].contains(where:{controlHovered($0)}) {color(0xD4E3C7,0.55).setStroke();face.lineWidth=1.5;face.stroke()}
  }
  func drawMachineNavigation() {
    let r = toolbar(2)
    let hover = r.contains(hoverPoint) && hoverLabel != nil
    fill(r, color(hover ? 0x39483C : 0x2D3931), 12)
    stroke(r, color(hover ? 0xB6C7A9 : 0x7A8F78), 12, 1)
    line([CGPoint(x:r.minX+18,y:r.midY-5),CGPoint(x:r.minX+13,y:r.midY),CGPoint(x:r.minX+18,y:r.midY+5)],color(0xD3DFC9),1.8)
    let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
    (handheld.name + " · " + handheld.editions[theme] as NSString).draw(in:CGRect(x:r.minX+30,y:r.minY+12,width:r.width-44,height:20),withAttributes:[.font:NSFont.systemFont(ofSize:12,weight:.semibold),.foregroundColor:color(0xE0E6D8),.paragraphStyle:style])
  }

}

extension StudioView {
  func shoulderKey(_ r: CGRect, right: Bool, tint: Int, name: String, down: Bool, hover: Bool) {
    NSGraphicsContext.saveGraphicsState()
    let t=NSAffineTransform()
    t.translateX(by:right ? r.maxX : r.minX,yBy:r.minY)
    if right {t.scaleX(by:-1,yBy:1)}
    t.concat()
    let w=r.width,h=r.height
    let p=NSBezierPath()
    p.move(to:CGPoint(x:13,y:1))
    p.curve(to:CGPoint(x:w-5,y:3),controlPoint1:CGPoint(x:w*0.4,y:-3),controlPoint2:CGPoint(x:w*0.85,y:1))
    p.line(to:CGPoint(x:w-1,y:h-9))
    p.curve(to:CGPoint(x:w-10,y:h-2),controlPoint1:CGPoint(x:w,y:h-3),controlPoint2:CGPoint(x:w-4,y:h-2))
    p.line(to:CGPoint(x:5,y:h))
    p.curve(to:CGPoint(x:0,y:h-13),controlPoint1:CGPoint(x:-1,y:h-1),controlPoint2:CGPoint(x:0,y:h-8))
    p.curve(to:CGPoint(x:13,y:1),controlPoint1:CGPoint(x:1,y:7),controlPoint2:CGPoint(x:5,y:2))
    p.close()
    // An inset seam follows the curved rear housing; the trigger pivots into this cutout.
    color(0x07100C,0.8).setStroke();p.lineWidth=3;p.stroke()
    if omitControlCaps { NSGraphicsContext.restoreGraphicsState();return }
    let wall=p.copy() as! NSBezierPath
    wall.transform(using:AffineTransform(translationByX:0,byY:down ? 2 : 4))
    keyColor(tint,-0.45).setFill();wall.fill()
    let face=p.copy() as! NSBezierPath
    face.transform(using:AffineTransform(translationByX:0,byY:down ? 2 : 0))
    NSGradient(starting:keyColor(tint,0.14),ending:keyColor(tint,-0.16))?.draw(in:face,angle:90)
    keyColor(tint,-0.3).setStroke();face.lineWidth=0.7;face.stroke()
    line([CGPoint(x:13,y:3),CGPoint(x:w-8,y:5)],color(0xFFFFFF,down ? 0.12 : 0.32),0.9)
    for i in 0..<3 {
      let x=CGFloat(9+i*4)
      line([CGPoint(x:x,y:h-13),CGPoint(x:x+1,y:h-7)],keyColor(tint,-0.18),0.7)
    }
    if hover {color(0xD8E3CE,0.55).setStroke();face.lineWidth=1;face.stroke()}
    NSGraphicsContext.restoreGraphicsState()
    centered(name,r.midX,r.midY-6+(down ? 2 : 0),9,cartridgeInk(tint).withAlphaComponent(0.85),.semibold)
  }
  func gbaRearHousing(_ body: NSBezierPath, high: Int, low: Int) {
    let lower=body.copy() as! NSBezierPath
    lower.transform(using:AffineTransform(translationByX:0,byY:6))
    keyColor(low,-0.34).setFill();lower.fill()
    let rear=body.copy() as! NSBezierPath
    rear.transform(using:AffineTransform(translationByX:0,byY:-11))
    NSGradient(starting:keyColor(high,-0.12),ending:keyColor(low,-0.28))?.draw(in:rear,angle:90)
    color(0xFFFFFF,0.16).setStroke();rear.lineWidth=1;rear.stroke()
    line([CGPoint(x:117,y:-4),CGPoint(x:248,y:-10)],color(0x0C1C15,0.7),1)
    line([CGPoint(x:392,y:-10),CGPoint(x:523,y:-4)],color(0x0C1C15,0.7),1)
    if !exportSpatialSurface {fill(CGRect(x:252,y:-12,width:136,height:9),color(0x08110D),3)}
    stroke(CGRect(x:250,y:-13,width:140,height:12),keyColor(high,-0.25),3,1)
  }
  func gbcRearHousing(high: Int, low: Int) {
    gradient(CGRect(x:2,y:-12,width:346,height:62),high,low,24)
    stroke(CGRect(x:3,y:-11,width:344,height:58),color(0xFFFFFF,0.24),23,1)
    let side=NSBezierPath()
    side.move(to:CGPoint(x:337,y:8));side.line(to:CGPoint(x:359,y:28));side.line(to:CGPoint(x:359,y:531));side.line(to:CGPoint(x:336,y:565));side.close()
    NSGradient(starting:keyColor(low,-0.12),ending:keyColor(low,-0.42))?.draw(in:side,angle:0)
    line([CGPoint(x:355,y:35),CGPoint(x:355,y:531)],color(0xFFFFFF,0.13),0.7)
    fill(CGRect(x:76,y:-14,width:198,height:16),keyColor(low,-0.45),4)
    fill(CGRect(x:84,y:-11,width:182,height:7),color(0x090F0B),2)
  }
}


extension StudioView {
  var focusedPixelsRect:CGRect {
    guard let frame=videoFrame else{return .zero}
    let rotated=handheld == .nds && bookMode
    let imageSize=CGSize(width:rotated ? frame.height:frame.width,height:rotated ? frame.width:frame.height)
    let area=CGRect(x:24,y:78,width:672,height:canvasHeight-102),q=min(area.width/imageSize.width,area.height/imageSize.height)
    return CGRect(x:area.midX-imageSize.width*q/2,y:area.midY-imageSize.height*q/2,width:imageSize.width*q,height:imageSize.height*q)
  }
  var focusedTouchRect:CGRect {
    let r=focusedPixelsRect
    if handheld == .nds && bookMode{return CGRect(x:r.midX,y:r.minY,width:r.width/2,height:r.height)}
    return CGRect(x:r.minX+(handheld == .n3ds ? r.width*0.1:0),y:r.midY,width:r.width*(handheld == .n3ds ? 0.8:1),height:r.height/2)
  }
  func drawFocusedPixels(){
    guard let frame=videoFrame else{return}
    let rect=focusedPixelsRect;fill(rect.insetBy(dx:-5,dy:-5),color(0x080C0D),5)
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current?.imageInterpolation = .none
    if handheld == .nds && bookMode {let t=NSAffineTransform();t.translateX(by:rect.midX,yBy:rect.midY);t.rotate(byDegrees:-90);t.concat();NSImage(cgImage:frame,size:CGSize(width:frame.width,height:frame.height)).draw(in:CGRect(x:-rect.height/2,y:-rect.width/2,width:rect.height,height:rect.width))}
    else{NSImage(cgImage:frame,size:CGSize(width:frame.width,height:frame.height)).draw(in:rect)}
    NSGraphicsContext.restoreGraphicsState()
  }
  func touchFocused(_ p:CGPoint,_ down:Bool){
    let r=focusedPixelsRect
    guard r.width>0,r.height>0 else{return}
    var u=(p.x-r.minX)/r.width,v=(p.y-r.minY)/r.height
    if handheld == .nds && bookMode{(u,v)=(1-v,u)}
    let inside=u>=0 && u<=1 && v>=0.5 && v<=1 && (handheld != .n3ds || (u>=0.1 && u<=0.9))
    if handheld == .n3ds{u=(u-0.1)/0.8}
    touch(CGPoint(x:bottom.minX+u*bottom.width,y:bottom.minY+(v-0.5)*2*bottom.height),down && inside)
  }
  @objc func showDisplaySettings(_ sender:Any?){
    guard ![Phase.inserting,.opening,.closing,.focusing].contains(phase) else{return}
    releaseAll();let controller=NSViewController(),stack=NSStackView();stack.orientation = .vertical;stack.spacing=10;stack.edgeInsets=NSEdgeInsets(top:18,left:18,bottom:18,right:18);stack.alignment = .leading
    let title=NSTextField(labelWithString:"显示调整");title.font = .systemFont(ofSize:16,weight:.semibold);stack.addArrangedSubview(title)
    let focus=NSButton(checkboxWithTitle:"画面优先（隐藏机身）",target:self,action:#selector(changeDisplayMode(_:)));focus.state=UserDefaults.standard.bool(forKey:displayKey+".focus") ? .on:.off;stack.addArrangedSubview(focus)
    for (index,name) in ["大小","左右位置","上下位置"].enumerated(){let label=NSTextField(labelWithString:name);stack.addArrangedSubview(label);let suffix=[".zoom",".x",".y"][index];let fallback=index==0 ? 1.0:0.5;let value=UserDefaults.standard.object(forKey:displayKey+suffix)==nil ? fallback:UserDefaults.standard.double(forKey:displayKey+suffix);let slider=NSSlider(value:value,minValue:index==0 ? 0.55:0,maxValue:index==0 ? 2:1,target:self,action:#selector(changeDisplayValue(_:)));slider.tag=index;slider.isContinuous=true;slider.widthAnchor.constraint(equalToConstant:300).isActive=true;stack.addArrangedSubview(slider)}
    let note=NSTextField(wrappingLabelWithString:"画面优先时使用键盘与触屏操作。保持比例并限制在可见范围；放大窗口或全屏可显示更大的画面。");note.font = .systemFont(ofSize:11);note.textColor = .secondaryLabelColor;note.widthAnchor.constraint(equalToConstant:300).isActive=true;stack.addArrangedSubview(note)
    let reset=NSButton(title:"恢复默认布局",target:self,action:#selector(resetDisplaySettings(_:)));stack.addArrangedSubview(reset)
    controller.view=stack;let popover=NSPopover();popover.contentViewController=controller;popover.behavior = .transient;popover.contentSize=NSSize(width:340,height:380);displayPopover=popover
    let r=toolbar(4);popover.show(relativeTo:NSRect(x:offset.x+r.minX*scale,y:offset.y+r.minY*scale,width:r.width*scale,height:r.height*scale),of:self,preferredEdge:.maxY)
  }
  @objc func changeDisplayValue(_ sender:NSSlider){UserDefaults.standard.set(sender.doubleValue,forKey:displayKey+[".zoom",".x",".y"][sender.tag]);tooltipSignature="";window?.invalidateCursorRects(for:self);needsDisplay=true}
  @objc func changeDisplayMode(_ sender:NSButton){UserDefaults.standard.set(sender.state == .on,forKey:displayKey+".focus");tooltipSignature="";needsDisplay=true}
  @objc func resetDisplaySettings(_ sender:NSButton){for suffix in [".zoom",".x",".y",".focus"]{UserDefaults.standard.removeObject(forKey:displayKey+suffix)};displayPopover?.performClose(nil);tooltipSignature="";needsDisplay=true}
}
