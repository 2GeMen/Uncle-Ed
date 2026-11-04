import Cocoa
import CoreImage
import QuartzCore
import UniformTypeIdentifiers

let fm = FileManager.default
let support = fm.homeDirectoryForCurrentUser.appendingPathComponent(
  "Library/Application Support/UncleED")
let dataDir = support.appendingPathComponent("Data")
let assets = support.appendingPathComponent("Assets")
let bundledAssets = Bundle.main.resourceURL!.appendingPathComponent("Assets")

// The emulator, its GL context, saves and audio producer share one serial queue.
// AppKit/SceneKit consume immutable images without blocking the core clock.
final class CoreDriver {
  static let shared=CoreDriver()
  private let queue=DispatchQueue(label:"local.uncleed.core",qos:.userInteractive),lock=NSLock()
  private var timer:DispatchSourceTimer?,paused=false,lastTime=0.0,accumulator=0.0,lastSerial:UInt=0
  private var latest:CGImage?,history=[[String:Any]](),title="",windowStart=0.0,coreTime=0.0,copyTime=0.0,worst=0.0,frames=0,images=0,maxBatch=0,readStart=0.0,lastSave=0.0
  private var pauseRequested=false
  func start(_ core:String,_ rom:String,_ save:String,title:String)->Int32 {
    stop()
    return queue.sync {
      let ok=emu_start(core,rom,save);guard ok != 0 else{return ok}
      self.title=title;self.lastTime=CACurrentMediaTime();self.lastSave=self.lastTime;self.windowStart=self.lastTime;self.accumulator=0;self.lastSerial=0;self.readStart=0;self.paused=false;self.pauseRequested=false
      self.lock.lock();self.latest=nil;self.history=[];self.lock.unlock()
      self.coreTime=0;self.copyTime=0;self.worst=0;self.frames=0;self.images=0;self.maxBatch=0
      let timer=DispatchSource.makeTimerSource(flags:.strict,queue:self.queue)
      timer.schedule(deadline:.now(),repeating:1/max(1,emu_fps()),leeway:.microseconds(200))
      timer.setEventHandler{[weak self] in autoreleasepool{self?.tick()}}
      self.timer=timer;timer.resume();return ok
    }
  }
  func stop(){queue.sync{timer?.cancel();timer=nil;emu_stop();lock.lock();latest=nil;lock.unlock()}}
  func save(){queue.sync{_ = emu_save()}}
  func instantState(restore:Bool,slot:Int,done:@escaping(Int32,String)->Void){queue.async{let result=restore ? emu_state_load(Int32(slot)):emu_state_save(Int32(slot));let message=String(cString:emu_state_error());self.lastTime=CACurrentMediaTime();self.accumulator=0;self.lastSerial=0;DispatchQueue.main.async{done(result,message)}}}
  func volume(_ value:Float){queue.async{emu_volume(value)}}
  func pause(_ value:Bool){guard value != pauseRequested else{return};pauseRequested=value;queue.async{self.paused=value;self.lastTime=CACurrentMediaTime();self.accumulator=0}}
  func snapshot()->(CGImage?,[[String:Any]]){lock.lock();defer{lock.unlock()};return (latest,history)}
  private func tick(){
    let now=CACurrentMediaTime();guard !paused else{lastTime=now;return}
    let step=1/max(1,emu_fps()),start=now;accumulator+=min(0.1,max(0,now-lastTime));lastTime=now;var count=0
    while accumulator>=step && count<4{emu_run();accumulator-=step;count+=1;if CACurrentMediaTime()-start>step*0.9{break}}
    if count==0{return};if accumulator>step{accumulator=step};frames+=count;maxBatch=max(maxBatch,count);coreTime+=CACurrentMediaTime()-start
    if emu_video_serial() != lastSerial {
      lastSerial=emu_video_serial();let copyStart=CACurrentMediaTime(),w=Int(emu_width()),h=Int(emu_height())
      if w>0 && h>0 && w<=2048 && h<=2048,let pixels=emu_pixels(){let bytes=Data(bytes:pixels,count:w*h*4)
        if let provider=CGDataProvider(data:bytes as CFData),let image=CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.noneSkipFirst.rawValue|CGBitmapInfo.byteOrder32Little.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent){lock.lock();latest=image;lock.unlock();images+=1}}
      copyTime+=CACurrentMediaTime()-copyStart
    }
    worst=max(worst,CACurrentMediaTime()-start)
    if now-lastSave>10{_ = emu_save();lastSave=now}
    if now-windowStart>=10{
      let elapsed=now-windowStart
      let row:[String:Any]=["game":title,"emulatedFPS":Double(frames)/elapsed,"submittedFPS":Double(images)/elapsed,"coreMS":coreTime/Double(max(1,frames))*1000,"copyMS":copyTime/Double(max(1,images))*1000,"worstTickMS":worst*1000,"maxBatch":maxBatch,"gpuReadbackMS":(emu_readback_seconds()-readStart)/Double(max(1,frames))*1000,"audioUnderrunSamples":emu_audio_underruns(),"audioBufferedSamples":emu_audio_buffered(),"cpuOption":String(cString:emu_core_option("ppsspp_cpu_core")),"backend":String(cString:emu_backend()),"displayClock":"serial core timer + CADisplayLink presentation","timestamp":Date().timeIntervalSince1970]
      lock.lock();history.append(row);if history.count>120{history.removeFirst()};let report=history;lock.unlock()
      if let bytes=try? JSONSerialization.data(withJSONObject:report,options:.prettyPrinted){try? bytes.write(to:dataDir.appendingPathComponent("performance-history.json"),options:.atomic)}
      windowStart=now;coreTime=0;copyTime=0;worst=0;frames=0;images=0;maxBatch=0;readStart=emu_readback_seconds()
    }
  }
}

// Shared physical geometry; both platforms ship the same Assets/media-slots.json.
struct CartridgeSlot:Decodable {
    let x:CGFloat,y:CGFloat,width:CGFloat,height:CGFloat,cardWidth:CGFloat,ratio:CGFloat
    var rect:CGRect{CGRect(x:x,y:y,width:width,height:height)}
}
let mediaSlots=(try? JSONDecoder().decode([String:CartridgeSlot].self,from:Data(contentsOf:bundledAssets.appendingPathComponent("media-slots.json")))) ?? [:]

enum Handheld: String, CaseIterable {
  case nds, gba, gbc, psp, n3ds = "3ds"
  var name: String {
    switch self {
    case .nds: return "Nintendo DS"
    case .gba: return "Game Boy Advance"
    case .gbc: return "Game Boy Color"
    case .psp: return "PlayStation Portable"
    case .n3ds: return "Nintendo 3DS"
    }
  }
  var editions: [String] {
    switch self {
    case .nds: return ["宝可梦黑白限定版", "马里奥限定版", "塞尔达限定版", "黑磨砂"]
    case .gba: return ["原生黄色", "索尼克定制", "EVA 定制", "白色磨砂半透明"]
    case .gbc: return ["宝可梦中心限定", "经典原始配色", "经典黄配色", "黑磨砂"]
    case .psp: return ["最终幻想限定", "怪物猎人限定", "实况足球限定", "黑磨砂"]
    case .n3ds: return ["塞尔达限定", "宝可梦日月限定", "大乱斗限定", "黑磨砂"]
    }
  }
}
func prepareStorage() {
  let legacy = fm.homeDirectoryForCurrentUser.appendingPathComponent(
    "Library/Application Support/PocketRoom")
  if !fm.fileExists(atPath: support.path), fm.fileExists(atPath: legacy.path) {
    try? fm.copyItem(at: legacy, to: support)
  }
  for kind in Handheld.allCases {
    try? fm.createDirectory(
      at: support.appendingPathComponent("roms/" + kind.rawValue), withIntermediateDirectories: true
    )
    try? fm.createDirectory(
      at: dataDir.appendingPathComponent("Saves/" + kind.rawValue),
      withIntermediateDirectories: true)
  }
  for url in (try? fm.contentsOfDirectory(at: dataDir, includingPropertiesForKeys: nil)) ?? []
  where url.pathExtension == "srm" || url.lastPathComponent == "melonDS DS" {
    let to = dataDir.appendingPathComponent("Saves/nds/" + url.lastPathComponent)
    if !fm.fileExists(atPath: to.path) { try? fm.copyItem(at: url, to: to) }
  }
  for path in [dataDir, assets, assets.appendingPathComponent("Covers")] {
    try? fm.createDirectory(at: path, withIntermediateDirectories: true)
  }
  if let enumerator = fm.enumerator(
    at: bundledAssets, includingPropertiesForKeys: [.isRegularFileKey])
  {
    for case let url as URL in enumerator {
      if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
        let relative = String(url.path.dropFirst(bundledAssets.path.count + 1))
        let target = assets.appendingPathComponent(relative)
        if !fm.fileExists(atPath: target.path) {
          try? fm.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
          try? fm.copyItem(at: url, to: target)
        }
      }
    }
  }
  for kind in [Handheld.psp, .n3ds] {
    let source=bundledAssets.appendingPathComponent("Systems/"+kind.rawValue)
    let target=dataDir.appendingPathComponent("Saves/"+kind.rawValue)
    if let children=try? fm.contentsOfDirectory(at:source,includingPropertiesForKeys:nil) {
      for child in children {let to=target.appendingPathComponent(child.lastPathComponent);if !fm.fileExists(atPath:to.path) {try? fm.copyItem(at:child,to:to)}}
    }
  }

  if let data=try? Data(contentsOf:bundledAssets.appendingPathComponent("retired-assets.json")),
    let retired=try? JSONDecoder().decode([String:String].self,from:data) {
    for (relative,hash) in retired where relative.hasPrefix("Skins/Modern/") && !relative.contains("..") {
      let source=assets.appendingPathComponent(relative)
      guard (try? fileDigest(source)) == hash else {continue}
      let archive=dataDir.appendingPathComponent("RetiredAssets/0.10/"+relative)
      if !fm.fileExists(atPath:archive.path) {
        try? fm.createDirectory(at:archive.deletingLastPathComponent(),withIntermediateDirectories:true)
        try? fm.moveItem(at:source,to:archive)
      }
    }
  }

}
func color(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
  NSColor(
    srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
    blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
func smooth(_ x: CGFloat) -> CGFloat {
  let t = max(0, min(1, x))
  return t * t * t * (t * (t * 6 - 15) + 10)
}
struct CoverEntry: Codable {
  var name: String
  var url: String
}
struct CoverMeta: Codable {
  var name: String
  var title: String
  var detail: String
  var url: String
  var source: String
  var match: String
}
struct Game {
  var url: URL
  var code: String
  var title: String
  var detail: String
  var cover: NSImage?
}
enum Phase: String {
  case library, focusing, inserting, opening, booting, playing, closing, idleOpen
}

final class StudioView: NSView, NSViewToolTipOwner {
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  lazy var lidTexture = NSImage(
    contentsOf: assets.appendingPathComponent("Skins/NDS/black-edition-lid.png"))
  var history: [[String: Any]] = []
  var inputCounts: [String: Int] = [:], touchCount = 0
  var handheld: Handheld = .nds
  var romDir: URL { support.appendingPathComponent("roms/" + handheld.rawValue) }
  var saveDir: URL { profileSaveRoot ?? dataDir.appendingPathComponent("Saves/" + handheld.rawValue) }
  var profileSaveRoot:URL?
  var frameLink:AnyObject?,displayTimestamp:CFTimeInterval?,lastVideoSerial:UInt=0
  var core: URL {
    Bundle.main.resourceURL!.appendingPathComponent(
      "cores/" + (handheld == .nds ? "melondsds_libretro.dylib" : handheld == .psp ? "ppsspp_libretro.dylib" : handheld == .n3ds ? "azahar_libretro.dylib" : "mgba_libretro.dylib"))
  }
  enum PickerPage { case models, themes }
  var pickerPage: PickerPage = .models
  var pickerIndex = 0
  var cartridgePalettes: [String: CartridgePalette] = [:]
  var cardTints: [String: (image: NSImage, tint: Int)] = [:]
  var machineLogos: [Handheld: NSImage] = [:]
  var homeBrandLogos:[Handheld:NSImage]=[:]
  var importing = false
  var libraryNotice: String?, noticeUntil = 0.0
  var coverIndexes: [Handheld: [CoverEntry]] = [:]
  var indexRequests = Set<Handheld>(), pendingCovers: [Handheld: [Game]] = [:]
  var coverStates: [String: String] = [:]
  var running = false, choosing = true, phase: Phase = .library, inserted = false
  var status = "每一张卡带，都是一次新的冒险。", videoFrame: CGImage?
  var games: [Game] = [], selectedIndex = 0, carousel: CGFloat = 0, scrollAmount: CGFloat = 0
  var covers: [String: CoverMeta] = [:], coverIndex: [CoverEntry] = [], requested = Set<String>()
  var lid: CGFloat = 0, stageStart = CACurrentMediaTime(), closeFrom: CGFloat = 1,
    bootAfterOpening = true
  var ticks = 0, timer: Timer?, lastTime = CACurrentMediaTime(), accumulator = 0.0, lastReport = 0.0
  var exportBareKeys = false,exportSpatialSurface=false
  var held = Set<Int>(), pressedAt: [Int: Double] = [:], releases: [Int: Double] = [:],
    touchRelease = 0.0, mouseButtonID: Int?
  var bookMode = false, pose: CGFloat = 0
  var muted = false
  var pressedFrame: [Int: UInt] = [:], touchDownFrame: UInt = 0, touchActive = false
  var shelfDown: CGPoint?, shelfDownIndex = 0, dragged = false
  var canvasHeight: CGFloat {
    !choosing && (phase == .playing || phase == .idleOpen) ? (handheld == .psp ? 480 : handheld == .gba ? 560 : 780) : 780
  }
  var modern: Bool { handheld == .psp || handheld == .n3ds }
  var dual: Bool { handheld == .nds || handheld == .n3ds }
  var volumeLevel: Float = 1
  var screenDim: CGFloat = 0
  var analogDrag = false
  var stickX: CGFloat = 0, stickY: CGFloat = 0
  var modernImages: [String:NSImage] = [:]
  var themePreviews: [String:NSImage] = [:]
  // Hardware uses fixed logical points in both windowed and full-screen presentation.
  // Drawing, hit testing, tooltips and the stylus all share this viewport transform.
  var fullScreenTransition = false
  lazy var mechanicalStage=MechanicalControlStage(owner:self)
  lazy var gbcStage=UniversalStage(owner:self)
  var gbcThemePosition:CGFloat=0,modelPosition:CGFloat=0
  var pickerWheelActiveUntil:CFTimeInterval=0,pickerWheelAnchor:CGFloat=0,pickerWheelGesture=false
  var gbcThemeDragging=false
  var displayPopover:NSPopover?
  var machineSelector:NSPopover?
  var mediaSeatSoundSent=false
  var displayKey:String{"display."+handheld.rawValue}
  var focusActive:Bool{!choosing && running && phase == .playing && UserDefaults.standard.bool(forKey:displayKey+".focus")}
  var scale:CGFloat {
    guard !choosing else{return 1}
    let zoom=UserDefaults.standard.object(forKey:displayKey+".zoom")==nil ? 1:UserDefaults.standard.double(forKey:displayKey+".zoom")
    return min(min(bounds.width/720,bounds.height/canvasHeight),CGFloat(max(0.55,min(2,zoom))))
  }
  var offset: CGPoint {
    let x=UserDefaults.standard.object(forKey:displayKey+".x")==nil || choosing ? 0.5:UserDefaults.standard.double(forKey:displayKey+".x")
    let y=UserDefaults.standard.object(forKey:displayKey+".y")==nil || choosing ? 0.5:UserDefaults.standard.double(forKey:displayKey+".y")
    return CGPoint(x:max(0,bounds.width-720*scale)*CGFloat(x),y:max(0,bounds.height-canvasHeight*scale)*CGFloat(y))
  }
  var selected: Game? { games.indices.contains(selectedIndex) ? games[selectedIndex] : nil }
  var baseY: CGFloat { 410 }
  var bottom: CGRect { CGRect(x: 440, y: baseY + 44, width: 320, height: 240) }
  var top: CGRect { CGRect(x: 440, y: baseY - 330 + 44, width: 320, height: 240) }
  let keys: [UInt16: Int] = [
    123: 6, 124: 7, 125: 5, 126: 4, 7: 8, 6: 0, 1: 9, 0: 1, 12: 10, 13: 11, 36: 3, 60: 2,
  ]
  var buttons: [(String, Int, CGRect)] {
    if modern { return modernButtons }
    if handheld != .nds { return classicButtons }
    let y = baseY
    return [
      ("X", 9, CGRect(x: 826, y: y + 69, width: 38, height: 38)),
      ("A", 8, CGRect(x: 862, y: y + 104, width: 38, height: 38)),
      ("B", 0, CGRect(x: 826, y: y + 139, width: 38, height: 38)),
      ("Y", 1, CGRect(x: 790, y: y + 104, width: 38, height: 38)),
      ("START", 3, CGRect(x: 801, y: y + 223, width: 85, height: 25)),
      ("SELECT", 2, CGRect(x: 801, y: y + 263, width: 85, height: 25)),
      ("L", 10, CGRect(x: 288, y: y + 5, width: 74, height: 24)),
      ("R", 11, CGRect(x: 838, y: y + 5, width: 74, height: 24)),
    ]
  }
  var dpad: [(String, Int, CGRect)] {
    if modern { return modernDpad }
    if handheld != .nds { return classicDpad }
    let y = baseY
    return [
      ("", 4, CGRect(x: 347, y: y + 97, width: 31, height: 32)),
      ("", 5, CGRect(x: 347, y: y + 158, width: 31, height: 32)),
      ("", 6, CGRect(x: 316, y: y + 128, width: 32, height: 31)),
      ("", 7, CGRect(x: 377, y: y + 128, width: 32, height: 31)),
    ]
  }
  lazy var stylus: NSCursor = {
    let image = NSImage(size: NSSize(width: 42, height: 42))
    image.lockFocus()
    let p = NSBezierPath()
    p.move(to: NSPoint(x: 3, y: 2))
    p.line(to: NSPoint(x: 8, y: 15))
    p.line(to: NSPoint(x: 31, y: 39))
    p.line(to: NSPoint(x: 39, y: 31))
    p.line(to: NSPoint(x: 15, y: 8))
    p.close()
    color(0xD2D5D8).setFill()
    p.fill()
    color(0x14171A).setStroke()
    p.lineWidth = 2
    p.stroke()
    let nib = NSBezierPath()
    nib.move(to: NSPoint(x: 3, y: 2))
    nib.line(to: NSPoint(x: 8, y: 15))
    nib.line(to: NSPoint(x: 15, y: 8))
    nib.close()
    color(0x343940).setFill()
    nib.fill()
    image.unlockFocus()
    return NSCursor(image: image, hotSpot: NSPoint(x: 3, y: 40))
  }()
  override init(frame: NSRect) {
    super.init(frame: frame)
    NotificationCenter.default.addObserver(forName:GameCatalog.changed,object:gameCatalog,queue:.main){[weak self] _ in self?.needsDisplay=true}
    prepareStorage()
    theme =
      UserDefaults.standard.object(forKey: "theme.nds") == nil
      ? (UserDefaults(suiteName: "local.pocketroom.nds")?.integer(forKey: "shellTheme") ?? 0)
      : UserDefaults.standard.integer(forKey: "theme.nds")
    theme = min(handheld.editions.count-1, max(0, theme))
    if let d = try? Data(contentsOf: assets.appendingPathComponent("cover-manifest.json")) {
      covers = (try? JSONDecoder().decode([String: CoverMeta].self, from: d)) ?? [:]
    }
    if let d = try? Data(contentsOf: assets.appendingPathComponent("cover-index.json")) {
      coverIndex = (try? JSONDecoder().decode([CoverEntry].self, from: d)) ?? []
    }
    if let data = try? Data(
      contentsOf: bundledAssets.appendingPathComponent("cover-manifest.json")),
      let bundled = try? JSONDecoder().decode([String: CoverMeta].self, from: data)
    {
      covers.merge(bundled) { _, new in new }
    }
    if let data=try? Data(contentsOf:assets.appendingPathComponent("cartridge-palettes.json")) {
      cartridgePalettes=(try? JSONDecoder().decode([String:CartridgePalette].self,from:data)) ?? [:]
    }
    scan()
    selectedIndex = games.count / 2
    carousel = CGFloat(selectedIndex)
    if #available(macOS 14.0,*) {
      let link=displayLink(target:self,selector:#selector(displayStep(_:)))
      link.preferredFrameRateRange=CAFrameRateRange(minimum:60,maximum:60,preferred:60)
      link.add(to:.main,forMode:.common);frameLink=link
    }else {
      timer=Timer(timeInterval:1.0/60,target:self,selector:#selector(step),userInfo:nil,repeats:true)
      RunLoop.main.add(timer!,forMode:.common)
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(inactive), name: NSWindow.didResignKeyNotification, object: nil)
    report()
    if let title=CommandLine.arguments.first(where:{$0.hasPrefix("--profile-game=")})?.dropFirst(15) {
      DispatchQueue.main.asyncAfter(deadline:.now()+1){
        self.handheld=CommandLine.arguments.first(where:{$0.hasPrefix("--profile-model=")}).flatMap{Handheld(rawValue:String($0.dropFirst(16)))} ?? .psp;self.scan()
        guard let i=self.games.firstIndex(where:{title.isEmpty || $0.title.localizedCaseInsensitiveContains(title)}) else{return}
        self.profileSaveRoot=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("uncleed-profile-"+UUID().uuidString)
        try? fm.createDirectory(at:self.saveDir,withIntermediateDirectories:true)
        self.selectedIndex=i;self.choosing=false;self.inserted=true;self.lid=1;self.resizeForMachine();self.boot()
        if let seconds=CommandLine.arguments.first(where:{$0.hasPrefix("--profile-stop-after=")}).flatMap({Double($0.dropFirst(21))}){
          DispatchQueue.main.asyncAfter(deadline:.now()+seconds){
            let row:[String:Any]=["model":self.handheld.rawValue,"frames":emu_frames(),"audioSamples":emu_audio_samples(),"audioUnderrunSamples":emu_audio_underruns(),"backend":String(cString:emu_backend()),"width":emu_width(),"height":emu_height()]
            if let bytes=try? JSONSerialization.data(withJSONObject:row,options:.prettyPrinted){try? bytes.write(to:dataDir.appendingPathComponent(self.handheld.rawValue+"-worker-result.json"))}
            CoreDriver.shared.stop();self.running=false;NSApp.terminate(nil)
          }
        }
      }
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  func normalized(_ s: String) -> String {
    s.replacingOccurrences(of: "\\[[^]]*\\]|\\(Rev[^)]*\\)", with: "", options: .regularExpression)
      .lowercased().filter { $0.isLetter || $0.isNumber }
  }
  func scan() {
    let old = selected?.code
    let urls = ((try? fm.contentsOfDirectory(at: romDir, includingPropertiesForKeys: nil)) ?? [])
      .filter { romKind($0.pathExtension) == handheld }

    games = urls.compactMap { url in
      guard let f = try? FileHandle(forReadingFrom: url) else { return nil }
      let bytes = (try? f.read(upToCount: 512)) ?? Data()
      try? f.close()
      guard bytes.count >= 16 else { return nil }
      let code: String
      if handheld == .nds {
        code = String(bytes: bytes[12..<16], encoding: .ascii) ?? "UNKN"
      } else if handheld == .gba, bytes.count > 176 {
        code = String(bytes: bytes[172..<176], encoding: .ascii) ?? "GBA"
      } else {
        code = rawGameCode(url)
      }
      let meta = covers[code]
      let raw = url.deletingPathExtension().lastPathComponent
      let title = meta?.title ?? raw.components(separatedBy: " (").first ?? raw
      let img = NSImage(contentsOf: assets.appendingPathComponent("Covers/\(code).png"))
      if let img { _=prepareCartridgePalette(code,image:img) }
      return Game(
        url: url, code: code, title: title, detail: meta?.detail ?? "\(handheld.name) · \(code)",
        cover: img)
    }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    if let old, let i = games.firstIndex(where: { $0.code == old }) { selectedIndex = i }
    selectedIndex = min(selectedIndex, max(0, games.count - 1))
    for game in games where game.cover == nil { preload(game) }
    needsDisplay = true
  }
  func preload(_ game: Game) { lookupCover(game, kind: handheld) }
  func phaseTo(_ next: Phase) {
    phase = next
    if next == .inserting {MediaSound.shared.beginLoading(handheld.rawValue)}
    if (handheld == .gba || handheld == .psp) && (next == .playing || next == .library) { resizeForMachine() }
    stageStart = CACurrentMediaTime()
    history.append([
      "phase": next.rawValue, "uptime": stageStart, "gameCode": selected?.code ?? "",
      "lid": Double(lid),
    ])
    if history.count > 80 { history.removeFirst() }
    report()
    needsDisplay = true
  }
  func report() {
    let state: [String: Any] = [
      "viewport": ["width": Double(bounds.width), "height": Double(bounds.height), "scale": Double(scale), "offsetX": Double(offset.x), "offsetY": Double(offset.y), "canvasHeight": Double(canvasHeight),"screenFirst":focusActive,"gbc3D":usesGBC3D,"sceneFrames":usesGBC3D ? gbcStage.renderedFrames:0,"previewRotationGestures":usesGBC3D ? gbcStage.previewRotationGestures:0, "fullScreen": window?.styleMask.contains(.fullScreen) ?? false],
      "cartridgeColors": cartridgePalettes.mapValues {String(format:"#%06X",$0.dominantRGB)}, "coverStates": coverStates, "importing": importing, "pickerIndex": pickerIndex, "choosing": choosing, "pickerPage": pickerPage == .models ? "models" : "themes",
      "phase": phase.rawValue, "muted": muted, "handheld": handheld.rawValue,
      "core": core.lastPathComponent, "backend": String(cString:emu_backend()),
      "inserted": inserted, "running": running, "theme": theme, "bookMode": bookMode,
      "pose": Double(pose), "buttonPressCounts": inputCounts,
      "hoverHint": hoverLabel ?? "", "touchCount": touchCount, "heldButtons": Array(held).sorted(),
      "gameCode": selected?.code ?? "", "gameCount": games.count, "framebufferWidth": emu_width(),
      "framebufferHeight": emu_height(), "fps": emu_fps(),
      "cachedCoverCount": games.filter { $0.cover != nil }.count, "lid": Double(lid),
      "closedHeight": 330, "openHeight": 660, "frameCount": emu_frames(),
      "audioSamples": emu_audio_samples(), "transitions": history,
    ]
    if let d = try? JSONSerialization.data(withJSONObject: state, options: .prettyPrinted) {
      try? d.write(to: dataDir.appendingPathComponent("session-diagnostics.json"), options: .atomic)
    }
  }
  private var instantStateBusy=false
  @objc func instantSave(_ sender:Any?){instantState(false,slot:0)}
  @objc func instantLoad(_ sender:Any?){instantState(true,slot:0)}
  @objc func instantContinue(_ sender:Any?){instantState(true,slot:1)}
  private func instantState(_ restore:Bool,slot:Int){
    guard running,!instantStateBusy else{return};instantStateBusy=true;CoreDriver.shared.pause(true);releaseAll()
    if restore{let alert=NSAlert();alert.messageText="恢复这份即时存档？";alert.informativeText="当前画面会回到保存时的位置。游戏内存档仍单独保留。";alert.addButton(withTitle:"恢复");alert.addButton(withTitle:"取消");if alert.runModal() != .alertFirstButtonReturn{instantStateBusy=false;CoreDriver.shared.pause(false);return}}
    CoreDriver.shared.instantState(restore:restore,slot:slot){[weak self] result,message in guard let self else{return};if result == -2{CoreDriver.shared.stop();self.running=false;self.phaseTo(.idleOpen)};self.instantStateBusy=false;self.status=result==1 ? (restore ? "已恢复进度":"此刻已保存"):message;CoreDriver.shared.pause(false);self.notifyLibrary(self.status)}
  }
  @objc func inactive() { releaseAll() }
  func releaseAll() {
    if usesGBC3D { gbcStage.clearInputState() }
    for id in held { emu_button(Int32(id), 0) }
    held.removeAll()
    releases.removeAll()
    pressedAt.removeAll()
    pressedFrame.removeAll()
    touchActive = false
    touchRelease = 0
    emu_touch(0, 0, 0)
    emu_axis(0,0,0); emu_axis(0,1,0); stickX=0; stickY=0; analogDrag=false
    mouseButtonID = nil
    needsDisplay = true
  }
  @available(macOS 14.0,*) @objc func displayStep(_ link:CADisplayLink){displayTimestamp=link.timestamp;step();displayTimestamp=nil}
  @objc func step() {
    let now = displayTimestamp ?? CACurrentMediaTime()
    let dt = min(0.08, max(0,now - lastTime))
    lastTime = now
    let age = now - stageStart
    let target: CGFloat =
      handheld == .nds && bookMode && (phase == .playing || phase == .idleOpen) ? 1 : 0
    let previousPose = pose
    pose += (target - pose) * CGFloat(1 - exp(-dt * 12))
    if abs(target - pose) < 0.0005 { pose = target }
    if abs(previousPose - pose) > 0.00001 {
      needsDisplay = true
      tooltipSignature = ""
      window?.invalidateCursorRects(for: self)
    }
    if usesGBC3D && (choosing || phase == .library) { needsDisplay=true }
    if choosing && usesGBC3D && !gbcThemeDragging && now>pickerWheelActiveUntil{if pickerPage == .models{modelPosition += (CGFloat(pickerIndex)-modelPosition)*CGFloat(1-exp(-dt*14));if abs(modelPosition-CGFloat(pickerIndex))>0.001{needsDisplay=true}}else{gbcThemePosition += (CGFloat(pickerIndex)-gbcThemePosition)*CGFloat(1-exp(-dt*14));if abs(gbcThemePosition-CGFloat(pickerIndex))>0.001{needsDisplay=true}}}
    if !dragged { carousel += (CGFloat(selectedIndex) - carousel) * CGFloat(1 - exp(-dt * 15)) }
    for (id, deadline) in releases
    where now >= deadline && emu_frames() >= (pressedFrame[id] ?? 0) + 2 {
      held.remove(id)
      emu_button(Int32(id), 0)
      releases.removeValue(forKey: id)
    }
    if touchRelease > 0 && now >= touchRelease && emu_frames() >= touchDownFrame + 2 {
      emu_touch(0, 0, 0)
      touchActive = false
      touchRelease = 0
    }
    switch phase {
    case .focusing:
      if age >= 0.32 {
        phaseTo(.inserting)
        status = "正在插入卡带…"
      }
    case .inserting:
      MediaSound.shared.advanceLoading(handheld.rawValue,progress:CGFloat(age)/SpatialMachine.insertionTime(handheld.rawValue))
      if !mediaSeatSoundSent && age >= Double(SpatialMachine.insertionTime(handheld.rawValue))*(handheld == .psp ? 0.84:0.85){mediaSeatSoundSent=true}
      if age >= Double(SpatialMachine.insertionTime(handheld.rawValue)) {
        if !dual {
          inserted = true
          lid = 0
          phaseTo(.opening)
          break
        }
        inserted = true
        bootAfterOpening = true
        phaseTo(.opening)
        status = "卡带就位 · 正在打开机盖"
      }
    case .opening:
      if !dual {
        lid = smooth(CGFloat(age / 0.55))
        if age >= 0.55 {
          lid = 1
          phaseTo(.booting)
        }
        break
      }
      lid = smooth(CGFloat(age / 1.35))
      if age >= 1.35 {
        lid = 1
        if bootAfterOpening {
          phaseTo(.booting)
          status = "电源已接通 · 正在启动"
        } else {
          phaseTo(.idleOpen)
          status = "机盖已打开 · 电源关闭"
        }
        window?.invalidateCursorRects(for: self)
      }
    case .booting: if age > 0.14 { boot() }
    case .closing:
      if !dual {
        lid = closeFrom * (1 - smooth(CGFloat(age / (usesGBC3D ? 0.78:0.45))))
        if age >= (usesGBC3D ? 1.2:0.45) {
          lid = 0
          inserted = false
          phaseTo(.library)
          scan()
        }
        break
      }
      lid = closeFrom * (1 - smooth(CGFloat(age / 1.35)))
      if age >= 1.35 {
        lid = 0
        inserted = false
        phaseTo(.library)
        scan()
        status = "已关机 · 选择下一张卡带"
      }
    default: break
    }
    if running {
      CoreDriver.shared.pause(choosing || machineSelector?.isShown == true || instantStateBusy)
      videoFrame=CoreDriver.shared.snapshot().0
    }
    if now - lastReport > 2 {
      lastReport = now
      report()
    }
    if hoverLabel != nil || running || phase != .library
      || abs(carousel - CGFloat(selectedIndex)) > 0.001
    {
      needsDisplay = true
    }
  }
  func boot() {
    guard let game = selected else { return }
    let ok = CoreDriver.shared.start(core.path, game.url.path, saveDir.path,title:game.title)
    if ok != 0 {
      running = true
      ticks = 0;lastVideoSerial=0
      lastTime = CACurrentMediaTime()
      accumulator = 0
      phaseTo(.playing)
      status = "\(game.title) · 正在游玩"
    } else {
      phaseTo(.idleOpen)
      status = "启动失败：" + String(cString: emu_error())
      notifyLibrary(status)
    }
    window?.invalidateCursorRects(for: self)
    window?.resetCursorRects()
  }
  func beginInsert(_ index: Int) {
    guard phase == .library, games.indices.contains(index), !choosing else { return }
    selectedIndex = index
    inserted = false
    status = "已选择 \(games[index].title)"
    mediaSeatSoundSent=false
    phaseTo(usesGBC3D ? .inserting:.focusing)
  }
  var powerHint: String {
    inserted || running ? "电源 · 退出游戏，返回选卡" : "电源 · 返回机型首页"
  }
  func handlePower() {
    // Ignore repeated taps while a cartridge or hinge animation is in progress.
    guard phase == .library || phase == .playing || phase == .idleOpen else { return }
    hoverLabel = nil
    if inserted || running {
      closeMachine()
    } else {
      releaseAll()
      hoverLabel = nil
      choosing = true
      showModelPicker()
      resizeForMachine()
      tooltipSignature = ""
      needsDisplay = true
    }
  }
  func closeMachine() {
    guard phase == .playing || phase == .idleOpen || phase == .library else { return }
    if running {
      CoreDriver.shared.save()
      CoreDriver.shared.stop()
      running = false
      videoFrame = nil
    }
    releaseAll()
    if handheld != .nds {
      closeFrom = lid
      phaseTo(.closing)
      return
    }
    closeFrom = lid
    if lid > 0 {
      phaseTo(.closing)
      status = "已刷新存档 · 正在关机合盖"
    } else {
      bootAfterOpening = false
      phaseTo(.opening)
    }
    window?.invalidateCursorRects(for: self)
  }
  func fill(_ r: CGRect, _ c: NSColor, _ radius: CGFloat = 0) {
    c.setFill()
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
  }
  func stroke(_ r: CGRect, _ c: NSColor, _ radius: CGFloat = 0, _ width: CGFloat = 1) {
    c.setStroke()
    let p = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
    p.lineWidth = width
    p.stroke()
  }
  func text(
    _ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat = 14, _ c: NSColor = color(0xB7B8BC),
    _ weight: NSFont.Weight = .regular
  ) {
    (s as NSString).draw(
      at: CGPoint(x: x, y: y),
      withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: c])
  }
  func centered(
    _ s: String, _ cx: CGFloat, _ y: CGFloat, _ size: CGFloat = 14, _ c: NSColor = color(0xB7B8BC),
    _ weight: NSFont.Weight = .regular
  ) {
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: c,
    ]
    let w = (s as NSString).size(withAttributes: attrs).width
    (s as NSString).draw(at: CGPoint(x: cx - w / 2, y: y), withAttributes: attrs)
  }
  func gradient(_ r: CGRect, _ a: Int, _ b: Int, _ radius: CGFloat) {
    NSGradient(starting: color(a), ending: color(b))!.draw(
      in: NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius), angle: 90)
  }
  func line(_ points: [CGPoint], _ c: NSColor, _ width: CGFloat = 1) {
    guard let first = points.first else { return }
    let p = NSBezierPath()
    p.move(to: first)
    for q in points.dropFirst() { p.line(to: q) }
    c.setStroke()
    p.lineWidth = width
    p.lineJoinStyle = .round
    p.stroke()
  }
  func pill(_ s: String, _ r: CGRect, _ active: Bool = false) {
    fill(r, color(active ? 0xD8C59A : 0x252729), r.height / 2)
    stroke(r, color(active ? 0xE4D5B7 : 0x3C3E40), r.height / 2)
    centered(s, r.midX, r.minY + 12, 12, color(active ? 0x222222 : 0xD1D0CC), .medium)
  }
  func screen(_ r: CGRect, _ index: Int) {
    fill(r.insetBy(dx: -8, dy: -8), color(0x08090A), 5)
    stroke(r.insetBy(dx: -6, dy: -6), color(0x4C4E50), 4, 0.7)
    fill(r, color(0x182024), 1)
    if running, let image = videoFrame {
      let half = image.height / 2
      let bw = handheld == .n3ds && index == 1 ? image.width * 4 / 5 : image.width
      if let img = image.cropping(
        to: CGRect(x: (image.width-bw)/2, y: index * half, width: bw, height: half))
      {
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height)).draw(in: r)
      }
    } else {
      gradient(r, 0x24292B, 0x101518, 1)
      fill(
        CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.48),
        color(0xFFFFFF, 0.025), 1)
    }
  }
  var spatialLoadingFrame:CGRect{
    let size:CGSize=handheld == .gbc ? CGSize(width:380,height:620):handheld == .gba ? CGSize(width:720,height:380):handheld == .psp ? CGSize(width:720,height:350):CGSize(width:720,height:730)
    let h:CGFloat=handheld == .psp ? 260*SpatialMachine.mediaScale("psp"):(mediaSlots[handheld.rawValue]?.cardWidth ?? 148)*(mediaSlots[handheld.rawValue]?.ratio ?? 1)
    return SpatialMachine.loadingFrame(model:handheld.rawValue,size:size,available:CGRect(x:28,y:78,width:664,height:670),maxScale:1,mediaHeight:h)
  }
  var spatialLoadingScale:CGFloat{spatialLoadingFrame.width/(handheld == .gbc ? 380:720)}
  var spatialCardStride:CGFloat{(handheld == .psp ? 260*SpatialMachine.mediaScale("psp"):mediaSlots[handheld.rawValue]?.cardWidth ?? 148)*spatialLoadingScale+60}
  func cardRect(_ index: Int) -> CGRect {
    if usesGBC3D {
      let center=CGFloat(games.count)*spatialCardStride-60<=660 ? CGFloat(max(0,games.count-1))/2:carousel,d=CGFloat(index)-center
      let w:CGFloat=(spatialCardStride-60)*(1-min(0.04,abs(d)*0.02)),ratio:CGFloat=handheld == .psp ? 1:mediaSlots[handheld.rawValue]?.ratio ?? 1
      return CGRect(x:360+d*spatialCardStride-w/2,y:360-w*ratio/2,width:w,height:w*ratio)
    }
    let center=games.count<=3 ? CGFloat(max(0,games.count-1))/2:carousel
    if modern { let d=CGFloat(index)-center; let w:CGFloat=(handheld == .psp ? 155 : 135)*(1-min(0.12,abs(d)*0.1)); return CGRect(x:360+d*184-w/2,y:96,width:w,height:w) }
    if handheld != .nds {
      let d = CGFloat(index) - center
      let q = 1 - min(0.12, abs(d) * 0.10)
      let w: CGFloat = (handheld == .gba ? 150 : 120) * q
      let h = w * (handheld == .gba ? 104 / 180 : 150 / 132)
      return CGRect(x: 360 + d * 184 - w / 2, y: 240 - h, width: w, height: h)
    }
    let distance = CGFloat(index) - center
    let q = 1 - min(0.12, abs(distance) * 0.1)
    let w: CGFloat = 128 * q
    return CGRect(
      x: 360 + distance * 184 - w / 2, y: 103 + (1 - q) * 50, width: w, height: 188 * w / 174)
  }
  func drawCard(_ game: Game, _ r: CGRect, _ highlighted: Bool = false) {
    if modern { drawModernMedia(game,r,highlighted); return }
    if handheld != .nds {
      drawClassicCard(game, r, highlighted)
      return
    }
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform()
    t.translateX(by: r.minX, yBy: r.minY)
    t.scaleX(by: r.width / 174, yBy: r.height / 188)
    t.concat()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.45)
    shadow.shadowBlurRadius = 14
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()
    let p = NSBezierPath()
    p.move(to: CGPoint(x: 7, y: 0))
    p.line(to: CGPoint(x: 153, y: 0))
    p.line(to: CGPoint(x: 153, y: 9))
    p.line(to: CGPoint(x: 173, y: 9))
    p.line(to: CGPoint(x: 173, y: 177))
    p.line(to: CGPoint(x: 164, y: 187))
    p.line(to: CGPoint(x: 9, y: 187))
    p.line(to: CGPoint(x: 0, y: 178))
    p.line(to: CGPoint(x: 0, y: 8))
    p.close()
    color(0x111916,0.4).setFill()
    p.fill()
    NSShadow().set()
    let tint = cartridgeTint(game)
    translucentCartridge(p,tint:tint)
    color(highlighted ? 0xB6A57C : 0x626568).setStroke()
    p.lineWidth = highlighted ? 1.8 : 1
    p.stroke()
    fill(CGRect(x: 7, y: 8, width: 155, height: 157), color(0x161819), 5)
    stroke(CGRect(x: 8, y: 10, width: 153, height: 155), color(0x0C0D0E), 4, 2)
    let label = CGRect(x: 11, y: 13, width: 147, height: 147)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: label, xRadius: 3, yRadius: 3).addClip()
    if let image = game.cover {
      image.draw(in: label)
    } else {
      gradient(label, 0xC6C6BF, 0x818680, 2)
      centered("NINTENDO DS", 84, 44, 12, color(0x232628), .bold)
      centered(game.code, 84, 87, 20, color(0x24272B), .semibold)
    }
    NSGraphicsContext.restoreGraphicsState()
    text("NTR-005", 13, 171, 7, cartridgeInk(tint), .bold)
    text(game.code + " • DS", 104, 171, 7, cartridgeInk(tint))
    line([CGPoint(x: 167, y: 22), CGPoint(x: 167, y: 166)], color(0x777A7C, 0.4), 1)
    fill(CGRect(x: 63, y: 178, width: 46, height: 3), color(0x191B1C), 1)
    NSGraphicsContext.restoreGraphicsState()
  }
  func drawShelf() {
    guard !choosing, phase != .playing, phase != .idleOpen else { return }
    let alpha = 1 - smooth(min(1, lid * 1.7))
    guard alpha > 0.002 else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current?.cgContext.setAlpha(alpha)
    for i in games.indices where games.count<=3 || abs(CGFloat(i) - carousel) < 2 {
      if i == selectedIndex && (phase == .inserting || inserted) { continue }
      let r = cardRect(i)
      drawCard(games[i], r, i == selectedIndex)
      let labelStyle=NSMutableParagraphStyle()
      labelStyle.alignment = .center
      labelStyle.lineBreakMode = .byTruncatingTail
      (games[i].title as NSString).draw(in:CGRect(x:r.midX-85,y:r.maxY+18,width:170,height:18),withAttributes:[.font:NSFont.systemFont(ofSize:11,weight:.medium),.foregroundColor:color(i == selectedIndex ? 0xE4D9BC : 0x959B98),.paragraphStyle:labelStyle])
    }
    if phase == .library {
      centered("滑动选卡 · 点击插入", 360, 317, 10, color(0x828C87))
      for i in games.indices {
        fill(
          CGRect(x: CGFloat(i - games.count / 2) * 12 + 357, y: 345, width: 5, height: 5),
          color(i == selectedIndex ? 0xDAC79C : 0x505954), 2.5)
      }
    }
    NSGraphicsContext.restoreGraphicsState()
  }
  func dragon(_ origin: CGPoint, _ mirror: Bool) {
    NSGraphicsContext.saveGraphicsState()
    let tr = NSAffineTransform()
    tr.translateX(by: origin.x, yBy: origin.y)
    tr.scaleX(by: mirror ? -1 : 1, yBy: 1)
    tr.concat()
    let points: [CGPoint] = [
      .init(x: 0, y: 98), .init(x: 18, y: 55), .init(x: 41, y: 37), .init(x: 36, y: 14),
      .init(x: 56, y: 29), .init(x: 72, y: 13), .init(x: 77, y: 37), .init(x: 105, y: 42),
      .init(x: 92, y: 58), .init(x: 71, y: 62), .init(x: 65, y: 86), .init(x: 85, y: 108),
      .init(x: 143, y: 56), .init(x: 206, y: 22), .init(x: 180, y: 64), .init(x: 159, y: 73),
      .init(x: 184, y: 85), .init(x: 150, y: 94), .init(x: 173, y: 115), .init(x: 134, y: 113),
      .init(x: 141, y: 137), .init(x: 109, y: 124), .init(x: 91, y: 139), .init(x: 104, y: 170),
      .init(x: 130, y: 192), .init(x: 113, y: 218), .init(x: 82, y: 204), .init(x: 73, y: 179),
      .init(x: 58, y: 154), .init(x: 48, y: 184), .init(x: 25, y: 208), .init(x: 5, y: 206),
      .init(x: 22, y: 190), .init(x: 29, y: 162), .init(x: 37, y: 134), .init(x: 20, y: 128),
      .init(x: -4, y: 145), .init(x: -27, y: 132), .init(x: -3, y: 124), .init(x: 0, y: 98),
    ]
    line(points, color(0x080A0B, 0.9), 2)
    line(points.map { CGPoint(x: $0.x + 0.6, y: $0.y + 1) }, color(0x656B6E, 0.23), 0.75)
    line(
      [CGPoint(x: 85, y: 108), CGPoint(x: 123, y: 79), CGPoint(x: 180, y: 64)], color(0x0A0B0C), 1.2
    )
    line(
      [CGPoint(x: 82, y: 113), CGPoint(x: 125, y: 99), CGPoint(x: 159, y: 73)], color(0x0A0B0C), 1.2
    )
    line(
      [CGPoint(x: 77, y: 120), CGPoint(x: 119, y: 117), CGPoint(x: 150, y: 94)], color(0x0A0B0C),
      1.2)
    line(
      [
        CGPoint(x: 0, y: 98), CGPoint(x: -25, y: 72), CGPoint(x: -52, y: 52),
        CGPoint(x: -44, y: 98), CGPoint(x: -18, y: 119),
      ], color(0x0B0C0D), 2)
    fill(CGRect(x: 68, y: 44, width: 5, height: 2), color(0x050607), 1)
    NSGraphicsContext.restoreGraphicsState()
  }
  func outerLid() {
    if handheld == .n3ds { draw3DSOuter(); return }
    gradient(CGRect(x: 0, y: 0, width: 640, height: 330), shellHi, shellLo, 22)
    stroke(CGRect(x: 2, y: 2, width: 636, height: 326), color(0x74797C, 0.6), 20, 1)
    stroke(CGRect(x: 8, y: 8, width: 624, height: 314), color(0x15181B), 16, 1.2)
    for i in 0..<230 {
      let x = CGFloat((i * 149) % 617 + 12)
      let y = CGFloat((i * 73) % 295 + 15)
      fill(CGRect(x: x, y: y, width: 1, height: 1), color(0xC8C9C6, 0.08))
    }
    if theme == 0, let image = lidTexture {
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(
        roundedRect: CGRect(x: 9, y: 9, width: 622, height: 312), xRadius: 15, yRadius: 15
      ).addClip()
      image.draw(in: CGRect(x: 9, y: 9, width: 622, height: 312))
      NSGraphicsContext.restoreGraphicsState()
    }
    if theme == 0 {
      centered("P O K É M O N    B L A C K", 311, 292, 11, color(0xC7AE70), .medium)
    } else if theme == 1 {
      drawMario(CGPoint(x: 526, y: 207), 3)
      text("SUPER MARIO BROS. 25th Anniversary", 365, 302, 10, color(0x4C0B08), .semibold)
    } else {
      for y in [CGFloat(111), CGFloat(167)] {
        stroke(CGRect(x: 297, y: y, width: 46, height: 39), color(0x80784E, 0.7), 7, 2)
        stroke(CGRect(x: 302, y: y + 5, width: 36, height: 29), color(0xCDC59C), 3, 1)
      }
      let tri = NSBezierPath()
      for points in [
        [CGPoint(x: 536, y: 208), CGPoint(x: 509, y: 254), CGPoint(x: 563, y: 254)],
        [CGPoint(x: 509, y: 254), CGPoint(x: 482, y: 300), CGPoint(x: 536, y: 300)],
        [CGPoint(x: 563, y: 254), CGPoint(x: 536, y: 300), CGPoint(x: 590, y: 300)],
      ] {
        tri.move(to: points[0])
        tri.line(to: points[1])
        tri.line(to: points[2])
        tri.close()
      }
      color(0xB5A04D).setFill()
      tri.fill()
    }
    if theme != 2 {
      fill(CGRect(x: 580, y: 276, width: 24, height: 24), color(0x0A0D10), 12)
      stroke(CGRect(x: 581, y: 277, width: 22, height: 22), color(0x434B50), 11)
      fill(CGRect(x: 588, y: 284, width: 7, height: 7), color(0x222B31), 4)
    }
    line([CGPoint(x: 24, y: 17), CGPoint(x: 603, y: 17)], color(0xFFFFFF, 0.04))
  }
  func innerLid() {
    if handheld == .n3ds { draw3DSInner(); return }
    gradient(CGRect(x: 0, y: 0, width: 640, height: 330), shellHi, shellLo, 21)
    stroke(CGRect(x: 3, y: 3, width: 634, height: 324), color(0x65696B, 0.6), 19)
    fill(CGRect(x: 26, y: 17, width: 588, height: 295), color(shellLo), 10)
    screen(CGRect(x: 160, y: 44, width: 320, height: 240), 0)
    if theme == 2 {
      for cx in [CGFloat(76), CGFloat(556)] {
        for dx in [-16, 0, 16] {
          for dy in [0, 15] {
            fill(
              CGRect(x: cx + CGFloat(dx), y: 151 + CGFloat(dy), width: 4, height: 4),
              color(0x22271E), 2)
          }
        }
      }
    } else {
      for x in [CGFloat(75), CGFloat(554)] {
        fill(CGRect(x: x, y: 206, width: 15, height: 5), color(0x080A0A), 2)
        stroke(CGRect(x: x - 1, y: 205, width: 17, height: 7), color(0x575B5C, 0.4), 3, 0.6)
      }
    }
    for p in [
      CGPoint(x: 53, y: 49), CGPoint(x: 579, y: 49), CGPoint(x: 53, y: 270),
      CGPoint(x: 579, y: 270),
    ] { stroke(CGRect(x: p.x, y: p.y, width: 14, height: 14), color(0x505457, 0.45), 3, 0.8) }
    centered("Nintendo", 320, 298, 8, color(0x787D7E), .semibold)
  }
  func drawBase() {
    if handheld == .n3ds { draw3DSBase(); return }
    let y = baseY
    fill(CGRect(x: 277, y: y + 14, width: 646, height: 331), color(0x000000, 0.32), 24)
    gradient(CGRect(x:280,y:y-7,width:640,height:38),shellHi,shellLo,15)
    gradient(CGRect(x: 280, y: y, width: 640, height: 330), shellHi, shellLo, 22)
    stroke(CGRect(x: 282, y: y + 2, width: 636, height: 326), color(0x71787B, 0.6), 20)
    stroke(CGRect(x: 287, y: y + 7, width: 626, height: 314), color(0x0C1012, 0.8), 16)
    screen(bottom, 1)
    plasticDpad(CGRect(x:316,y:y+97,width:93,height:93),tint:keyHi)
    for (name, id, r0) in buttons {
      let down=held.contains(id), hover=controlHovered(id)
      if id == 10 || id == 11 {
        continue
      } else if id == 2 || id == 3 {
        let dot=CGRect(x:r0.minX,y:r0.minY+3,width:18,height:18)
        _=plasticKey(dot,tint:keyHi,radius:9,down:down,hover:hover,separable:true)
        text(name,r0.minX+24,r0.minY+6,9,color(ink),.medium)
      } else {
        let cap=plasticKey(r0,tint:keyHi,radius:r0.width/2,down:down,hover:hover,separable:true)
        if !omitControlCaps { centered(name,cap.midX,cap.midY-10,17,color(ink),.semibold) }
      }
    }
    text("POWER",307,y+278,7,color(ink),.medium)
    let powerCap=plasticKey(powerRect,tint:keyHi,radius:12)
    powerSymbol(CGPoint(x:powerCap.midX,y:powerCap.midY),8,color(ink))
    fill(CGRect(x: 890, y: y + 311, width: 5, height: 10), color(running ? 0x95D9AC : 0x20292A), 2)
    fill(CGRect(x: 870, y: y + 311, width: 5, height: 10), color(0x303D40), 2)
    fill(CGRect(x: 746, y: y + 324, width: 49, height: 4), color(0x080A0B), 2)
    fill(CGRect(x: 813, y: y + 321, width: 12, height: 7), color(0x05080A), 3)
    text("♫", 831, y + 316, 9, color(0x9FA6A8))
  }
  func drawMachine() {
    if handheld == .psp { drawPSPMachine(); return }
    if handheld != .nds && handheld != .n3ds {
      drawClassicMachine()
      return
    }
    NSGraphicsContext.saveGraphicsState()
    let rotation = NSAffineTransform()
    rotation.translateX(by: 360, yBy: 410)
    rotation.rotate(byDegrees: -90 * pose)
    rotation.translateX(by: -360, yBy: -410)
    rotation.concat()
    let scene = NSAffineTransform()
    scene.translateX(by: -240, yBy: 0)
    scene.concat()
    drawBase()
    // A rigid lid rotates about one fixed hinge. Perspective changes the far edge,
    // while its two faces share exactly the same projected corners.
    let angle = lid * CGFloat.pi * 165 / 180
    let pitch = CGFloat.pi * 15 / 180
    let z = 330 * sin(angle)
    let depth = 1 - z / 2400
    let farY = baseY + 330 * cos(angle + pitch) / cos(pitch) / depth
    let nearL = CGPoint(x: 280, y: baseY)
    let nearR = CGPoint(x: 920, y: baseY)
    let farL = CGPoint(x: 600 - 320 / depth, y: farY)
    let farR = CGPoint(x: 600 + 320 / depth, y: farY)
    let inner = cos(angle + pitch) < 0
    if abs(farY - baseY) > 0.7 {
      let image = NSImage(size: NSSize(width: 640, height: 330))
      image.lockFocusFlipped(true)
      if inner { innerLid() } else { outerLid() }
      image.unlockFocus()
      var r = CGRect(
        x: min(nearL.x, farL.x), y: min(baseY, farY), width: max(640, 640 / depth),
        height: abs(farY - baseY))
      r = r.integral
      if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
        let filter = CIFilter(name: "CIPerspectiveTransform")
      {
        filter.setValue(CIImage(cgImage: cg), forKey: kCIInputImageKey)
        let corners = inner ? [farL, farR, nearR, nearL] : [nearL, nearR, farR, farL]
        for (key, p) in zip(
          ["inputTopLeft", "inputTopRight", "inputBottomRight", "inputBottomLeft"], corners)
        { filter.setValue(CIVector(x: p.x - r.minX, y: r.maxY - p.y), forKey: key) }
        if let output = filter.outputImage,
          let result = ciContext.createCGImage(output, from: CGRect(origin: .zero, size: r.size))
        {
          NSImage(cgImage: result, size: r.size).draw(in: r)
        }
      }

    }
    gradient(CGRect(x: 285, y: baseY - 7, width: 630, height: 21), keyHi, handheld == .n3ds ? 0x171B20 : shellLo, 10)
    for x in [CGFloat(341), CGFloat(846)] {
      line([CGPoint(x: x, y: baseY - 4), CGPoint(x: x, y: baseY - 1)], color(0x0A0D0F,0.55), 1)
    }
    if lid > 0.1 {
      for (name,id,r) in buttons where id == 10 || id == 11 {
        shoulderKey(r,right:id == 11,tint:keyHi,name:name,down:held.contains(id),hover:controlHovered(id))
      }
    }
    if lid > 0.1 {
      fill(CGRect(x: 594, y: baseY - 1, width: 11, height: 11), color(0x080B0D), 6)
      text("MIC", 609, baseY + 1, 6, color(ink))
    }
    if lid < 0.1,let slot=mediaSlots[handheld.rawValue] {fill(CGRect(x:slot.x+240,y:baseY-5,width:slot.width,height:slot.height),color(0x07090A),2)}
    NSGraphicsContext.restoreGraphicsState()
  }
  func drawFlyingCard() {
    guard phase == .inserting else { return }
    if modern { drawModernFlyingMedia(); return }
    if handheld != .nds {
      drawClassicFlyingCard()
      return
    }
    guard phase == .inserting, let game = selected else { return }
    let t = CGFloat(min(1, (CACurrentMediaTime() - stageStart) / 1.2))
    let source = cardRect(selectedIndex)
    let travel = smooth(min(1, t / 0.72))
    let w = mix(source.width, mediaSlots["nds"]!.cardWidth, travel)
    let h = w * 188 / 174
    let x = mix(source.midX, 360, travel) - w / 2
    var y = mix(source.minY, baseY - h - 8, travel) - sin(travel * CGFloat.pi) * 54
    if t > 0.72 { y += smooth((t - 0.72) / 0.28) * (h + 15) }
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: CGRect(x: 0, y: 0, width: 1200, height: baseY - 5)).addClip()
    drawCard(game, CGRect(x: x, y: y, width: w, height: h), false)
    NSGraphicsContext.restoreGraphicsState()
  }
  override func draw(_ dirtyRect: NSRect) {
    fill(bounds, color(0x191E1D))
    if !CommandLine.arguments.contains("--render-source"){gbcStage.sync();mechanicalStage.sync()}
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform()
    t.translateX(by: offset.x, yBy: offset.y)
    t.scale(by: scale)
    t.concat()
    if choosing {
      drawHandheldPicker()
      drawImportButton()
      drawLibraryNotice()
      NSGraphicsContext.restoreGraphicsState()
      refreshTooltips()
      return
    }
    if usesGBC3D && !focusActive{drawGBCCardLabels()}else{drawShelf()}
    if focusActive{drawFocusedPixels()}else if !usesGBC3D{drawMachine();drawFlyingCard()}
    drawMachineNavigation()
    drawImportButton()
    for i in (handheld == .nds ? [4,1,3,0]:[4,1,0]) {
      let r = toolbar(i)
      fill(r, color(0x2D3431), 10)
      let c = color(i == 3 && !running ? 0x69736C : 0xD2D8D0)
      if i == 4 {
        for (dy,dx) in [(CGFloat(12),CGFloat(14)),(20,26),(28,19)]{line([CGPoint(x:r.minX+9,y:r.minY+dy),CGPoint(x:r.maxX-9,y:r.minY+dy)],c,1.2);fill(CGRect(x:r.minX+dx-3,y:r.minY+dy-3,width:6,height:6),c,3)}
      } else if i == 0 {
        powerSymbol(CGPoint(x: r.midX, y: r.midY), 8, c)
      } else if i == 1 {
        if handheld == .psp {stroke(r.insetBy(dx:10,dy:10),c,10,1.4);stroke(r.insetBy(dx:18,dy:18),c,2,1)} else {
        stroke(r.insetBy(dx: 12, dy: 10), c, 2, 1.4)
        stroke(CGRect(x: r.minX + 15, y: r.minY + 13, width: 10, height: 10), c, 1, 1)
        for j in 0..<3 {
          line(
            [
              CGPoint(x: r.minX + 16 + CGFloat(j) * 4, y: r.minY + 26),
              CGPoint(x: r.minX + 16 + CGFloat(j) * 4, y: r.minY + 29),
            ], c, 1)
        }
        }
      } else {
        let q = NSAffineTransform()
        NSGraphicsContext.saveGraphicsState()
        q.translateX(by: r.midX, yBy: r.midY)
        if bookMode { q.rotate(byDegrees: -90) }
        q.concat()
        stroke(CGRect(x: -8, y: -12, width: 16, height: 24), c, 2, 1.3)
        for y in [CGFloat(-9), CGFloat(2)] {
          stroke(CGRect(x: -5, y: y, width: 10, height: 7), c, 1, 1)
        }
        NSGraphicsContext.restoreGraphicsState()
        line(
          [
            CGPoint(x: r.minX + 28, y: r.minY + 11), CGPoint(x: r.minX + 32, y: r.minY + 15),
            CGPoint(x: r.minX + 28, y: r.minY + 19),
          ], c, 1.2)
      }
    }

    drawLibraryNotice()
    if let hint = hoverLabel, CACurrentMediaTime() - hoverSince > 0.4, !choosing {
      let w =
        (hint as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width + 24
      let x = max(8, min(712 - w, hoverPoint.x - w / 2))
      let y = max(58, hoverPoint.y - 42)
      fill(CGRect(x: x, y: y, width: w, height: 29), color(0xE4E8DF), 7)
      centered(hint, x + w / 2, y + 7, 12, color(0x263229))
    }
    NSGraphicsContext.restoreGraphicsState()
    refreshTooltips()
  }
  let ciContext = CIContext(options: [
    .cacheIntermediates: false, .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
  ])
  var theme = 0
  var shellHi: Int { if handheld == .n3ds { return [0xC29A35,0x303238,0xD52C41][min(2,max(0,theme))] }; return [0x393E41, 0xDF2318, 0xC2B990][min(2, max(0, theme))] }
  var shellLo: Int { if handheld == .n3ds { return [0x785511,0x101216,0x8F1128][min(2,max(0,theme))] }; return [0x202628, 0xA8100B, 0x918760][min(2, max(0, theme))] }
  var keyHi: Int { if handheld == .n3ds { return 0x454B52 }; return [0x697174, 0xEC3B30, 0xCEC69F][min(2, max(0, theme))] }
  var keyLo: Int { [0x30373A, 0xB2160D, 0x9D936E][min(2, max(0, theme))] }
  var ink: Int { theme == 2 ? 0x35372A : 0xE1E4DE }
  var powerRect: CGRect {
    if modern { return modernPowerRect.offsetBy(dx:240,dy:0) }
    if handheld != .nds { return classicPowerRect }
    return CGRect(x: 309, y: baseY + 294, width: 25, height: 25)
  }
  func toolbar(_ i: Int) -> CGRect {
    if i == 4{return CGRect(x:handheld == .nds ? 472:520,y:14,width:40,height:40)}
    if i == 2 { return CGRect(x:24,y:14,width:handheld == .nds ? 400:448,height:40) }
    return CGRect(
      x: [0: CGFloat(664), 1: (handheld == .nds ? 520 : 568), 3: 616][i] ?? 616, y: 14, width: 40,
      height: 40)
  }
  func machinePoint(_ p: CGPoint) -> CGPoint {
    let a = -pose * CGFloat.pi / 2
    let dx = p.x - 360
    let dy = p.y - 410
    return CGPoint(x: 600 + dx * cos(a) + dy * sin(a), y: 410 - dx * sin(a) + dy * cos(a))
  }
  func displayPoint(_ p: CGPoint) -> CGPoint {
    let a = -pose * CGFloat.pi / 2
    let dx = p.x - 360
    let dy = p.y - 410
    return CGPoint(x: 360 + dx * cos(a) - dy * sin(a), y: 410 + dx * sin(a) + dy * cos(a))
  }
  func displayRect(_ r: CGRect) -> CGRect {
    let points = [
      CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY),
      CGPoint(x: r.minX, y: r.maxY),
    ].map { displayPoint($0) }
    let xs = points.map { $0.x }
    let ys = points.map { $0.y }
    return CGRect(
      x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
  }
  func themeRect(_ i: Int) -> CGRect {
    CGRect(x: 38 + CGFloat(i % 3) * 220 + (i >= 3 ? 110 : 0), y: 160 + CGFloat(i / 3) * 270, width: 204, height: 205)
  }
  func drawMario(_ origin: CGPoint, _ pixel: CGFloat) {
    let rows = [
      "0000011111000000", "0000111111111000", "0000111010100000", "0001011010111000",
      "0001011101011100", "0000111100000000", "0000011111100000", "0000110110110000",
      "0001110110111000", "0011111111111100", "0000011111100000", "0000111001110000",
      "0001110000111000",
    ]
    for (y, row) in rows.enumerated() {
      for (x, c) in row.enumerated() where c == "1" {
        fill(
          CGRect(
            x: origin.x + CGFloat(x) * pixel, y: origin.y + CGFloat(y) * pixel, width: pixel,
            height: pixel), color(0x390B06))
      }
    }
  }
  func powerSymbol(_ p: CGPoint, _ radius: CGFloat, _ c: NSColor) {
    let path = NSBezierPath()
    path.appendArc(withCenter: p, radius: radius, startAngle: -55, endAngle: 235, clockwise: false)
    c.setStroke()
    path.lineWidth = 1.7
    path.stroke()
    line([CGPoint(x: p.x, y: p.y - radius - 2), CGPoint(x: p.x, y: p.y - 1)], c, 1.7)
  }
  var hoverLabel: String?, hoverPoint = CGPoint.zero, hoverSince = 0.0
  var hoverEntries: [(CGRect, String)] = []
  var tooltipSignature = "", tooltipLabels: [NSView.ToolTipTag: String] = [:]
  func refreshTooltips() {
    let signature = "\(bounds)-\(choosing)-\(phase.rawValue)-\(bookMode)-\(pose)-\(handheld)-\(pickerPage)"
    if signature == tooltipSignature { return }
    tooltipSignature = signature
    removeAllToolTips()
    if choosing {
      hoverEntries = [(importRect, "添加 ROM · ⌘O")]
      if pickerPage == .themes {hoverEntries.append((CGRect(x:28,y:28,width:160,height:40),"返回选择机型"));for i in 0..<3{hoverEntries.append((themeGridRect(i),handheld.editions[i]))}}else{for (i,kind) in Handheld.allCases.enumerated(){hoverEntries.append((modelRect(i),"选择 "+kind.name))}}
      tooltipLabels.removeAll(); return
    }
    tooltipLabels.removeAll()
    var entries: [(CGRect, String)] = [
      (toolbar(0), powerHint),
      (toolbar(1), "更换卡带 · 先保存并关机"), (toolbar(2), "返回首页 · 选择机型与主题"),
      (
        toolbar(3),
        !running ? "开机后切换书本握法" : (bookMode ? "切换为横握 · 机身恢复上下双屏" : "切换为书本握法 · 整机逆时针旋转 90°")
      ),
    ]
    entries.append((importRect,"添加 ROM · ⌘O"));entries.append((toolbar(4),"显示调整 · 大小、位置与大屏模式"))
    if !choosing && !focusActive && lid > 0.99 {
      let mappings = [
        8: "A · 键盘 X", 0: "B · 键盘 Z", 9: "X · 键盘 S", 1: "Y · 键盘 A", 10: "L · 键盘 Q", 11: "R · 键盘 W",
        3: "START · Return", 2: "SELECT · 右 Shift", 4: "上 · ↑", 5: "下 · ↓", 6: "左 · ←", 7: "右 · →",
      ]
      entries += (buttons + dpad).map {
        (displayRect($0.2.offsetBy(dx: -240, dy: 0)), mappings[$0.1] ?? $0.0)
      }
      entries.append(
        (
          displayRect(powerRect.offsetBy(dx: -240, dy: 0)),
          powerHint
        ))
    }
    if handheld != .nds { entries.remove(at: 3) }
    if handheld == .psp { entries = entries.map { ($0.0, $0.1.replacingOccurrences(of:"A · 键盘 X",with:"○ · 键盘 X").replacingOccurrences(of:"B · 键盘 Z",with:"× · 键盘 Z").replacingOccurrences(of:"X · 键盘 S",with:"△ · 键盘 S").replacingOccurrences(of:"Y · 键盘 A",with:"□ · 键盘 A")) } }
    if modern && !focusActive && lid>0.99 { entries.append((modernStickRect,"模拟摇杆 · 拖动或 I/J/K/L")); entries += modernUtilities }
    if handheld == .gba && !focusActive {
      entries.append(
        (
          classicRect(CGRect(x: 16, y: 260, width: 25, height: 48)),
          muted ? "音量 · 点击恢复声音" : "音量 · 点击静音"
        ))
    }
    hoverEntries = entries
    for (r, label) in entries {
      let viewRect = CGRect(
        x: offset.x + r.minX * scale, y: offset.y + r.minY * scale, width: r.width * scale,
        height: r.height * scale)
      _ = viewRect
      _ = label
    }
  }
  func view(
    _ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
    userData: UnsafeMutableRawPointer?
  ) -> String { tooltipLabels[tag] ?? "" }
  func point(_ e: NSEvent) -> CGPoint {
    let p = convert(e.locationInWindow, from: nil)
    return CGPoint(x: (p.x - offset.x) / scale, y: (p.y - offset.y) / scale)
  }
  func set(_ id: Int, _ down: Bool) {
    if down {
      inputCounts[String(id), default: 0] += 1
      pressedAt[id] = CACurrentMediaTime()
      pressedFrame[id] = emu_frames()
      releases.removeValue(forKey: id)
      held.insert(id)
      emu_button(Int32(id), 1)
    } else {
      releases[id] = max(CACurrentMediaTime(), (pressedAt[id] ?? 0) + 0.025)
    }
    needsDisplay = true
  }
  func touch(_ p: CGPoint, _ down: Bool) {
    if down {
      if !touchActive {
        touchCount += 1
        touchDownFrame = emu_frames()
      }
      touchActive = true
      touchRelease = 0
    }
    let u = max(0, min(1, (p.x - bottom.minX) / bottom.width))
    let v = max(0, min(1, (p.y - bottom.minY) / bottom.height))
    if !down { touchActive = false }
    emu_touch(Int32(handheld == .n3ds ? (0.1+u*0.8)*65534-32767 : u*65534-32767), Int32(v*32767), down ? 1 : 0)
  }
  func choose(_ delta: Int) {
    guard phase == .library, !games.isEmpty else { return }
    selectedIndex = max(0, min(games.count - 1, selectedIndex + delta))
    status = games[selectedIndex].title
    needsDisplay = true
  }
  override func scrollWheel(with e: NSEvent) {
    if choosing && usesGBC3D {
      if e.momentumPhase != []{pickerWheelActiveUntil=CACurrentMediaTime();return}
      let delta=abs(e.scrollingDeltaX)>abs(e.scrollingDeltaY) ? e.scrollingDeltaX:e.scrollingDeltaY
      let last=CGFloat((pickerPage == .models ? Handheld.allCases.count:handheld.editions.count)-1)
      if !e.hasPreciseScrollingDeltas {if CACurrentMediaTime()>pickerWheelActiveUntil{pickerIndex=max(0,min(Int(last),pickerIndex+(delta>0 ? -1:1)));pickerWheelActiveUntil=CACurrentMediaTime()+0.18};needsDisplay=true;return}
      if e.phase.contains(.began) || !pickerWheelGesture {pickerWheelGesture=true;pickerWheelAnchor=pickerPage == .models ? modelPosition:gbcThemePosition}
      let current=pickerPage == .models ? modelPosition:gbcThemePosition
      let next=PickerMotion.trackpadPosition(current:current,delta:delta,anchor:pickerWheelAnchor,count:Int(last)+1)
      if pickerPage == .models{modelPosition=next}else{gbcThemePosition=next};pickerIndex=Int(next.rounded());pickerWheelActiveUntil=CACurrentMediaTime()+0.12
      if e.phase.contains(.ended) || e.phase.contains(.cancelled){pickerWheelGesture=false}
      if e.momentumPhase != []{pickerWheelActiveUntil=CACurrentMediaTime();return}
      needsDisplay=true;return
    }
    guard phase == .library, !choosing else { return }
    scrollAmount +=
      abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) ? e.scrollingDeltaX : e.scrollingDeltaY
    if abs(scrollAmount) > 14 {
      choose(scrollAmount > 0 ? -1 : 1)
      scrollAmount = 0
    }
  }
  override func mouseDown(with e: NSEvent) {
    window?.makeFirstResponder(self)
    let p = point(e)
    let m = machinePoint(p)
    updateHover(p)
    if importRect.contains(p) { importROM(); return }
    if importing { return }
    if usesGBC3D,choosing,let i=pageDotHit(p,count:pickerPage == .models ? Handheld.allCases.count:handheld.editions.count,index:pickerIndex,y:632){pickerIndex=i;needsDisplay=true;return}
    if usesGBC3D,!choosing,phase == .library,let i=pageDotHit(p,count:games.count,index:selectedIndex,y:680){selectedIndex=i;needsDisplay=true;return}
    if choosing {
      if pickerPage == .themes {
        if usesGBC3D && !CGRect(x:28,y:28,width:160,height:40).contains(p){if CGRect(x:260,y:660,width:200,height:44).contains(p){confirmTheme(pickerIndex);return};shelfDown=p;shelfDownIndex=pickerIndex;gbcThemeDragging=true;dragged=false;return}
        if CGRect(x:28,y:28,width:160,height:40).contains(p) {showModelPicker();return}
        for i in 0..<3 where themeGridRect(i).contains(p) {confirmTheme(i);return}
      } else {
        if usesGBC3D{if CGRect(x:260,y:660,width:200,height:44).contains(p){chooseMachine(Handheld.allCases[pickerIndex]);return};shelfDown=p;shelfDownIndex=pickerIndex;gbcThemeDragging=true;dragged=false;return}
        for (i,kind) in Handheld.allCases.enumerated() where modelRect(i).contains(p) {chooseMachine(kind);return}
      }
      return
    }
    if toolbar(4).contains(p){showDisplaySettings(nil);return}
    if toolbar(2).contains(p) {
      if running{showSpatialSwitcher();return}
      if running {CoreDriver.shared.stop();running=false;videoFrame=nil}
      inserted=false;lid=0;phaseTo(.library)
      pickerIndex = theme
      pickerPage = .models
      choosing = true
      showModelPicker()
      releaseAll()
      hoverLabel = nil
      resizeForMachine()
      needsDisplay = true
      report()
      return
    }
    if handheld == .nds && toolbar(3).contains(p) {
      guard phase == .playing || phase == .idleOpen else { return }
      bookMode.toggle()
      releaseAll()
      hoverLabel = nil
      tooltipSignature = ""
      report()
      needsDisplay = true
      return
    }
    if handheld == .gba && classicRect(CGRect(x: 16, y: 260, width: 25, height: 48)).contains(p) {
      muted.toggle()
      hoverLabel = muted ? "音量 · 点击恢复声音" : "音量 · 点击静音"
      CoreDriver.shared.volume(muted ? 0 : 1)
      tooltipSignature = ""
      report()
      needsDisplay = true
      return
    }
    if toolbar(0).contains(p) || (!usesGBC3D && (handheld != .nds || lid > 0.99) && powerRect.contains(m)) {
      handlePower()
      return
    }
    if toolbar(1).contains(p) {
      if running || phase == .idleOpen { closeMachine() } else if phase == .library { scan() }
      return
    }
    if usesGBC3D && phase == .playing && !focusActive{gbcStage.press(e);return}
    if phase == .library && (usesGBC3D ? CGRect(x:0,y:200,width:720,height:340):CGRect(x:55,y:85,width:610,height:215)).contains(p) {
      shelfDown = p
      shelfDownIndex = selectedIndex
      dragged = false
      return
    }
    if focusActive{if dual{touchFocused(p,true)};return}
    if modern && handleModernUtility(p) { return }
    if running && phase == .playing {
      if modern && modernStickRect.offsetBy(dx:240,dy:0).contains(m) { analogDrag=true; updateStick(p); return }
      if dual && bottom.contains(m) {
        touch(m, true)
      } else {
        for (_, id, r) in buttons + dpad where r.contains(m) {
          mouseButtonID = id
          set(id, true)
          break
        }
      }
    }
  }
  override func mouseDragged(with e: NSEvent) {
    let p = point(e)
    if gbcThemeDragging,let start=shelfDown{let dx=p.x-start.x;if abs(dx)>10{dragged=true;let position=CGFloat(shelfDownIndex)-dx/(pickerPage == .models ? SpatialMachine.homeColumn:SpatialMachine.homeColumn);if pickerPage == .models{modelPosition=position}else{gbcThemePosition=position};pickerIndex=max(0,min((pickerPage == .models ? Handheld.allCases.count:handheld.editions.count)-1,Int(position.rounded())));needsDisplay=true};return}
    if usesGBC3D && running && !focusActive{gbcStage.drag(e);return}
    if focusActive{if dual{touchFocused(p,true)};return}
    if analogDrag { updateStick(p); return }
    if let start = shelfDown, phase == .library {
      let dx = p.x - start.x
      if abs(dx) > 12 {
        dragged = true
        carousel = CGFloat(shelfDownIndex) - dx / (usesGBC3D ? spatialCardStride:184)
        selectedIndex = max(0, min(games.count - 1, Int(carousel.rounded())))
        needsDisplay = true
      }
      return
    }
    let m = machinePoint(p)
    if dual && running && mouseButtonID == nil { touch(m, bottom.contains(m)) }
  }
  override func mouseUp(with e: NSEvent) {
    if gbcThemeDragging{if !dragged,let index=pickerPage == .models ? gbcStage.modelIndex(e):gbcStage.themeIndex(e){if index==pickerIndex{if pickerPage == .models{chooseMachine(Handheld.allCases[index])}else{confirmTheme(index)}}else{pickerIndex=index}};gbcThemeDragging=false;shelfDown=nil;dragged=false;needsDisplay=true;return}
    if usesGBC3D && running{gbcStage.release()}
    if usesGBC3D && phase == .library,shelfDown != nil{if !dragged,let index=gbcStage.cardIndex(e){beginInsert(index)};shelfDown=nil;dragged=false;return}
    if analogDrag { analogDrag=false; stickX=0; stickY=0; emu_axis(0,0,0); emu_axis(0,1,0); needsDisplay=true }
    if shelfDown != nil {
      let p = point(e)
      if !dragged {
        for i in games.indices where cardRect(i).insetBy(dx: -7, dy: -7).contains(p) {
          beginInsert(i)
          break
        }
      }
      shelfDown = nil
      dragged = false
    }
    if let id = mouseButtonID {
      set(id, false)
      mouseButtonID = nil
    }
    touchRelease = CACurrentMediaTime() + 0.025
  }
  override func keyDown(with e: NSEvent) {
    if importing { return }
    if e.isARepeat { return }
    if choosing {
      if e.keyCode == 36 {if pickerPage == .themes {confirmTheme(pickerIndex)}else{chooseMachine(Handheld.allCases[pickerIndex])}}
      else if e.keyCode == 53 && pickerPage == .themes {showModelPicker()}
      else if [UInt16(123),124,125,126].contains(e.keyCode) {
        let count=pickerPage == .models ? Handheld.allCases.count:handheld.editions.count
        pickerIndex=(pickerIndex + ((e.keyCode == 123 || e.keyCode == 126) ? -1:1)+count)%count;needsDisplay=true;report()
      }
      return
    }
    if phase == .library {
      if e.keyCode == 53 {
        choosing=true; showModelPicker(); resizeForMachine()
      } else if e.keyCode == 123 {
        choose(-1)
      } else if e.keyCode == 124 {
        choose(1)
      } else if e.keyCode == 36 {
        beginInsert(selectedIndex)
      }
      return
    }
    if e.keyCode == 53 {
      releaseAll()
      return
    }
    if running && modern && analogKey(e.keyCode,true) { return }
    if running, let id = keys[e.keyCode] { set(id, true) }
  }
  override func keyUp(with e: NSEvent) { if modern && analogKey(e.keyCode,false) { return }; if let id = keys[e.keyCode] { set(id, false) } }
  override func flagsChanged(with e: NSEvent) {
    if running && e.keyCode == 60 { set(2, e.modifierFlags.contains(.shift)) }
  }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas { removeTrackingArea(area) }
    addTrackingArea(
      NSTrackingArea(
        rect: .zero,
        options: [
          .inVisibleRect, .activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate,
        ], owner: self, userInfo: nil))
  }
  func updateHover(_ p: CGPoint) {
    let label = hoverEntries.first { $0.0.contains(p) }?.1
    if label != hoverLabel { hoverSince = CACurrentMediaTime() }
    hoverLabel = label
    hoverPoint = p
    needsDisplay = true
  }
  override func mouseExited(with e: NSEvent) {
    hoverLabel = nil
    needsDisplay = true
  }
  override func mouseMoved(with e: NSEvent) {
    updateHover(point(e))
    if usesGBC3D && running && !focusActive{hoverLabel=nil;gbcStage.updateTooltip(e)}
    if dual && running && phase == .playing && (focusActive ? focusedTouchRect.contains(point(e)):bottom.contains(machinePoint(point(e)))) {
      stylus.set()
    } else if hoverEntries.contains(where: { $0.0.contains(point(e)) }) || (choosing && (pickerPage == .themes ? (0..<3).contains(where:{themeGridRect($0).contains(point(e))}):(0..<Handheld.allCases.count).contains(where:{modelRect($0).contains(point(e))}))) {
      NSCursor.pointingHand.set()
    } else {
      NSCursor.arrow.set()
    }
  }
  override func cursorUpdate(with e: NSEvent) { mouseMoved(with: e) }
  override func resetCursorRects() {
    if dual && running && phase == .playing {
      let rect = focusActive ? focusedTouchRect:displayRect(bottom.offsetBy(dx: -240, dy: 0))
      let r = CGRect(
        x: offset.x + rect.minX * scale, y: offset.y + rect.minY * scale, width: rect.width * scale,
        height: rect.height * scale)
      addCursorRect(r, cursor: stylus)
    }
  }
  func importROM() { presentROMImporter() }

}
final class Delegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  var window: NSWindow!, view: StudioView!
  func applicationDidFinishLaunching(_ n: Notification) {
    NSApp.applicationIconImage = NSImage(
      contentsOf: Bundle.main.resourceURL!.appendingPathComponent("UncleED.icns"))
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 720, height: 780),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    window.title = "Uncle Ed"
    window.contentMinSize = NSSize(width: 720, height: 780)
    window.backgroundColor = NSColor(srgbRed: 25/255, green: 30/255, blue: 29/255, alpha: 1)
    window.collectionBehavior.insert(.fullScreenPrimary)
    window.center()
    view = StudioView(frame: NSRect(x: 0, y: 0, width: 720, height: 780))
    view.autoresizingMask = [.width, .height]
    window.contentView = view
    window.acceptsMouseMovedEvents = true
    window.delegate = self
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(view)
    NSApp.activate(ignoringOtherApps: true)
    let menu = NSMenu()
    let item = NSMenuItem()
    menu.addItem(item)
    let sub = NSMenu()
    sub.addItem(
      withTitle: "退出 Uncle Ed", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    item.submenu = sub
    let fileItem = NSMenuItem(title: "文件", action: nil, keyEquivalent: "")
    let fileMenu = NSMenu(title: "文件")
    let add = NSMenuItem(title: "添加 ROM…", action: #selector(StudioView.addROMAction(_:)), keyEquivalent: "o")
    add.target = view
    fileMenu.addItem(add)
    let retry = NSMenuItem(title: "重新匹配缺失封面", action: #selector(StudioView.retryCoversAction(_:)), keyEquivalent: "")
    retry.target = view
    fileMenu.addItem(retry)
    fileMenu.addItem(NSMenuItem.separator())
    for (title,selector,key) in [("存下此刻",#selector(StudioView.instantSave(_:)),"s"),("恢复手动存档",#selector(StudioView.instantLoad(_:)),"l"),("继续上次离开",#selector(StudioView.instantContinue(_:)),"")]{let action=NSMenuItem(title:title,action:selector,keyEquivalent:key);action.target=view;fileMenu.addItem(action)}
    fileItem.submenu = fileMenu
    menu.addItem(fileItem)
    let viewItem = NSMenuItem(title: "显示", action: nil, keyEquivalent: "")
    let viewMenu = NSMenu(title: "显示")
    let fullScreenItem = NSMenuItem(title: "切换全屏", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
    fullScreenItem.keyEquivalentModifierMask = [.control, .command]
    fullScreenItem.target = window
    viewMenu.addItem(fullScreenItem)
    let settings=NSMenuItem(title:"显示调整…",action:#selector(StudioView.showDisplaySettings(_:)),keyEquivalent:",");settings.target=view;viewMenu.addItem(settings)
    viewItem.submenu = viewMenu
    menu.addItem(viewItem)
    NSApp.mainMenu = menu
  }
  func windowWillEnterFullScreen(_ notification: Notification) {
    view.fullScreenTransition = true
  }
  func windowDidEnterFullScreen(_ notification: Notification) {
    view.fullScreenTransition = false
    view.needsDisplay = true
    view.window?.invalidateCursorRects(for: view)
  }
  func windowWillExitFullScreen(_ notification: Notification) {
    view.fullScreenTransition = true
  }
  func windowDidExitFullScreen(_ notification: Notification) {
    view.fullScreenTransition = false
    view.resizeForMachine()
    view.needsDisplay = true
    view.window?.invalidateCursorRects(for: view)
  }
  func windowDidResize(_ notification: Notification) {
    view.needsDisplay = true
    view.window?.invalidateCursorRects(for: view)
    view.report()
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if view.running { CoreDriver.shared.stop() }
    return .terminateNow
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = Delegate()
app.delegate = delegate
app.run()
