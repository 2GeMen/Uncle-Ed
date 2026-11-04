import Foundation

enum DeviceModel: String, CaseIterable, Codable, Sendable {
    case nds, gba, gbc, psp, n3ds = "3ds"
    static func available(onPhone:Bool)->[DeviceModel]{onPhone ? [.gba,.gbc,.psp]:allCases}
    var name: String { switch self { case .nds: return "Nintendo DS"; case .gba: return "Game Boy Advance"; case .gbc: return "Game Boy Color"; case .psp: return "PlayStation Portable"; case .n3ds: return "Nintendo 3DS" } }
    var themes: [String] { switch self { case .nds: return ["宝可梦黑白限定版", "马里奥限定版", "塞尔达限定版", "黑磨砂"]; case .gba: return ["原生黄色", "索尼克定制", "EVA 定制", "白色磨砂半透明"]; case .gbc: return ["宝可梦中心限定", "经典原始配色", "经典黄配色", "黑磨砂"]; case .psp: return ["最终幻想限定", "怪物猎人限定", "实况足球限定", "黑磨砂"]; case .n3ds: return ["塞尔达限定", "宝可梦日月限定", "大乱斗限定", "黑磨砂"] } }
    var coreName: String { switch self { case .nds: return "melondsds_libretro"; case .gba, .gbc: return "mgba_libretro"; case .psp: return "ppsspp_libretro"; case .n3ds: return "azahar_libretro" } }
    var requiresMobileGPU: Bool { self == .psp || self == .n3ds }
    static func detect(extension ext: String) -> DeviceModel? {
        switch ext.lowercased() { case "nds": return .nds; case "gba": return .gba; case "gb", "gbc": return .gbc; case "iso", "cso", "chd", "pbp": return .psp; case "cci", "3ds", "cxi", "3dsx": return .n3ds; default: return nil }
    }
    var maximumROMBytes: UInt64 { switch self { case .nds: return 1_073_741_824; case .gba: return 67_108_864; case .gbc: return 16_777_216; case .psp: return 2_684_354_560; case .n3ds: return 8_589_934_592 } }
}
struct ROMItem: Codable, Identifiable, Equatable, Sendable {
    var id: String // SHA-256 of actual ROM, independent of name/archive
    var model: DeviceModel
    var fileName: String
    var title: String
    var coverFile: String?
    var dominantRGB: UInt32?
    var catalogName:String? = nil // Original title and region, separate from hash filename.
}
struct ImportSummary: Sendable { var added: [ROMItem] = []; var duplicateCount = 0; var failures: [String] = [] }
enum LibraryError: LocalizedError {
    case unsupported, unsafePath, tooLarge, emptyFile, excessiveArchive, damagedArchive, unavailable(String)
    var errorDescription: String? { switch self { case .unsupported: return "请选择 ROM 文件或 ZIP 压缩包；7z 请先在“文件”中解压。"; case .unsafePath: return "压缩包中的文件路径不安全。"; case .tooLarge: return "文件大小超过该机型支持的范围。"; case .emptyFile: return "ROM 文件为空。"; case .excessiveArchive: return "单个 ZIP 最多导入 100 个 ROM，请拆分压缩包。"; case .damagedArchive: return "ZIP 校验失败，文件可能已损坏。"; case .unavailable(let reason): return reason } }
}
func safeArchivePath(_ path: String) -> Bool {
    !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0") && !path.split(separator: "/", omittingEmptySubsequences: false).contains("..") && !path.contains(":")
}
func cleanGameTitle(_ name: String) -> String {
    let ext=(name as NSString).pathExtension.lowercased()
    let raw = DeviceModel.detect(extension:ext) != nil || ["zip","7z","png","jpg","jpeg"].contains(ext) ? (name as NSString).deletingPathExtension : name
    return raw.replacingOccurrences(of: #"\s*[\(\[].*?[\)\]]"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
}
func coverMatchKey(_ name: String) -> String { cleanGameTitle(name).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).filter { $0.isLetter || $0.isNumber } }
