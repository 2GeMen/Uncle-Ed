import Cocoa
import CryptoKit

struct CartridgePalette: Codable {
  var coverSHA256: String
  var dominantRGB: Int
  var shellOpacity: Double
  var version: Int
}
let cartridgeShellOpacity: CGFloat = 0.76

// Quantize RGB into colour families and average the most populated family.
// Transparent pixels do not contribute; the tiny thumbnail is only sampled once per cover.
func dominantCoverColor(_ image: NSImage) -> Int? {
  guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
  let side = 48
  var rgba = [UInt8](repeating: 0, count: side * side * 4)
  let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
    guard let context = CGContext(data: bytes.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
    context.interpolationQuality = .medium
    context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
    return true
  }
  guard rendered else { return nil }
  var chromatic = [(count: Int, r: Int, g: Int, b: Int)](repeating: (0,0,0,0),count:512)
  var chromaticCount=0
  var bins = [(count: Int, r: Int, g: Int, b: Int)](repeating: (0, 0, 0, 0), count: 512)
  for i in stride(from: 0, to: rgba.count, by: 4) {
    let alpha = Int(rgba[i + 3])
    guard alpha > 127 else { continue }
    let r = min(255, Int(rgba[i]) * 255 / alpha), g = min(255, Int(rgba[i+1]) * 255 / alpha), b = min(255, Int(rgba[i+2]) * 255 / alpha)
    let index = (r >> 5) * 64 + (g >> 5) * 8 + (b >> 5)
    bins[index].count += 1; bins[index].r += r; bins[index].g += g; bins[index].b += b
    let hi=max(r,max(g,b)),lo=min(r,min(g,b))
    if hi > 45 && Double(hi-lo)/Double(hi) > 0.25 {
      chromatic[index].count += 1; chromatic[index].r += r; chromatic[index].g += g; chromatic[index].b += b
      chromaticCount += 1
    }
  }
  // Ignore neutral platform borders when the artwork has a substantial coloured area.
  // Monochrome covers retain their actual dark/light dominant shade.
  let families = chromaticCount > side*side/8 ? chromatic : bins
  guard let best = families.max(by: { $0.count < $1.count }), best.count > 0 else { return nil }
  return ((best.r / best.count) << 16) | ((best.g / best.count) << 8) | (best.b / best.count)
}
extension StudioView {
  func prepareCartridgePalette(_ code: String, image: NSImage, data: Data? = nil) -> Int {
    if let cached=cardTints[code], cached.image === image { return cached.tint }
    let bytes=data ?? (try? Data(contentsOf:assets.appendingPathComponent("Covers/"+code+".png")))
    let digest=bytes.map { SHA256.hash(data:$0).map {String(format:"%02x",$0)}.joined() } ?? ""
    let tint: Int
    if let saved=cartridgePalettes[code],saved.coverSHA256 == digest,saved.version == 2,!digest.isEmpty {
      tint=saved.dominantRGB
    } else {
      tint=dominantCoverColor(image) ?? 0x6C8175
      if !digest.isEmpty {
        cartridgePalettes[code]=CartridgePalette(coverSHA256:digest,dominantRGB:tint,shellOpacity:Double(cartridgeShellOpacity),version:2)
        if let encoded=try? JSONEncoder().encode(cartridgePalettes) {try? encoded.write(to:assets.appendingPathComponent("cartridge-palettes.json"),options:.atomic)}
      }
    }
    cardTints[code]=(image,tint)
    return tint
  }
  func cartridgeTint(_ game: Game) -> Int {
    guard let image=game.cover else { return 0x6C8175 }
    return prepareCartridgePalette(game.code,image:image)
  }
  func cartridgeInk(_ tint: Int) -> NSColor {
    let luma = CGFloat((tint >> 16) & 255) * 0.2126 + CGFloat((tint >> 8) & 255) * 0.7152 + CGFloat(tint & 255) * 0.0722
    return color(luma > 140 ? 0x23312A : 0xDBE4D6)
  }
  func translucentCartridge(_ path: NSBezierPath, tint: Int) {
    // The circuit substrate remains visible under the coloured translucent moulding.
    color(0x798B7A, 0.24).setFill(); path.fill()
    NSGraphicsContext.saveGraphicsState(); path.addClip()
    let r = path.bounds
    for i in 0..<4 {
      let x = r.minX + r.width * (0.13 + CGFloat(i) * 0.21)
      line([CGPoint(x:x,y:r.minY+5),CGPoint(x:x,y:r.maxY-18),CGPoint(x:x+8,y:r.maxY-10)],color(0xD6E4C7,0.13),0.8)
    }
    NSGradient(starting:keyColor(tint,0.19).withAlphaComponent(cartridgeShellOpacity+0.02),ending:keyColor(tint,-0.18).withAlphaComponent(cartridgeShellOpacity-0.06))?.draw(in:r,angle:90)
    NSGraphicsContext.restoreGraphicsState()
    color(0xFFFFFF,0.19).setStroke();path.lineWidth=0.75;path.stroke()
  }
}
