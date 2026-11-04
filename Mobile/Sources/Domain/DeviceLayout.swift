import CoreGraphics
import Foundation

enum GameControl: Int, CaseIterable, Hashable { case b = 0, y = 1, select = 2, start = 3, up = 4, down = 5, left = 6, right = 7, a = 8, x = 9, l = 10, r = 11
    var title: String { switch self { case .a: return "A"; case .b: return "B"; case .x: return "X"; case .y: return "Y"; case .up: return "▲"; case .down: return "▼"; case .left: return "◀"; case .right: return "▶"; case .l: return "L"; case .r: return "R"; case .start: return "START"; case .select: return "SELECT" } }
}
struct DeviceGeometry {
    var size: CGSize
    var shells: [CGRect]
    var screens: [CGRect]
    var controls: [GameControl: CGRect]
    var power: CGRect
    var utilities:[Int:CGRect] {
        if let customUtilities{return customUtilities}
        if stick != nil,screens.count==1 {return Dictionary(uniqueKeysWithValues:[CGFloat(192),228,264,460,424].enumerated().map{($0.offset,CGRect(x:$0.element,y:287.5,width:25,height:15))})}
        if stick != nil,screens.count==2 {return [0:CGRect(x:343,y:660,width:34,height:15)]}
        if size.width==720,screens.count==1 {return [3:CGRect(x:61,y:306,width:11,height:24)]}
        return [:]
    }
    var stick:CGRect?
    var customUtilities:[Int:CGRect]? = nil
    static func make(_ model:DeviceModel)->DeviceGeometry {
        var geometry=original(model)
        let inset:CGFloat=model == .psp ? 0.09:0.06
        geometry.screens=geometry.screens.map{$0.insetBy(dx:-$0.width*inset,dy:-$0.height*inset)}
        return geometry
    }
    private static func original(_ model:DeviceModel)->DeviceGeometry {
        switch model {
        case .n3ds: return DeviceGeometry(size:CGSize(width:720,height:730),shells:[CGRect(x:40,y:30,width:640,height:330),CGRect(x:40,y:360,width:640,height:330)],screens:[CGRect(x:160,y:74,width:400,height:240),CGRect(x:200,y:404,width:320,height:240)],controls:[GameControl(rawValue:0)!:CGRect(x:590,y:504,width:32,height:32),GameControl(rawValue:1)!:CGRect(x:556,y:471,width:32,height:32),GameControl(rawValue:2)!:CGRect(x:576,y:618,width:65,height:19),GameControl(rawValue:3)!:CGRect(x:576,y:586,width:65,height:19),GameControl(rawValue:4)!:CGRect(x:108,y:524,width:23,height:23),GameControl(rawValue:5)!:CGRect(x:108,y:570,width:23,height:23),GameControl(rawValue:6)!:CGRect(x:85,y:547,width:23,height:23),GameControl(rawValue:7)!:CGRect(x:131,y:547,width:23,height:23),GameControl(rawValue:8)!:CGRect(x:624,y:471,width:32,height:32),GameControl(rawValue:9)!:CGRect(x:590,y:438,width:32,height:32),GameControl(rawValue:10)!:CGRect(x:51,y:353,width:83,height:24),GameControl(rawValue:11)!:CGRect(x:586,y:353,width:83,height:24)],power:CGRect(x:627,y:653,width:30,height:18),stick:CGRect(x:92,y:420,width:48,height:48))
        case .gba: return DeviceGeometry(size:CGSize(width:720,height:380),shells:[CGRect(x:40,y:25,width:640,height:330)],screens:[CGRect(x:211,y:73,width:298,height:199)],controls:[GameControl(rawValue:0)!:CGRect(x:568,y:181,width:40,height:40),GameControl(rawValue:2)!:CGRect(x:124,y:308,width:14,height:14),GameControl(rawValue:3)!:CGRect(x:130,y:282,width:14,height:14),GameControl(rawValue:4)!:CGRect(x:101,y:154,width:28,height:28),GameControl(rawValue:5)!:CGRect(x:101,y:210,width:28,height:28),GameControl(rawValue:6)!:CGRect(x:73,y:182,width:28,height:28),GameControl(rawValue:7)!:CGRect(x:129,y:182,width:28,height:28),GameControl(rawValue:8)!:CGRect(x:612,y:141,width:40,height:40),GameControl(rawValue:10)!:CGRect(x:54,y:23,width:101,height:31),GameControl(rawValue:11)!:CGRect(x:565,y:23,width:101,height:31)],power:CGRect(x:612,y:315,width:36,height:17),stick:nil)
        case .gbc: return DeviceGeometry(size:CGSize(width:380,height:620),shells:[CGRect(x:15,y:20,width:350,height:568)],screens:[CGRect(x:84,y:79,width:212,height:191)],controls:[GameControl(rawValue:0)!:CGRect(x:222,y:398,width:44,height:44),GameControl(rawValue:2)!:CGRect(x:130,y:486,width:39,height:14),GameControl(rawValue:3)!:CGRect(x:185,y:486,width:39,height:14),GameControl(rawValue:4)!:CGRect(x:78,y:360,width:28,height:28),GameControl(rawValue:5)!:CGRect(x:78,y:416,width:28,height:28),GameControl(rawValue:6)!:CGRect(x:50,y:388,width:28,height:28),GameControl(rawValue:7)!:CGRect(x:106,y:388,width:28,height:28),GameControl(rawValue:8)!:CGRect(x:278,y:372,width:44,height:44)],power:CGRect(x:362,y:103,width:13,height:38),stick:nil)
        case .nds: return DeviceGeometry(size:CGSize(width:720,height:730),shells:[CGRect(x:40,y:30,width:640,height:330),CGRect(x:40,y:360,width:640,height:330)],screens:[CGRect(x:200,y:74,width:320,height:240),CGRect(x:200,y:404,width:320,height:240)],controls:[GameControl(rawValue:0)!:CGRect(x:586,y:499,width:38,height:38),GameControl(rawValue:1)!:CGRect(x:550,y:464,width:38,height:38),GameControl(rawValue:2)!:CGRect(x:561,y:623,width:85,height:25),GameControl(rawValue:3)!:CGRect(x:561,y:583,width:85,height:25),GameControl(rawValue:4)!:CGRect(x:107,y:457,width:31,height:32),GameControl(rawValue:5)!:CGRect(x:107,y:518,width:31,height:32),GameControl(rawValue:6)!:CGRect(x:76,y:488,width:32,height:31),GameControl(rawValue:7)!:CGRect(x:137,y:488,width:32,height:31),GameControl(rawValue:8)!:CGRect(x:622,y:464,width:38,height:38),GameControl(rawValue:9)!:CGRect(x:586,y:429,width:38,height:38),GameControl(rawValue:10)!:CGRect(x:48,y:365,width:74,height:24),GameControl(rawValue:11)!:CGRect(x:598,y:365,width:74,height:24)],power:CGRect(x:69,y:654,width:25,height:25),stick:nil)
        case .psp: return DeviceGeometry(size:CGSize(width:720,height:350),shells:[CGRect(x:30,y:30,width:660,height:290)],screens:[CGRect(x:192,y:63,width:336,height:190.4)],controls:[GameControl(rawValue:0)!:CGRect(x:610,y:159,width:30,height:30),GameControl(rawValue:1)!:CGRect(x:579,y:128,width:30,height:30),GameControl(rawValue:2)!:CGRect(x:558,y:285,width:35,height:14),GameControl(rawValue:3)!:CGRect(x:602,y:285,width:35,height:14),GameControl(rawValue:4)!:CGRect(x:94,y:106,width:24,height:24),GameControl(rawValue:5)!:CGRect(x:94,y:154,width:24,height:24),GameControl(rawValue:6)!:CGRect(x:70,y:130,width:24,height:24),GameControl(rawValue:7)!:CGRect(x:118,y:130,width:24,height:24),GameControl(rawValue:8)!:CGRect(x:641,y:128,width:30,height:30),GameControl(rawValue:9)!:CGRect(x:610,y:97,width:30,height:30),GameControl(rawValue:10)!:CGRect(x:75,y:46,width:75,height:16),GameControl(rawValue:11)!:CGRect(x:570,y:46,width:75,height:16)],power:CGRect(x:667,y:199,width:15,height:42),stick:CGRect(x:88,y:204,width:45,height:45))
        }
    }
}
struct MobileLayout {
    var frame: CGRect
    var scale: CGFloat
    var geometry: DeviceGeometry
    init(model: DeviceModel, viewport: CGSize, topInset: CGFloat, bottomInset: CGFloat,rotated:Bool=false,verticalPosition:CGFloat=0.58,zoom:CGFloat=1,horizontalPosition:CGFloat=0.5,nativePhone:Bool=false,leftInset:CGFloat=0,rightInset:CGFloat=0,immersiveWidePad:Bool=false) {
        geometry = .make(model)
        if nativePhone {
            let visible:CGRect=model == .gbc ? CGRect(x:8,y:10,width:370,height:600):model == .psp ? CGRect(x:28,y:20,width:664,height:304):CGRect(x:30,y:14,width:660,height:348)
            // The shell may use the empty side margins. Controls and LCDs must
            // remain inside safe areas, so fitting is constrained by both bounds.
            let area=CGRect(x:4,y:topInset+4,width:max(1,viewport.width-8),height:max(1,viewport.height-topInset-bottomInset-8))
            let interactive=(Array(geometry.controls.values)+geometry.screens).reduce(CGRect.null){$0.union($1)}
            scale=min(area.width/visible.width,area.height/visible.height,max(1,viewport.width-leftInset-rightInset-8)/interactive.width)*max(0.6,min(1,zoom))
            let low=max(area.minX-visible.minX*scale,leftInset+4-interactive.minX*scale)
            let high=min(area.maxX-visible.maxX*scale,viewport.width-rightInset-4-interactive.maxX*scale)
            let x=low+max(0,high-low)*max(0,min(1,horizontalPosition))
            let y=area.minY+(area.height-visible.height*scale)*max(0,min(1,verticalPosition))-visible.minY*scale
            frame=CGRect(x:x,y:y,width:geometry.size.width*scale,height:geometry.size.height*scale);return
        }
        if immersiveWidePad && viewport.width>viewport.height && (model == .psp || model == .gba) && !rotated {
            // Fit the physical shell rather than its padded design canvas.
            // Use the same transform for LCDs, keys and hit testing.
            let visible=CGRect(x:28,y:model == .psp ? 18:12,width:664,height:model == .psp ? 306:350)
            let area=CGRect(x:leftInset+14,y:topInset+14,width:max(1,viewport.width-leftInset-rightInset-28),height:max(1,viewport.height-topInset-bottomInset-28))
            scale=min(area.width/visible.width,area.height/visible.height)*max(0.6,min(1,zoom))
            frame=CGRect(x:area.minX+(area.width-visible.width*scale)*max(0,min(1,horizontalPosition))-visible.minX*scale,y:area.minY+(area.height-visible.height*scale)*max(0,min(1,verticalPosition))-visible.minY*scale,width:geometry.size.width*scale,height:geometry.size.height*scale);return
        }
        let available = CGRect(x:20,y:topInset+64,width:max(1,viewport.width-40),height:max(1,viewport.height-topInset-bottomInset-84))
        let maximumWidth:CGFloat = model == .gbc ? 510 : 1000
        let fit=rotated ? CGSize(width:geometry.size.height,height:geometry.size.width):geometry.size
        let baseScale=min(min(available.width,maximumWidth)/fit.width,available.height/fit.height)
        scale=min(available.width/fit.width,min(available.height/fit.height,baseScale*max(0.6,min(1.6,zoom))))
        let size=CGSize(width:fit.width*scale,height:fit.height*scale)
        frame=CGRect(x:available.minX+max(0,available.width-size.width)*max(0,min(1,horizontalPosition)),y:available.minY+max(0,available.height-size.height)*max(0,min(1,verticalPosition)),width:size.width,height:size.height)
    }
    func local(_ p:CGPoint)->CGPoint { CGPoint(x:(p.x-frame.minX)/scale,y:(p.y-frame.minY)/scale) }
    func rect(_ r:CGRect)->CGRect { CGRect(x:frame.minX+r.minX*scale,y:frame.minY+r.minY*scale,width:r.width*scale,height:r.height*scale) }
    func control(at p:CGPoint)->GameControl? {
        // Nearest centre resolves expanded hit targets without stealing adjacent controls.
        geometry.controls.compactMap { control,r -> (GameControl,CGFloat)? in
            let target=rect(r);let hit=target.insetBy(dx:-max(0,(44-target.width)/2),dy:-max(0,(44-target.height)/2))
            guard hit.contains(p) else {return nil};return (control,hypot(p.x-target.midX,p.y-target.midY))
        }.min(by:{$0.1<$1.1})?.0
    }
}
struct MultiTouchButtons {
    private var fingers: [Int: GameControl] = [:]
    mutating func update(finger:Int, control:GameControl?) -> [(GameControl,Bool)] {
        let previous=fingers[finger];guard previous != control else{return []}
        fingers[finger]=control
        var changes:[(GameControl,Bool)]=[]
        if let previous, !fingers.values.contains(previous) {changes.append((previous,false))}
        if let control, fingers.values.filter({$0==control}).count==1 {changes.append((control,true))}
        return changes
    }
    mutating func releaseAll()->[(GameControl,Bool)] {let old=Set(fingers.values);fingers.removeAll();return old.map{($0,false)}}
}

enum TouchInputEvent:Equatable {
    case button(GameControl,Bool),axis(CGFloat,CGFloat),pointer(CGFloat,CGFloat,Bool),power,utility(Int)
}
struct TouchInputRouter {
    private enum Owner {case buttons,stick,pointer,utility}
    private var owners:[Int:Owner]=[:],held:[Int:Set<GameControl>]=[:]
    private var stickFinger:Int?,pointerFinger:Int?
    private func allButtons()->Set<GameControl>{Set(held.values.flatMap{$0})}
    private mutating func buttons(_ finger:Int,_ next:Set<GameControl>)->[TouchInputEvent]{
        let before=allButtons();held[finger]=next.isEmpty ? nil:next;let after=allButtons()
        return before.subtracting(after).map{.button($0,false)}+after.subtracting(before).map{.button($0,true)}
    }
    mutating func update(finger:Int,point:CGPoint,ending:Bool,geometry g:DeviceGeometry,enabled:Bool,scale:CGFloat)->[TouchInputEvent]{
        if ending {
            owners.removeValue(forKey:finger);var events=buttons(finger,[])
            if stickFinger==finger{stickFinger=nil;events.append(.axis(0,0))}
            if pointerFinger==finger{pointerFinger=nil;events.append(.pointer(0,0,false))};return events
        }
        func hit(_ r:CGRect)->Bool{r.insetBy(dx:-max(0,(44/scale-r.width)/2),dy:-max(0,(44/scale-r.height)/2)).contains(point)}
        if owners[finger]==nil {
            // Resolve visible utility targets by nearest centre; expanded regions must not overlap priority.
            if hit(g.power){owners[finger] = .utility;return [.power]}
            if !enabled{return []}
            if let utility=g.utilities.filter({hit($0.value)}).min(by:{hypot(point.x-$0.value.midX,point.y-$0.value.midY)<hypot(point.x-$1.value.midX,point.y-$1.value.midY)})?.key {owners[finger] = .utility;return [.utility(utility)]}
            if let stick=g.stick,hit(stick),stickFinger==nil {owners[finger] = .stick;stickFinger=finger}
            else if g.screens.count==2,let bottom=g.screens.last,bottom.contains(point),pointerFinger==nil{owners[finger] = .pointer;pointerFinger=finger}
            else{owners[finger] = .buttons}
        }
        switch owners[finger] {
        case .stick:
            guard let r=g.stick else{return []};let dx=(point.x-r.midX)/(r.width/2),dy=(point.y-r.midY)/(r.height/2),length=max(1,hypot(dx,dy))
            return [.axis(abs(dx)<0.12 && abs(dy)<0.12 ? 0:dx/length,abs(dx)<0.12 && abs(dy)<0.12 ? 0:dy/length)]
        case .pointer:
            guard let r=g.screens.last else{return []};return [.pointer(max(0,min(1,(point.x-r.minX)/r.width)),max(0,min(1,(point.y-r.minY)/r.height)),true)]
        case .buttons:
            let dirs:[GameControl]=[.up,.down,.left,.right],pad=dirs.compactMap{g.controls[$0]}.reduce(CGRect.null){$0.union($1)}
            if pad.insetBy(dx:-4,dy:-4).contains(point){
                let x=(point.x-pad.midX)/(pad.width/2),y=(point.y-pad.midY)/(pad.height/2);var next=Set<GameControl>()
                if x < -0.28{next.insert(.left)};if x>0.28{next.insert(.right)};if y < -0.28{next.insert(.up)};if y>0.28{next.insert(.down)}
                return buttons(finger,next)
            }
            let control=g.controls.filter{!dirs.contains($0.key) && hit($0.value)}.min{hypot(point.x-$0.value.midX,point.y-$0.value.midY)<hypot(point.x-$1.value.midX,point.y-$1.value.midY)}?.key
            return buttons(finger,control.map{[$0]} ?? [])
        default:return []
        }
    }
    mutating func releaseAll()->[TouchInputEvent]{
        var events=allButtons().map{TouchInputEvent.button($0,false)}
        if stickFinger != nil{events.append(.axis(0,0))};if pointerFinger != nil{events.append(.pointer(0,0,false))}
        owners=[:];held=[:];stickFinger=nil;pointerFinger=nil;return events
    }
}

// Same fixed-hinge projection as StudioView.drawMachine on macOS.
struct LidProjection {
    let farY:CGFloat,farWidth:CGFloat,inner:Bool
    init(openness:CGFloat){
        let angle=max(0,min(1,openness)) * .pi * 165/180,pitch=CGFloat.pi * 15/180
        let depth=1-330*sin(angle)/2400
        farY=360+330*cos(angle+pitch)/cos(pitch)/depth
        farWidth=640/depth;inner=cos(angle+pitch)<0
    }
}

// Shared physical geometry; both platforms ship the same Assets/media-slots.json.
struct CartridgeSlot:Decodable {
    let x:CGFloat,y:CGFloat,width:CGFloat,height:CGFloat,cardWidth:CGFloat,ratio:CGFloat
    var rect:CGRect{CGRect(x:x,y:y,width:width,height:height)}
}
extension CartridgeSlot {
    private static let shared:[String:CartridgeSlot] = {
        guard let path=Bundle.main.url(forResource:"media-slots",withExtension:"json",subdirectory:"Assets"),let data=try? Data(contentsOf:path) else{return [:]}
        return (try? JSONDecoder().decode([String:CartridgeSlot].self,from:data)) ?? [:]
    }()
    static func load(_ model:DeviceModel)->CartridgeSlot?{shared[model.rawValue]}
}

// Optional iPad screen-first mode uses the same touch router as the physical skins.
// iPhone retains the original machine layout in its native orientation.
struct ScreenFirstLayout {
    var geometry:DeviceGeometry
    var screen:CGRect
    init(model:DeviceModel,viewport:CGSize,topInset:CGFloat,bottomInset:CGFloat,leftInset:CGFloat=0,rightInset:CGFloat=0,zoom:CGFloat=1,x:CGFloat=0.5,y:CGFloat=0.5){
        let wide=viewport.width>viewport.height
        let left=leftInset+12,right=viewport.width-rightInset-12,top=topInset+60,bottom=viewport.height-bottomInset-16
        let ratio:CGFloat
        switch model{case .psp:ratio=480.0/272;case .gbc:ratio=160.0/144;case .nds:ratio=256.0/384;case .n3ds:ratio=400.0/480;case .gba:ratio=240.0/160}
        let margin:CGFloat=wide ? 162:4
        let space=CGRect(x:left+margin,y:top+8,width:max(100,right-left-margin*2),height:max(90,(wide ? bottom-52:bottom-342)-(top+8)))
        let sizeFactor=max(0.55,min(1,zoom))
        let w=min(space.width,space.height*ratio)*sizeFactor,h=w/ratio
        screen=CGRect(x:space.minX+(space.width-w)*max(0,min(1,x)),y:space.minY+(space.height-h)*max(0,min(1,y)),width:w,height:h)
        var controls:[GameControl:CGRect]=[:]
        let cx=left+70,cy=wide ? top+(bottom-top)*0.43:bottom-152
        let unit:CGFloat=44
        controls[.up]=CGRect(x:cx-unit/2,y:cy-unit*1.5,width:unit,height:unit)
        controls[.down]=CGRect(x:cx-unit/2,y:cy+unit/2,width:unit,height:unit)
        controls[.left]=CGRect(x:cx-unit*1.5,y:cy-unit/2,width:unit,height:unit)
        controls[.right]=CGRect(x:cx+unit/2,y:cy-unit/2,width:unit,height:unit)
        let rx=right-64,ry=wide ? top+(bottom-top)*0.45:bottom-155
        if model == .psp || model == .nds || model == .n3ds {
            controls[.x]=CGRect(x:rx-27,y:ry-66,width:54,height:54);controls[.b]=CGRect(x:rx-27,y:ry+12,width:54,height:54)
            controls[.y]=CGRect(x:rx-66,y:ry-27,width:54,height:54);controls[.a]=CGRect(x:rx+12,y:ry-27,width:54,height:54)
        }else{controls[.a]=CGRect(x:right-64,y:ry-46,width:60,height:60);controls[.b]=CGRect(x:right-132,y:ry+8,width:60,height:60)}
        controls[.select]=CGRect(x:viewport.width/2-92,y:bottom-38,width:64,height:34)
        controls[.start]=CGRect(x:viewport.width/2+28,y:bottom-38,width:64,height:34)
        if model != .gbc {controls[.l]=CGRect(x:left+16,y:wide ? top+4:bottom-352,width:100,height:44);controls[.r]=CGRect(x:right-116,y:wide ? top+4:bottom-352,width:100,height:44)}
        let stick=(model == .psp || model == .n3ds) ? CGRect(x:cx-30,y:wide ? bottom-74:bottom-292,width:60,height:60):nil
        let displayScreens:[CGRect]=(model == .nds || model == .n3ds) ? [CGRect(x:screen.minX,y:screen.minY,width:screen.width,height:screen.height/2),CGRect(x:screen.minX+(model == .n3ds ? screen.width*0.1:0),y:screen.midY,width:screen.width*(model == .n3ds ? 0.8:1),height:screen.height/2)]:[screen]
        geometry=DeviceGeometry(size:viewport,shells:[],screens:displayScreens,controls:controls,power:CGRect(x:-1000,y:-1000,width:0,height:0),stick:stick,customUtilities:[:])
    }
}

/// Physical cross pivots as one rigid part. Cancelling opposite directions must
/// return to neutral; diagonal input retains the same maximum tilt angle.
struct DPadPose {
    let x:CGFloat,y:CGFloat
    init(held:Set<GameControl>){
        let vertical=CGFloat((held.contains(.down) ? 1:0)-(held.contains(.up) ? 1:0))
        let horizontal=CGFloat((held.contains(.right) ? 1:0)-(held.contains(.left) ? 1:0))
        let length=max(1,sqrt(vertical*vertical+horizontal*horizontal))
        x=vertical/length*0.14;y=horizontal/length*0.14
    }
}
