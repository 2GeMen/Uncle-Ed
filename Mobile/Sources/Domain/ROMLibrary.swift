import Foundation
import CryptoKit
import ZIPFoundation

final class ROMLibrary {
    let root: URL
    lazy var catalog=GameCatalog(directory:root.appendingPathComponent("Metadata"))
    private let io = DispatchQueue(label:"uncleed.library",qos:.userInitiated)
    init(root: URL = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("UncleEd",isDirectory:true)) {
        self.root=root
        for name in ["ROMs","Covers","Saves","Staging"] {try? FileManager.default.createDirectory(at:root.appendingPathComponent(name),withIntermediateDirectories:true)}
        // Recover only importer-owned temporary files from an interrupted prior launch.
        for file in (try? FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("Staging"),includingPropertiesForKeys:nil)) ?? [] {
            if UUID(uuidString:file.lastPathComponent) != nil {try? FileManager.default.removeItem(at:file)}
        }
    }
    func romURL(_ item:ROMItem)->URL {root.appendingPathComponent("ROMs/\(item.model.rawValue)/\(item.fileName)")}
    func coverURL(_ item:ROMItem)->URL? {item.coverFile.map{root.appendingPathComponent("Covers/"+$0)}}
    func load()->[ROMItem] { (try? JSONDecoder().decode([ROMItem].self,from:Data(contentsOf:root.appendingPathComponent("library.json")))) ?? [] }
    private func save(_ items:[ROMItem]) throws {try JSONEncoder().encode(items).write(to:root.appendingPathComponent("library.json"),options:.atomic)}
    func updateCover(id:String,file:String,rgb:UInt32,completion:@escaping()->Void) {
        io.async {var items=self.load();if let i=items.firstIndex(where:{$0.id==id}) {items[i].coverFile=file;items[i].dominantRGB=rgb;try? self.save(items)};DispatchQueue.main.async(execute:completion)}
    }
    func importFiles(_ urls:[URL],completion:@escaping(ImportSummary)->Void) {
        io.async {var summary=ImportSummary();var items=self.load()
            for source in urls {
                let access=source.startAccessingSecurityScopedResource();defer {if access {source.stopAccessingSecurityScopedResource()}}
                var coordinationError:NSError?
                NSFileCoordinator().coordinate(readingItemAt:source,options:.withoutChanges,error:&coordinationError) { url in
                    do {try self.read(url,items:&items,summary:&summary)} catch {summary.failures.append(source.lastPathComponent+": "+error.localizedDescription)}
                }
                if let coordinationError {summary.failures.append(source.lastPathComponent+": "+coordinationError.localizedDescription)}
            }
            do {try self.save(items)} catch {summary.failures.append("保存资源目录失败："+error.localizedDescription)}
            let result=summary;DispatchQueue.main.async{completion(result)}
        }
    }
    private func read(_ source:URL,items:inout [ROMItem],summary:inout ImportSummary) throws {
        if source.pathExtension.lowercased() == "zip" {
            let archive=try Archive(url:source,accessMode:.read)
            let entries=archive.filter{$0.type == .file && DeviceModel.detect(extension:($0.path as NSString).pathExtension) != nil}
            guard !entries.isEmpty else {throw LibraryError.unsupported};guard entries.count<=100 else{throw LibraryError.excessiveArchive}
            for entry in entries {
                guard safeArchivePath(entry.path) else {throw LibraryError.unsafePath}
                let model=DeviceModel.detect(extension:(entry.path as NSString).pathExtension)!
                guard entry.uncompressedSize<=model.maximumROMBytes else{throw LibraryError.tooLarge}
                do {
                    let temporary=root.appendingPathComponent("Staging/"+UUID().uuidString)
                    defer{try? FileManager.default.removeItem(at:temporary)}
                    FileManager.default.createFile(atPath:temporary.path,contents:nil)
                    let output=try FileHandle(forWritingTo:temporary);defer{try? output.close()}
                    var written:UInt64=0
                    let checksum=try archive.extract(entry,bufferSize:262144,consumer:{ chunk in written += UInt64(chunk.count);guard written<=model.maximumROMBytes else{throw LibraryError.tooLarge};try output.write(contentsOf:chunk) })
                    guard checksum==entry.checksum else {throw LibraryError.damagedArchive}
                    try output.synchronize();try self.install(temporary,name:(entry.path as NSString).lastPathComponent,model:model,items:&items,summary:&summary)
                } catch {summary.failures.append(entry.path+": "+error.localizedDescription)}
            }
        } else {
            guard let model=DeviceModel.detect(extension:source.pathExtension) else {throw LibraryError.unsupported}
            let temporary=root.appendingPathComponent("Staging/"+UUID().uuidString);defer{try? FileManager.default.removeItem(at:temporary)}
            FileManager.default.createFile(atPath:temporary.path,contents:nil)
            let input=try FileHandle(forReadingFrom:source),output=try FileHandle(forWritingTo:temporary)
            defer{try? input.close();try? output.close()}
            var total:UInt64=0
            while true {
                let copied:Int=try autoreleasepool {
                    guard let chunk=try input.read(upToCount:262144),!chunk.isEmpty else{return 0}
                    total += UInt64(chunk.count);guard total<=model.maximumROMBytes else{throw LibraryError.tooLarge}
                    try output.write(contentsOf:chunk);return chunk.count
                }
                if copied==0 {break}
            }
            try output.synchronize();try install(temporary,name:source.lastPathComponent,model:model,items:&items,summary:&summary)
        }
    }
    private func install(_ temporary:URL,name:String,model:DeviceModel,items:inout [ROMItem],summary:inout ImportSummary) throws {
        let handle=try FileHandle(forReadingFrom:temporary);defer{try? handle.close()};var hasher=SHA256();var count=0
        while true {
            let hashed:Int=try autoreleasepool {
                guard let chunk=try handle.read(upToCount:262144),!chunk.isEmpty else{return 0}
                hasher.update(data:chunk);count += chunk.count;return chunk.count
            }
            if hashed==0 {break}
        }
        guard count>0 else{throw LibraryError.emptyFile}
        let id=hasher.finalize().map{String(format:"%02x",$0)}.joined()
        guard !items.contains(where:{$0.id==id}) else{summary.duplicateCount += 1;return}
        let folder=root.appendingPathComponent("ROMs/"+model.rawValue,isDirectory:true);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let filename=id+"."+(name as NSString).pathExtension.lowercased(), destination=folder.appendingPathComponent(filename)
        // Recover a file left by an interrupted prior import; manifest remains the commit point.
        if !FileManager.default.fileExists(atPath:destination.path) {try FileManager.default.moveItem(at:temporary,to:destination)}
        let item=ROMItem(id:id,model:model,fileName:filename,title:cleanGameTitle(name),catalogName:name)
        items.append(item);summary.added.append(item);catalog.request(model:model.rawValue,name:name)
    }
}
