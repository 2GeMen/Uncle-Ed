import UIKit

// One policy for physical keys and media handling. Never pulse on every frame
// or every stick movement; one event represents one mechanical transition.
enum PhoneHaptics {
    private static let key=UIImpactFeedbackGenerator(style:.medium)
    private static let latch=UIImpactFeedbackGenerator(style:.rigid)
    private static let release=UIImpactFeedbackGenerator(style:.soft)
    private static let selection=UISelectionFeedbackGenerator()
    static var enabled:Bool{UIDevice.current.userInterfaceIdiom == .phone && (UserDefaults.standard.object(forKey:"controls.haptics") as? Bool ?? true)}
    #if DEBUG
    private(set) static var counts:[String:Int]=[:]
    private static func record(_ name:String){counts[name,default:0]+=1}
    #else
    private static func record(_ name:String){}
    #endif
    static func press(){guard enabled else{return};key.impactOccurred(intensity:0.55);key.prepare();record("key")}
    static func pickUp(){guard enabled else{return};selection.selectionChanged();selection.prepare();latch.prepare();record("mediaPickup")}
    static func seat(disc:Bool){guard enabled else{return};latch.impactOccurred(intensity:disc ? 0.64:0.72);release.prepare();record(disc ? "discLatched":"cartridgeSeated")}
    static func eject(){guard enabled else{return};release.impactOccurred(intensity:0.68);release.prepare();record("mediaEject")}
}

extension UIColor {
    convenience init(hex:UInt32,alpha:CGFloat=1){self.init(red:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:alpha)}
}
extension UIImage {
    func drawAspectFit(in rect:CGRect){let scale=min(rect.width/size.width,rect.height/size.height);draw(in:CGRect(x:rect.midX-size.width*scale/2,y:rect.midY-size.height*scale/2,width:size.width*scale,height:size.height*scale))}
}

// The shell, print, key caps and hinge faces come from the Mac renderer, not a second skin design.
final class MachineCanvas:UIView {
    private static let images=NSCache<NSString,UIImage>()
    static func skin(_ model:DeviceModel,_ theme:Int,_ part:String)->UIImage? {
        let name="\(model.rawValue)-\(theme)-\(part)"
        if let image=images.object(forKey:name as NSString){return image}
        guard let path=Bundle.main.url(forResource:name,withExtension:"png",subdirectory:"Assets/Skins/MobileRenders"),let image=UIImage(contentsOfFile:path.path) else{return nil}
        images.totalCostLimit=96*1024*1024;images.setObject(image,forKey:name as NSString,cost:Int(image.size.width*image.size.height*4));return image
    }
    static func preview(model:DeviceModel,theme:Int)->UIImage {
        if let path=Bundle.main.url(forResource:model.rawValue+"-"+String(theme),withExtension:"png",subdirectory:"Assets/Skins/ThemePreviews"),let image=UIImage(contentsOfFile:path.path){return UIGraphicsImageRenderer(size:CGSize(width:210,height:132)).image{_ in image.draw(in:CGRect(x:0,y:0,width:210,height:132))}}
        return         UIGraphicsImageRenderer(size:CGSize(width:210,height:132)).image{_ in
            let closed=skin(model,theme,model == .psp ? "back":model == .nds || model == .n3ds ? "outer":"front")
            closed?.drawAspectFit(in:CGRect(x:8,y:2,width:194,height:model == .gbc || model == .gba ? 128:90))
            if model == .psp || model == .nds || model == .n3ds {skin(model,theme,"front")?.drawAspectFit(in:CGRect(x:101,y:62,width:103,height:66))}
        }
    }
    var displayZoom:CGFloat=1 {didSet{updateGeometry()}}
    var horizontalPosition:CGFloat=0.5 {didSet{updateGeometry()}}
    var screenFirst=false {didSet{cancelTouches();updateGeometry()}}
    var verticalPosition:CGFloat=0.58 {didSet{updateGeometry()}}
    var bookMode=false {didSet{updateGeometry()}}
    var model:DeviceModel = .nds {didSet{cancelTouches();configure()}}
    var theme=0 {didSet{configure()}}
    var libraryMode=false {didSet{if libraryMode{spatial.clearMedia()};updateGeometry()}}
    var playing=false {didSet{updateGeometry()}}
    var openness:CGFloat=0 {didSet{updateGeometry()}}
    var loadingProgress:CGFloat=0 {didSet{updateGeometry()}}
    var frameImage:CGImage? {didSet{updateScreens()}}
    var onButton:((GameControl,Bool)->Void)?
    var onAxis:((CGFloat,CGFloat)->Void)?
    var onTouch:((CGFloat,CGFloat,Bool)->Void)?
    var onUtility:((Int)->Void)?
    var onPower:(()->Void)?
    var screenBrightness:CGFloat=1 {didSet{for image in screens{image.alpha=screenBrightness}}}
    var loadedMediaImage:UIImage? {didSet{loadedDisc.image=loadedMediaImage}}
    private let cavity=UIImageView(),hatch=UIImageView(),loadedDisc=UIImageView(),powerLED=UIView(),cardSlot=UIView()
    private let screenFirstSurface=ScreenFirstSurface()
    var usesScreenLayout:Bool{(UIDevice.current.userInterfaceIdiom == .pad && screenFirst) && playing && openness>=0.999}
    var screenFirstLayout:ScreenFirstLayout{ScreenFirstLayout(model:model,viewport:bounds.size,topInset:safeAreaInsets.top,bottomInset:safeAreaInsets.bottom,leftInset:safeAreaInsets.left,rightInset:safeAreaInsets.right,zoom:min(1,displayZoom),x:horizontalPosition,y:verticalPosition)}
    var activeGeometry:DeviceGeometry{
        if usesScreenLayout{return screenFirstLayout.geometry}
        var g=layout.geometry
        if playing && (model == .psp || model == .gba){for (key,rect) in spatial.physicalShoulderRects(){g.controls[key]=spatial.convert(rect,to:scene)}}
        return g
    }
    private let scene=UIView(),front=UIImageView(),rear=UIImageView(),base=UIImageView(),lid=UIView(),inner=UIImageView(),outer=UIImageView(),stick=StickView()
    let spatial=SpatialCanvas()
    private let mechanicalKeys=MechanicalKeys(), screenKeys=MechanicalKeys()
    private var screens=[UIImageView(),UIImageView()]
    private var hapticFingers=Set<Int>()
    var hapticsEnabled:Bool{UserDefaults.standard.object(forKey:"controls.haptics") as? Bool ?? true}
    private var router=TouchInputRouter(),ids:[ObjectIdentifier:Int]=[:],nextID=0
    var layout:MobileLayout {
        let result=MobileLayout(model:model,viewport:bounds.size,topInset:safeAreaInsets.top,bottomInset:safeAreaInsets.bottom,rotated:bookMode,verticalPosition:verticalPosition,zoom:displayZoom,horizontalPosition:horizontalPosition,nativePhone:UIDevice.current.userInterfaceIdiom == .phone,leftInset:safeAreaInsets.left,rightInset:safeAreaInsets.right,immersiveWidePad:UIDevice.current.userInterfaceIdiom == .pad)
        let mediaHeight:CGFloat=model == .psp ? 278*SpatialMachine.mediaScale("psp"):(CartridgeSlot.load(model)?.cardWidth ?? 148)*(CartridgeSlot.load(model)?.ratio ?? 1)
        let area=CGRect(x:safeAreaInsets.left+12,y:safeAreaInsets.top+(UIDevice.current.userInterfaceIdiom == .phone ? 8:72),width:max(1,bounds.width-safeAreaInsets.left-safeAreaInsets.right-24),height:max(1,bounds.height-safeAreaInsets.top-safeAreaInsets.bottom-(UIDevice.current.userInterfaceIdiom == .phone ? 16:88)))
        let start=SpatialMachine.loadingFrame(model:model.rawValue,size:result.geometry.size,available:area,maxScale:result.scale,mediaHeight:mediaHeight)
        let t:CGFloat=playing ? openness*openness*(3-2*openness):0
        var presentation=result
        presentation.frame=CGRect(x:start.minX+(result.frame.minX-start.minX)*t,y:start.minY+(result.frame.minY-start.minY)*t,width:start.width+(result.frame.width-start.width)*t,height:start.height+(result.frame.height-start.height)*t)
        presentation.scale=presentation.frame.width/(bookMode ? result.geometry.size.height:result.geometry.size.width)
        return presentation
    }

    override init(frame:CGRect){
        super.init(frame:frame);isMultipleTouchEnabled=true;backgroundColor=UIColor(hex:0x191E1D)
        addSubview(scene);scene.isUserInteractionEnabled=false
        for view in [rear,front,base,lid] {scene.addSubview(view);view.layer.isDoubleSided=false}
        scene.addSubview(cardSlot);cardSlot.backgroundColor=UIColor(hex:0x07090A);cardSlot.layer.cornerRadius=2
        rear.addSubview(cavity);rear.addSubview(loadedDisc);rear.addSubview(hatch);cavity.isHidden=true;hatch.isHidden=true
        lid.layer.isDoubleSided=true;lid.addSubview(outer);lid.addSubview(inner);inner.layer.isDoubleSided=false;outer.layer.isDoubleSided=false
        for image in screens {image.layer.magnificationFilter = .nearest;image.layer.minificationFilter = .nearest;image.isUserInteractionEnabled=false}
        front.addSubview(screens[0]);base.addSubview(screens[1]);inner.addSubview(screens[0]);base.addSubview(stick)
        addSubview(spatial)
        addSubview(screenFirstSurface);screenFirstSurface.isHidden=true
        configure()
    }
    required init?(coder:NSCoder){fatalError()}
    override func layoutSubviews(){super.layoutSubviews();updateGeometry()}
    private func configure(){
        front.image=Self.skin(model,theme,"body") ?? Self.skin(model,theme,"front");rear.image=Self.skin(model,theme,"back");base.image=Self.skin(model,theme,"base-body") ?? Self.skin(model,theme,"base")
        cavity.image=Self.skin(model,theme,"door")
        if model == .psp,let cg=rear.image?.cgImage {
            let q=CGFloat(cg.width)/720
            if let crop=cg.cropping(to:CGRect(x:219*q,y:30*q,width:282*q,height:268*q)){hatch.image=UIImage(cgImage:crop)}
        }
        inner.image=Self.skin(model,theme,"inner");outer.image=Self.skin(model,theme,"outer")
        let dual=model == .nds || model == .n3ds
        (dual ? base:front).addSubview(powerLED)
        if dual {inner.addSubview(screens[0]);base.addSubview(screens[1]);base.addSubview(stick)}else{front.addSubview(screens[0]);front.addSubview(stick)}
        (dual ? base:front).addSubview(mechanicalKeys)
        mechanicalKeys.configure(model:model,theme:theme,geometry:layout.geometry)
        screenFirstSurface.addSubview(screenKeys)
        spatial.configure(model:model,theme:theme)
        stick.silver=model == .psp && theme==0;updateGeometry();updateScreens()
    }
    private func updateGeometry(){
        screenFirstSurface.frame=bounds;screenFirstSurface.isHidden = !usesScreenLayout;scene.isHidden=usesScreenLayout
        if usesScreenLayout {screenFirstSurface.update(model:model,theme:theme,geometry:screenFirstLayout.geometry,image:frameImage);var geometry=screenFirstLayout.geometry;geometry.size=bounds.size;screenKeys.frame=bounds;screenKeys.configure(model:model,theme:theme,geometry:geometry);screenKeys.setHeld(screenFirstSurface.held);return}
        let l=layout,g=l.geometry,dual=model == .nds || model == .n3ds
        CATransaction.begin();CATransaction.setDisableActions(true)
        scene.bounds=CGRect(origin:.zero,size:g.size);scene.center=CGPoint(x:l.frame.midX,y:l.frame.midY);scene.transform=CGAffineTransform(scaleX:l.scale,y:l.scale).rotated(by:bookMode ? -.pi/2:0)
        mechanicalKeys.frame=scene.bounds
        front.frame=scene.bounds;rear.frame=scene.bounds;base.frame=scene.bounds
        loadedDisc.frame=CGRect(x:271,y:83,width:178,height:178);loadedDisc.isHidden=model != .psp || loadingProgress<0.72
        cavity.frame=scene.bounds;let cavityMask=CAShapeLayer();cavityMask.path=UIBezierPath(roundedRect:CGRect(x:219,y:30,width:282,height:268),cornerRadius:15).cgPath;cavity.layer.mask=cavityMask
        let door=sin(loadingProgress * .pi);cavity.isHidden=model != .psp || door<0.001;hatch.isHidden=cavity.isHidden
        hatch.bounds=CGRect(x:0,y:0,width:282,height:268);hatch.layer.anchorPoint=CGPoint(x:0.5,y:1);hatch.layer.position=CGPoint(x:360,y:298)
        var doorTransform=CATransform3DIdentity;doorTransform.m34 = -1/1000;hatch.layer.transform=CATransform3DRotate(doorTransform,-door * .pi * 0.43,1,0,0)
        front.isHidden=dual;rear.isHidden=model != .psp;base.isHidden = !dual;lid.isHidden = !dual
        var perspective=CATransform3DIdentity;perspective.m34 = -1/1800
        if model == .psp {
            front.layer.transform=CATransform3DRotate(perspective,(1-openness) * .pi,0,1,0)
            rear.layer.transform=CATransform3DRotate(perspective,-openness * .pi,0,1,0)
        }else{front.layer.transform=CATransform3DIdentity;rear.layer.transform=CATransform3DIdentity}
        if dual {
            let projection=LidProjection(openness:openness)
            // Project the two faces onto the Mac renderer's identical four corners.
            // Culling the parent at 180° hid the outer face in the previous port.
            let topWidth:CGFloat=projection.inner ? projection.farWidth:640
            let bottomWidth:CGFloat=projection.inner ? 640:projection.farWidth
            let topY:CGFloat=projection.inner ? projection.farY:360
            let bottomY:CGFloat=projection.inner ? 360:projection.farY
            let ratio=topWidth/bottomWidth,topLeft=360-topWidth/2,bottomLeft=360-bottomWidth/2
            lid.bounds=CGRect(x:0,y:0,width:640,height:330);lid.layer.anchorPoint = .zero;lid.layer.position=CGPoint(x:topLeft,y:topY)
            var transform=CATransform3DIdentity
            transform.m11=topWidth/640;transform.m21=(bottomLeft-topLeft)*ratio/330
            transform.m22=(bottomY-topY)*ratio/330;transform.m24=(ratio-1)/330
            lid.layer.transform=transform;lid.isHidden=abs(projection.farY-360)<0.7
            inner.frame=lid.bounds;outer.frame=lid.bounds;outer.layer.transform=CATransform3DIdentity
            inner.isHidden = !projection.inner;outer.isHidden=projection.inner
        }
        for (index,r) in g.screens.enumerated(){screens[index].frame=dual && index==0 ? r.offsetBy(dx:-40,dy:-30):r}
        screens[1].isHidden = !dual || !playing || frameImage==nil
        screens[0].isHidden = !playing || frameImage==nil
        let led:CGRect
        switch model {case .nds:led=CGRect(x:650,y:671,width:5,height:10);case .gba:led=CGRect(x:568,y:105,width:8,height:8);case .gbc:led=CGRect(x:54,y:109,width:5,height:5);case .psp:led=CGRect(x:662,y:182,width:4,height:8);case .n3ds:led=CGRect(x:584,y:680,width:5,height:6)}
        powerLED.frame=led;powerLED.isHidden = !playing || frameImage==nil || openness<0.99;powerLED.backgroundColor=UIColor(hex:model == .gbc ? 0xDB4141:model == .n3ds ? 0x5FB5F2:0xB7F26B);powerLED.layer.cornerRadius=2;powerLED.layer.shadowColor=powerLED.backgroundColor?.cgColor;powerLED.layer.shadowOpacity=0.7;powerLED.layer.shadowRadius=4;powerLED.layer.shadowOffset = .zero
        cardSlot.frame=CartridgeSlot.load(model)?.rect ?? .zero;cardSlot.isHidden = !dual || openness>0.1
        stick.isHidden=g.stick==nil || !playing
        if let r=g.stick {stick.frame=r.insetBy(dx:-7,dy:-7)}
        CATransaction.commit()
        spatial.frame=bounds;spatial.isHidden=usesScreenLayout || !spatial.available
        if spatial.available && !usesScreenLayout {scene.isHidden=true;spatial.update(layout:l,viewport:bounds.size,openness:openness,loading:loadingProgress,playing:playing,library:libraryMode,book:bookMode,frame:frameImage,axis:stick.position)}
    }
    private func updateScreens(){
        guard let image=frameImage else{for view in screens {view.image=nil};updateGeometry();return}
        if spatial.available && !usesScreenLayout{spatial.updateFrame(image);return}
        let dual=layout.geometry.screens.count==2
        for index in 0..<(dual ? 2:1) {
            var source=image
            if dual {let w=CGFloat(image.width),h=CGFloat(image.height)/2;let r=model == .n3ds && index==1 ? CGRect(x:w*0.1,y:h,width:w*0.8,height:h):CGRect(x:0,y:CGFloat(index)*h,width:w,height:h);if let crop=image.cropping(to:r){source=crop}}
            screens[index].image=UIImage(cgImage:source)
        };updateGeometry()
    }
    // Both physical UITouch delivery and development verification use this same route.
    #if DEBUG
    func localPointForValidation(_ point:CGPoint)->CGPoint{usesScreenLayout ? point:scene.convert(point,from:self)}
    #endif
    #if DEBUG
    var mechanicalState:[String:Any]{!usesScreenLayout && spatial.available ? spatial.machine!.mechanicalState:(usesScreenLayout ? screenKeys:mechanicalKeys).mechanicalState}
    #endif
    func pointForLocal(_ point:CGPoint)->CGPoint{usesScreenLayout ? point:scene.convert(point,to:self)}
    func route(finger:Int,point:CGPoint,ending:Bool=false){
        let changes=router.update(finger:finger,point:usesScreenLayout ? point:scene.convert(point,from:self),ending:ending,geometry:activeGeometry,enabled:playing && openness>=0.99,scale:usesScreenLayout ? 1:layout.scale)
        if UIDevice.current.userInterfaceIdiom == .phone,hapticsEnabled {
            let pressed=changes.contains{if case .button(_,true)=$0{return true};if case .power=$0{return true};if case .utility(let id)=$0{return id != 0};return false}
            let firstStick=changes.contains{if case .axis=$0{return !hapticFingers.contains(finger) && !ending};return false}
            if pressed || firstStick {PhoneHaptics.press()}
        }
        if ending{hapticFingers.remove(finger)}else{hapticFingers.insert(finger)}
        for change in changes {switch change {
        case .button(let control,let down):if down{screenFirstSurface.held.insert(control)}else{screenFirstSurface.held.remove(control)};screenFirstSurface.setNeedsDisplay();spatial.setHeld(screenFirstSurface.held);mechanicalKeys.setHeld(screenFirstSurface.held);screenKeys.setHeld(screenFirstSurface.held);onButton?(control,down)
        case .axis(let x,let y):screenFirstSurface.axis=CGPoint(x:x,y:y);screenFirstSurface.setNeedsDisplay();stick.position=CGPoint(x:x,y:y);spatial.updateAxis(CGPoint(x:x,y:y));onAxis?(x,y)
        case .pointer(let x,let y,let down):onTouch?(x,y,down)
        case .power:onPower?()
        case .utility(let id):onUtility?(id)
        }}
    }
    func cancelTouches(){for event in router.releaseAll(){switch event{case .button(let c,let down):onButton?(c,down);case .axis: onAxis?(0,0);case .pointer:onTouch?(0,0,false);default:break}};stick.position = .zero;spatial.updateAxis(.zero);screenFirstSurface.held=[];spatial.setHeld([]);mechanicalKeys.setHeld([]);screenKeys.setHeld([]);screenFirstSurface.axis = .zero;screenFirstSurface.setNeedsDisplay();hapticFingers=[];ids=[:]}
    private func handle(_ touch:UITouch,ending:Bool=false){let key=ObjectIdentifier(touch);if ids[key]==nil{nextID+=1;ids[key]=nextID};route(finger:ids[key]!,point:touch.location(in:self),ending:ending);if ending{ids.removeValue(forKey:key)}}
    override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent?){for touch in touches{handle(touch)}}
    override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent?){for touch in touches{handle(touch)}}
    override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent?){for touch in touches{handle(touch,ending:true)}}
    override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent?){for touch in touches{handle(touch,ending:true)}}
}

private final class StickView:UIView {
    var silver=false
    var position=CGPoint.zero {didSet{setNeedsDisplay()}}
    override init(frame:CGRect){super.init(frame:frame);backgroundColor = .clear;isUserInteractionEnabled=false}
    required init?(coder:NSCoder){fatalError()}
    override func draw(_ rect:CGRect){
        let socket=bounds.insetBy(dx:2,dy:2);UIColor(hex:0x101416).setFill();UIBezierPath(ovalIn:socket).fill()
        let cap=bounds.insetBy(dx:7,dy:7).offsetBy(dx:position.x*6,dy:position.y*6)
        guard let c=UIGraphicsGetCurrentContext() else{return};c.saveGState();c.setShadow(offset:CGSize(width:0,height:2),blur:3,color:UIColor.black.cgColor);let p=UIBezierPath(ovalIn:cap);UIColor(hex:silver ? 0xC1C5CA:0x797E84).setFill();p.fill();p.addClip()
        let colors=[UIColor.white.withAlphaComponent(0.35).cgColor,UIColor.clear.cgColor,UIColor.black.withAlphaComponent(0.3).cgColor] as CFArray
        c.drawLinearGradient(CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,0.5,1])!,start:cap.origin,end:CGPoint(x:cap.maxX,y:cap.maxY),options:[])
        c.restoreGState();UIColor.white.withAlphaComponent(0.3).setStroke();p.lineWidth=0.8;p.stroke()
        for y in stride(from:cap.minY+7,to:cap.maxY-6,by:4){let path=UIBezierPath();path.move(to:CGPoint(x:cap.minX+9,y:y));path.addLine(to:CGPoint(x:cap.maxX-9,y:y));UIColor.black.withAlphaComponent(0.13).setStroke();path.lineWidth=0.7;path.stroke()}
    }
}

// Optional iPad large-screen layout. Button art is cut
// from the same Mac skin layers used by the physical-machine presentation.
private final class ScreenFirstSurface:UIView {
    var model:DeviceModel = .gba,theme=0,geometry=DeviceGeometry.make(.gba)
    var image:CGImage?,held=Set<GameControl>(),axis=CGPoint.zero
    override init(frame:CGRect){super.init(frame:frame);isUserInteractionEnabled=false;backgroundColor = .clear}
    required init?(coder:NSCoder){fatalError()}
    func update(model:DeviceModel,theme:Int,geometry:DeviceGeometry,image:CGImage?){
        self.model=model;self.theme=theme;self.geometry=geometry;self.image=image
        setNeedsDisplay()
    }
    override func draw(_ rect:CGRect){
        guard let context=UIGraphicsGetCurrentContext() else{return}
        let screen=geometry.screens.count==2 ? geometry.screens[0].union(geometry.screens[1]):geometry.screens[0]
        let bezel=UIBezierPath(roundedRect:screen.insetBy(dx:-6,dy:-6),cornerRadius:8)
        context.saveGState();context.setShadow(offset:CGSize(width:0,height:4),blur:10,color:UIColor.black.withAlphaComponent(0.65).cgColor);UIColor(hex:0x080C0D).setFill();bezel.fill();context.restoreGState()
        if let image{UIImage(cgImage:image).draw(in:screen)}else{UIColor(hex:0x111A18).setFill();UIBezierPath(rect:screen).fill()}
        UIColor.white.withAlphaComponent(0.15).setStroke();bezel.lineWidth=1;bezel.stroke()
        if let stick=geometry.stick {
            UIColor(hex:0x080C0D).setFill();UIBezierPath(ovalIn:stick.insetBy(dx:-4,dy:-4)).fill()
            let cap=stick.insetBy(dx:4,dy:4).offsetBy(dx:axis.x*8,dy:axis.y*8)
            UIColor(hex:model == .psp && theme==0 ? 0xB7BDC1:0x616B69).setFill();UIBezierPath(ovalIn:cap).fill();UIColor.white.withAlphaComponent(0.25).setStroke();UIBezierPath(ovalIn:cap).stroke()
            for dy in stride(from:CGFloat(12),to:cap.height-8,by:5){let line=UIBezierPath();line.move(to:CGPoint(x:cap.minX+10,y:cap.minY+dy));line.addLine(to:CGPoint(x:cap.maxX-10,y:cap.minY+dy));UIColor.black.withAlphaComponent(0.15).setStroke();line.stroke()}
        }
    }
}
