import Cocoa
import CryptoKit
import UniformTypeIdentifiers

let gameCatalog=GameCatalog(directory:support.appendingPathComponent("metadata"))

struct ROMImportResult {
  var added = 0, duplicates = 0
  var games: [(Handheld, Game)] = []
  var failures: [String] = []
}
func coverTitleKey(_ name: String) -> String {
  name.replacingOccurrences(of: "\\([^)]*\\)|\\[[^]]*\\]", with: "", options: .regularExpression)
    .lowercased().filter { $0.isLetter || $0.isNumber }
}
func bestCover(_ name: String, entries: [CoverEntry]) -> CoverEntry? {
  let exactKey = name.lowercased().filter { $0.isLetter || $0.isNumber }
  if let exact = entries.first(where: { $0.name.lowercased().filter { $0.isLetter || $0.isNumber } == exactKey }) { return exact }
  let candidates = entries.filter { coverTitleKey($0.name) == coverTitleKey(name) }
  let regions = ["USA", "Europe", "Japan", "World"]
  let region = regions.first { name.contains($0) }
  if let region, let match = candidates.first(where: { $0.name.contains(region) }) { return match }
  // A different region can use different artwork; leave it unmatched instead of guessing.
  return region == nil ? candidates.first : nil
}
func readZip(_ archive: URL, entry: String? = nil, limit: Int) throws -> Data {
  let task = Process(), pipe = Pipe()
  task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
  task.arguments = entry == nil ? ["-Z1", archive.path] : ["-p", archive.path, entry!]
  task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
  try task.run()
  var result = Data()
  do {
    while let chunk = try pipe.fileHandleForReading.read(upToCount: 1_048_576), !chunk.isEmpty {
      if result.count + chunk.count > limit {
        task.terminate()
        try? pipe.fileHandleForReading.close()
        task.waitUntilExit()
        throw NSError(domain: "ROM", code: 1, userInfo: [NSLocalizedDescriptionKey: "文件超过该机型的容量限制"])
      }
      result.append(chunk)
    }
  } catch { if task.isRunning { task.terminate() }; throw error }
  task.waitUntilExit()
  guard task.terminationStatus == 0 else { throw NSError(domain: "ROM", code: 2, userInfo: [NSLocalizedDescriptionKey: "ZIP 已损坏或需要密码"]) }
  return result
}
func romKind(_ ext: String) -> Handheld? {
  switch ext.lowercased() { case "nds": return .nds; case "gba": return .gba; case "gb", "gbc": return .gbc; case "iso", "cso", "chd", "pbp": return .psp; case "cci", "3ds", "cxi", "3dsx": return .n3ds; default: return nil }
}
func fileDigest(_ url: URL) throws -> String {
  let handle=try FileHandle(forReadingFrom:url); defer {try? handle.close()}
  var hash=SHA256()
  while let chunk=try handle.read(upToCount:4_194_304), !chunk.isEmpty { hash.update(data:chunk) }
  return hash.finalize().map {String(format:"%02x",$0)}.joined()
}
func archiveEntries(_ url:URL) throws -> [String] {
  let task=Process(),pipe=Pipe(); task.executableURL=URL(fileURLWithPath:"/usr/bin/tar")
  task.arguments=["-tf",url.path];task.standardOutput=pipe;task.standardError=FileHandle.nullDevice
  try task.run();let data=pipe.fileHandleForReading.readDataToEndOfFile();task.waitUntilExit()
  guard task.terminationStatus == 0,data.count<4_194_304 else {throw NSError(domain:"ROM",code:2,userInfo:[NSLocalizedDescriptionKey:"无法读取压缩包"])}
  return (String(data:data,encoding:.utf8) ?? "").components(separatedBy:"\n").filter {!$0.hasPrefix("__MACOSX/") && romKind(URL(fileURLWithPath:$0).pathExtension) != nil}
}
func extractEntry(_ url:URL,_ entry:String,to target:URL,limit:Int) throws {
  let task=Process(),pipe=Pipe(); task.executableURL=URL(fileURLWithPath:"/usr/bin/tar");task.arguments=["-xOf",url.path,"--",entry]
  task.standardOutput=pipe;task.standardError=FileHandle.nullDevice
  fm.createFile(atPath:target.path,contents:nil);let handle=try FileHandle(forWritingTo:target);defer {try? handle.close()}
  try task.run();var size=0
  do {
    while let data=try pipe.fileHandleForReading.read(upToCount:4_194_304),!data.isEmpty {
      size+=data.count
      guard size<=limit else {throw NSError(domain:"ROM",code:4,userInfo:[NSLocalizedDescriptionKey:"ROM 超过该机型容量限制"])}
      try handle.write(contentsOf:data)
    }
  } catch { task.terminate();try? pipe.fileHandleForReading.close();task.waitUntilExit();throw error }
  task.waitUntilExit();guard task.terminationStatus == 0 else {throw NSError(domain:"ROM",code:2,userInfo:[NSLocalizedDescriptionKey:"压缩包已损坏或需要密码"])}
}
func importROMFiles(_ urls: [URL]) -> ROMImportResult {
  var result=ROMImportResult()
  for source in urls {
    do {
      let archive=["zip","7z"].contains(source.pathExtension.lowercased())
      let names=try archive ? archiveEntries(source) : [source.lastPathComponent]
      guard !names.isEmpty else {throw NSError(domain:"ROM",code:3,userInfo:[NSLocalizedDescriptionKey:"压缩包中没有支持的游戏文件"])}
      for entry in names {
        guard let kind=romKind(URL(fileURLWithPath:entry).pathExtension) else {continue}
        let limit=kind == .nds ? 536_870_912 : kind == .gba ? 33_554_432 : kind == .gbc ? 8_388_608 : kind == .psp ? 2_147_483_648 : 8_589_934_592
        let directory=support.appendingPathComponent("roms/"+kind.rawValue)
        try fm.createDirectory(at:directory,withIntermediateDirectories:true)
        let temporary=directory.appendingPathComponent(".import-"+UUID().uuidString)
        defer {try? fm.removeItem(at:temporary)}
        if archive {try extractEntry(source,entry,to:temporary,limit:limit)}
        else {
          let size=(try source.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
          guard size<=limit else {throw NSError(domain:"ROM",code:4,userInfo:[NSLocalizedDescriptionKey:"ROM 容量异常"])}
          try fm.copyItem(at:source,to:temporary)
        }
        let handle=try FileHandle(forReadingFrom:temporary);let bytes=(try handle.read(upToCount:512)) ?? Data();try handle.close()
        guard bytes.count>=512 else {throw NSError(domain:"ROM",code:5,userInfo:[NSLocalizedDescriptionKey:"游戏文件不完整"])}
        var target=directory.appendingPathComponent(URL(fileURLWithPath:entry).lastPathComponent)
        let digest=try fileDigest(temporary)
        if fm.fileExists(atPath:target.path),try fileDigest(target) != digest {
          target=directory.appendingPathComponent(target.deletingPathExtension().lastPathComponent+" ("+digest.prefix(8)+")."+target.pathExtension)
        }
        if fm.fileExists(atPath:target.path) {result.duplicates+=1}
        else {try fm.moveItem(at:temporary,to:target);result.added+=1}
        var hash:UInt64=1_469_598_103_934_665_603
        for byte in target.lastPathComponent.lowercased().utf8 {hash=(hash ^ UInt64(byte)) &* 1_099_511_628_211}
        let code:String
        if kind == .nds {code=String(bytes:bytes[12..<16],encoding:.ascii) ?? "UNKN"}
        else if kind == .gba {code=String(bytes:bytes[172..<176],encoding:.ascii) ?? "GBA"}
        else if kind == .gbc && target.lastPathComponent.lowercased().contains("gold version") {code="GB_GOLD"}
        else if kind == .gbc && target.lastPathComponent.lowercased().contains("silver version") {code="GB_SILVER"}
        else {code="GB_"+String(hash,radix:16)}
        let title=target.deletingPathExtension().lastPathComponent.components(separatedBy:" (").first ?? target.lastPathComponent
        result.games.append((kind,Game(url:target,code:code,title:title,detail:kind.name,cover:nil)))
        gameCatalog.request(model:kind.rawValue,name:target.lastPathComponent)
      }
    } catch {result.failures.append(source.lastPathComponent+"："+error.localizedDescription)}
  }
  return result
}

// Read the ISO9660 game icon without extracting a multi-GB PSP image.
func embeddedPSPImage(_ url:URL) -> Data? {
  guard url.pathExtension.lowercased() == "iso",let handle=try? FileHandle(forReadingFrom:url) else {return nil}
  defer {try? handle.close()}
  func read(_ offset:UInt64,_ count:Int) -> Data? {do {try handle.seek(toOffset:offset);return try handle.read(upToCount:count)} catch {return nil}}
  func number(_ data:Data,_ offset:Int) -> Int {guard data.count>=offset+4 else{return 0};return (0..<4).reduce(0){$0 | Int(data[offset+$1]) << ($1*8)}}
  guard let pvd=read(32768,2048),pvd.count==2048,String(bytes:pvd[1..<6],encoding:.ascii)=="CD001" else{return nil}
  var extent=number(pvd,158),size=number(pvd,166)
  for component in ["PSP_GAME","ICON0.PNG"] {
    guard size>0,size<=4_194_304,let block=read(UInt64(extent)*2048,size) else{return nil}
    var offset=0,found=false
    while offset<block.count {
      let length=Int(block[offset]);if length==0 {offset=(offset/2048+1)*2048;continue}
      guard length>=34,offset+length<=block.count else{return nil}
      let nameLength=Int(block[offset+32]);guard nameLength+33<=length else{return nil}
      let name=String(bytes:block[(offset+33)..<(offset+33+nameLength)],encoding:.ascii)?.components(separatedBy:";").first
      if name?.uppercased()==component {extent=number(block,offset+2);size=number(block,offset+10);found=true;break}
      offset+=length
    }
    if !found {return nil}
  }
  guard size>0,size<=4_194_304,let data=read(UInt64(extent)*2048,size),NSImage(data:data) != nil else{return nil}
  return data
}

extension StudioView {
  var importRect: CGRect { choosing ? CGRect(x: 650, y: 25, width: 40, height: 40) : CGRect(x: handheld == .nds ? 568 : 616, y: 14, width: 40, height: 40) }
  func drawImportButton() {
    let r = importRect
    fill(r, color(0x2D3431), 9)
    stroke(CGRect(x: r.midX - 10, y: r.midY - 5, width: 20, height: 15), color(0xC4CFC0), 2, 1.2)
    line([CGPoint(x: r.midX - 10, y: r.midY - 5), CGPoint(x: r.midX - 10, y: r.midY - 9), CGPoint(x: r.midX - 3, y: r.midY - 9), CGPoint(x: r.midX, y: r.midY - 5)], color(0xC4CFC0), 1.2)
    line([CGPoint(x:r.midX-4,y:r.midY+2),CGPoint(x:r.midX+4,y:r.midY+2)],color(0xC4CFC0),1.2)
    line([CGPoint(x:r.midX,y:r.midY-2),CGPoint(x:r.midX,y:r.midY+6)],color(0xC4CFC0),1.2)
  }
  func drawLibraryNotice() {
    guard let notice = libraryNotice, CACurrentMediaTime() < noticeUntil else { return }
    fill(CGRect(x: 35, y: canvasHeight - 46, width: 650, height: 30), color(0x303B33), 10)
    centered(notice, 360, canvasHeight - 39, 11, color(0xD8E2D2))
  }
  func notifyLibrary(_ message: String) { libraryNotice = message; noticeUntil = CACurrentMediaTime() + 12; needsDisplay = true }
  @objc func addROMAction(_ sender: Any?) { importROM() }
  @objc func retryCoversAction(_ sender: Any?) {
    requested.removeAll()
    for game in games where game.cover == nil { lookupCover(game, kind: handheld) }
    notifyLibrary("正在为当前卡带收藏重新匹配封面")
  }
  func presentROMImporter() {
    guard !importing else { return }
    guard !running, phase == .library else { notifyLibrary("请先关闭电源，再添加 ROM"); return }
    guard let window else { return }
    let panel = NSOpenPanel()
    panel.title = "添加 ROM"
    panel.prompt = "添加"
    panel.allowedContentTypes = ["zip", "7z", "nds", "gba", "gb", "gbc", "cci", "3ds", "cxi", "3dsx", "iso", "cso", "chd", "pbp"].compactMap { UTType(filenameExtension: $0) }
    panel.allowsMultipleSelection = true
    panel.message = "支持 ZIP／7z 及 NDS、GBA、GBC、PSP、3DS 游戏；自动归类并匹配封面。原文件保留。"
    panel.beginSheetModal(for: window) { [weak self] response in
      guard let self, response == .OK else { return }
      self.importing = true
      self.notifyLibrary("正在导入卡带…")
      let urls = panel.urls
      DispatchQueue.global(qos: .userInitiated).async {
        let result = importROMFiles(urls)
        DispatchQueue.main.async {
          self.importing = false
          for (kind, game) in result.games {
            let key = kind.rawValue + ":" + game.code
            self.requested.remove(key)
            if !fm.fileExists(atPath: assets.appendingPathComponent("Covers/" + game.code + ".png").path) { self.lookupCover(game, kind: kind) }
          }
          if let first = result.games.first {
            self.selectHandheld(first.0)
            self.choosing = false
            self.scan()
            if let index = self.games.firstIndex(where: { $0.url == first.1.url }) { self.selectedIndex = index; self.carousel = CGFloat(index) }
            self.resizeForMachine()
          }
          self.notifyLibrary("已添加 \(result.added) 张 · 已有 \(result.duplicates) 张 · 自动匹配封面")
          self.report()
          if !result.failures.isEmpty {
            let alert = NSAlert()
            alert.messageText = "部分文件未能导入"
            alert.informativeText = result.failures.joined(separator: "\n")
            alert.beginSheetModal(for: window)
          }
        }
      }
    }
  }
  func lookupCover(_ game: Game, kind: Handheld) {
    let key = kind.rawValue + ":" + game.code
    guard !requested.contains(key) else { return }
    requested.insert(key)
    if let meta = covers[game.code] { downloadCover(game, kind: kind, entry: CoverEntry(name: meta.name, url: meta.url)); return }
    let file = "cover-index" + (kind == .nds ? "" : "-" + kind.rawValue) + ".json"
    if coverIndexes[kind] == nil, let data = try? Data(contentsOf: assets.appendingPathComponent(file)) {
      coverIndexes[kind] = try? JSONDecoder().decode([CoverEntry].self, from: data)
    }
    if let entries = coverIndexes[kind] {
      if let match = bestCover(game.url.deletingPathExtension().lastPathComponent, entries: entries) { downloadCover(game, kind: kind, entry: match) }
      else { if kind == .psp { useEmbeddedCover(game) } else { coverStates[key] = "unmatched"; report() } }
      return
    }
    pendingCovers[kind, default: []].append(game)
    guard !indexRequests.contains(kind) else { return }
    indexRequests.insert(kind)
    let repo = kind == .psp ? "Sony_-_PlayStation_Portable" : kind == .n3ds ? "Nintendo_-_Nintendo_3DS" : kind == .nds ? "Nintendo_-_Nintendo_DS" : kind == .gba ? "Nintendo_-_Game_Boy_Advance" : "Nintendo_-_Game_Boy_Color"
    let url = URL(string: "https://api.github.com/repos/libretro-thumbnails/" + repo + "/git/trees/master?recursive=1")!
    var request = URLRequest(url: url); request.timeoutInterval = 25
    URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
      let category = kind == .psp ? "Sony - PlayStation Portable" : kind == .n3ds ? "Nintendo - Nintendo 3DS" : kind == .nds ? "Nintendo - Nintendo DS" : kind == .gba ? "Nintendo - Game Boy Advance" : "Nintendo - Game Boy Color"
      var entries: [CoverEntry] = []
      if let data, data.count < 16_777_216, (response as? HTTPURLResponse)?.statusCode == 200,
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let tree = json["tree"] as? [[String: Any]] {
        for item in tree {
          if let path = item["path"] as? String, path.hasPrefix("Named_Boxarts/"), path.hasSuffix(".png") {
            let encoded = (category + "/" + path).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#&")))!
            entries.append(CoverEntry(name: String(path.dropFirst(14).dropLast(4)), url: "https://thumbnails.libretro.com/" + encoded))
          }
        }
      }
      let fetched = entries
      DispatchQueue.main.async {
        guard let self else { return }
        self.indexRequests.remove(kind)
        let pending = self.pendingCovers.removeValue(forKey: kind) ?? []
        if !fetched.isEmpty {
          self.coverIndexes[kind] = fetched
          if let data = try? JSONEncoder().encode(fetched) { try? data.write(to: assets.appendingPathComponent(file), options: .atomic) }
          for game in pending { self.requested.remove(kind.rawValue + ":" + game.code); self.lookupCover(game, kind: kind) }
        } else {
          for game in pending { let key = kind.rawValue + ":" + game.code; self.requested.remove(key); self.coverStates[key] = "offline" }
          self.notifyLibrary("封面库暂时不可用；卡带已保留，可从文件菜单重试匹配")
          self.report()
        }
      }
    }.resume()
  }
  func useEmbeddedCover(_ game:Game) {
    DispatchQueue.global(qos:.utility).async { [weak self] in
      let data=embeddedPSPImage(game.url)
      DispatchQueue.main.async { [weak self] in
        guard let self else{return}
        let key=Handheld.psp.rawValue+":"+game.code
        guard let data,let image=NSImage(data:data) else {self.coverStates[key]="unmatched";self.report();return}
        do {try data.write(to:assets.appendingPathComponent("Covers/"+game.code+".png"),options:.atomic)} catch {self.coverStates[key]="unavailable";return}
        _=self.prepareCartridgePalette(game.code,image:image,data:data)
        if self.handheld == .psp,let index=self.games.firstIndex(where:{$0.code==game.code}) {self.games[index].cover=image}
        self.coverStates[key]="embedded";self.needsDisplay=true;self.report()
      }
    }
  }
  func downloadCover(_ game: Game, kind: Handheld, entry: CoverEntry) {
    let key = kind.rawValue + ":" + game.code
    guard let url = URL(string: entry.url), url.scheme == "https", url.host == "thumbnails.libretro.com" else { requested.remove(key); return }
    coverStates[key] = "downloading"
    var request = URLRequest(url: url); request.timeoutInterval = 25
    URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
      DispatchQueue.main.async {
        guard let self else { return }
        guard let data, data.count <= 10_485_760, (response as? HTTPURLResponse)?.statusCode == 200, let image = NSImage(data: data) else {
          self.requested.remove(key); self.coverStates[key] = "unavailable"; self.report(); return
        }
        do { try data.write(to: assets.appendingPathComponent("Covers/" + game.code + ".png"), options: .atomic) }
        catch { self.coverStates[key] = "cache-error"; self.requested.remove(key); self.report(); return }
        _=self.prepareCartridgePalette(game.code,image:image,data:data)
        if self.covers[game.code] == nil { self.covers[game.code] = CoverMeta(name: entry.name, title: game.title, detail: kind.name, url: entry.url, source: "Libretro thumbnails", match: "regional filename + ROM identity") }
        if let encoded = try? JSONEncoder().encode(self.covers) { try? encoded.write(to: assets.appendingPathComponent("cover-manifest.json"), options: .atomic) }
        if self.handheld == kind, let i = self.games.firstIndex(where: { $0.code == game.code }) { self.games[i].cover = image }
        self.coverStates[key] = "cached"; self.needsDisplay = true; self.report()
      }
    }.resume()
  }
}
