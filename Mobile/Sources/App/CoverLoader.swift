import UIKit

final class CoverLoader {
    struct Entry: Decodable {var name:String;var url:String}
    private let library:ROMLibrary
    private var pending=Set<String>()
    init(library:ROMLibrary){self.library=library}
    func load(_ item:ROMItem,completion:@escaping()->Void) {
        guard item.coverFile == nil,!pending.contains(item.id) else{return};pending.insert(item.id)
        if let bundled=Bundle.main.url(forResource:item.id,withExtension:"png",subdirectory:"Assets/Covers"),let data=try? Data(contentsOf:bundled),let image=UIImage(data:data) {
            let file=item.id+".png"
            do{try data.write(to:library.root.appendingPathComponent("Covers/"+file),options:.atomic);library.updateCover(id:item.id,file:file,rgb:palette(image)){[weak self] in self?.pending.remove(item.id);completion()};return}catch{pending.remove(item.id);return}
        }
        let file="cover-index"+(item.model == .nds ? "" : "-"+item.model.rawValue)
        guard let url=Bundle.main.url(forResource:file,withExtension:"json",subdirectory:"Assets"),let data=try? Data(contentsOf:url),let entries=try? JSONDecoder().decode([Entry].self,from:data) else{pending.remove(item.id);return}
        let key=coverMatchKey(item.title)
        let candidates=entries.filter{coverMatchKey($0.name)==key}
        guard let entry=candidates.first(where:{$0.name.contains("(USA")}) ?? candidates.first,let url=URL(string:entry.url),url.scheme=="https",["raw.githubusercontent.com","github.com","thumbnails.libretro.com"].contains(url.host ?? "") else{pending.remove(item.id);return}
        URLSession.shared.downloadTask(with:url){[weak self] temporary,response,error in
            guard let self else{return}
            defer{DispatchQueue.main.async{self.pending.remove(item.id)}}
            guard error==nil,let response=response as? HTTPURLResponse,response.statusCode==200,let temporary,let data=try? Data(contentsOf:temporary),data.count<=8_000_000,let image=UIImage(data:data),let png=image.pngData() else{return}
            let file=item.id+".png", destination=self.library.root.appendingPathComponent("Covers/"+file)
            do{try png.write(to:destination,options:.atomic);let rgb=self.palette(image);self.library.updateCover(id:item.id,file:file,rgb:rgb,completion:completion)}catch{}
        }.resume()
    }
    private func palette(_ image:UIImage)->UInt32 {
        guard let cg=image.cgImage else{return 0x54615E}
        var pixels=[UInt8](repeating:0,count:32*32*4)
        guard let context=CGContext(data:&pixels,width:32,height:32,bitsPerComponent:8,bytesPerRow:128,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return 0x54615E}
        context.draw(cg,in:CGRect(x:0,y:0,width:32,height:32));var bins:[UInt32:Int]=[:]
        for i in stride(from:0,to:pixels.count,by:4) {let r=UInt32(pixels[i]),g=UInt32(pixels[i+1]),b=UInt32(pixels[i+2]);if pixels[i+3]<128 || max(r,g,b)<24 || min(r,g,b)>235 {continue};let key=((r>>4)<<8)|((g>>4)<<4)|(b>>4);bins[key,default:0]+=1}
        guard let key=bins.max(by:{$0.value<$1.value})?.key else{return 0x54615E};return (((key>>8)*17)<<16)|((((key>>4)&15)*17)<<8)|((key&15)*17)
    }
}
