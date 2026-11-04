import Foundation

struct GameCatalogRecord:Codable,Equatable {
 var title:String
 var publisher:String?,developer:String?,releaseDate:String?,releaseRegion:String?,metacritic:Int?,metacriticURL:String?
 var sourceURLs:[String]=[]
 var checkedAt:Date=Date()
 init(title:String){self.title=title}
 var scoreText:String{metacritic.map{String($0)+"/100"} ?? "/"}
 var creditsText:String{"开发 · "+(developer ?? "/")+"   出品 · "+(publisher ?? "/")}
 var releaseText:String{"发售 · "+(releaseDate ?? "/")+(releaseRegion.map{" · "+$0} ?? "")}
}

/// One versioned, non-blocking catalogue for all clients. A score is accepted
/// only from Metacritic's own Metascore JSON-LD for one matching platform.
final class GameCatalog {
 static let changed=Notification.Name("UncleEdGameCatalogChanged")
 private let directory:URL,queue:OperationQueue,lock=NSLock()
 private var records:[String:GameCatalogRecord]=[:],pending=Set<String>(),failed:[String:Date]=[:]
 var pendingCount:Int{lock.lock();defer{lock.unlock()};return pending.count}
 init(directory:URL){self.directory=directory;queue=OperationQueue();queue.maxConcurrentOperationCount=2;queue.qualityOfService = .utility
  try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
  if let seed=Bundle.main.url(forResource:"game-catalog-seed-v1",withExtension:"json",subdirectory:"Assets"),let bytes=try? Data(contentsOf:seed),let defaults=try? JSONDecoder().decode([String:GameCatalogRecord].self,from:bytes){records=defaults}
  if let bytes=try? Data(contentsOf:directory.appendingPathComponent("catalog-v1.json")),let cached=try? JSONDecoder().decode([String:GameCatalogRecord].self,from:bytes){records.merge(cached){seed,local in local.checkedAt>=seed.checkedAt ? local:seed}}
 }
 static func title(_ source:String)->String{
  var value=source.replacingOccurrences(of:"\\([^)]*\\)|\\[[^]]*\\]",with:"",options:.regularExpression)
  for suffix in [".gba",".gbc",".gb",".nds",".iso",".cso",".3ds",".cci",".pbp"]{if value.lowercased().hasSuffix(suffix){value=String(value.dropLast(suffix.count))}}
  if let r=value.range(of:", The",options:.caseInsensitive){value="The "+value.replacingCharacters(in:r,with:"")}
  return value.replacingOccurrences(of:" - ",with:": ").replacingOccurrences(of:"\\s+",with:" ",options:.regularExpression).trimmingCharacters(in:.whitespacesAndNewlines)
 }
 static func normalized(_ title:String)->String{Self.title(title).folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"en_US_POSIX")).components(separatedBy:CharacterSet.alphanumerics.inverted).filter{!$0.isEmpty && !["the","version"].contains($0)}.joined()}
 static func canonicalTitle(model:String,name:String)->String {
  let title=Self.title(name),key=normalized(title)
  if model=="nds" && (key.hasPrefix("fireemblemshinmonsho") || key.hasPrefix("fireemblemnewmysteryofemblem") || (title.contains("ファイアーエムブレム") && title.contains("新") && title.contains("紋章")) || (title.contains("火焰") && title.contains("新") && (title.contains("纹章") || title.contains("紋章")))) {return "Fire Emblem: New Mystery of the Emblem"}
  return title
 }
 static func searchLanguage(_ title:String)->String {
  if title.unicodeScalars.contains(where:{(0x3040...0x30FF).contains(Int($0.value))}){return "ja"}
  if title.unicodeScalars.contains(where:{(0x4E00...0x9FFF).contains(Int($0.value))}){return "zh"}
  return "en"
 }
 static func verifiedRegionalRecord(model:String,name:String)->GameCatalogRecord? {
  guard model=="nds",canonicalTitle(model:model,name:name)=="Fire Emblem: New Mystery of the Emblem" else{return nil}
  var result=GameCatalogRecord(title:"Fire Emblem: New Mystery of the Emblem — Heroes of Light and Shadow")
  result.developer="Intelligent Systems";result.publisher="Nintendo";result.releaseDate="2010-07-15";result.releaseRegion="日本"
  result.sourceURLs=["https://www.nintendo.co.jp/ds/vi2j/index.html","https://www.nintendo.co.jp/ds/interview/vi2j/vol1/index.html"]
  return result
 }
 static func key(model:String,name:String)->String{let region=["USA","Europe","Japan","Australia"].first{name.contains($0)} ?? "first-release";let variant=["demo","kiosk","beta","proto","dpad"].filter{name.lowercased().contains("("+$0)}.joined(separator:"-");return model+":"+normalized(name)+":"+region+":"+variant}
 func cached(model:String,name:String)->GameCatalogRecord?{lock.lock();defer{lock.unlock()};return records[Self.key(model:model,name:name)]}
 func request(model:String,name:String){let key=Self.key(model:model,name:name);lock.lock()
  if pending.contains(key) || failed[key].map({Date().timeIntervalSince($0)<1800})==true || records[key].map({Date().timeIntervalSince($0.checkedAt)<86400*7})==true{lock.unlock();return};pending.insert(key);lock.unlock()
  queue.addOperation{[weak self] in guard let self else{return};let record=self.lookup(model:model,name:name)
   self.lock.lock();if let record{self.records[key]=record;self.failed.removeValue(forKey:key)}else{self.failed[key]=Date()};self.pending.remove(key);let data=try? JSONEncoder().encode(self.records);if let data{try? data.write(to:self.directory.appendingPathComponent("catalog-v1.json"),options:.atomic)};self.lock.unlock()
   if record != nil{DispatchQueue.main.async{NotificationCenter.default.post(name:Self.changed,object:self,userInfo:["key":key])}}
  }
 }
 private func bytes(_ url:URL)->Data?{var request=URLRequest(url:url);request.timeoutInterval=12;request.setValue("UncleEd/1.0 (personal game library)",forHTTPHeaderField:"User-Agent");let semaphore=DispatchSemaphore(value:0),box=DataBox()
  let task=URLSession.shared.dataTask(with:request){data,response,_ in if let response=response as? HTTPURLResponse,response.statusCode==200,let data,data.count<5_000_000{box.value=data};semaphore.signal()};task.resume()
  if semaphore.wait(timeout:.now()+13) == .timedOut{task.cancel();return nil};return box.value
 }
 private final class DataBox:@unchecked Sendable {var value:Data?}
 private func json(_ url:URL)->[String:Any]?{guard let data=bytes(url) else{return nil};return (try? JSONSerialization.jsonObject(with:data)) as? [String:Any]}
 private func entity(_ id:String)->[String:Any]?{guard id.range(of:"^Q[0-9]+$",options:.regularExpression) != nil,let url=URL(string:"https://www.wikidata.org/wiki/Special:EntityData/"+id+".json") else{return nil};return (json(url)?["entities"] as? [String:[String:Any]])?[id]}
 private func value(_ claim:[String:Any])->Any?{((claim["mainsnak"] as? [String:Any])?["datavalue"] as? [String:Any])?["value"]}
 private func ids(_ rows:[[String:Any]])->[String]{rows.compactMap{(value($0) as? [String:Any])?["id"] as? String}}
 private func lookup(model:String,name:String)->GameCatalogRecord?{
  let title=Self.title(name);var result=Self.verifiedRegionalRecord(model:model,name:name) ?? GameCatalogRecord(title:title)
  let pokemonAliases=["pokemonfirered":"Pokémon FireRed and LeafGreen","pokemonleafgreen":"Pokémon FireRed and LeafGreen","pokemongold":"Pokémon Gold and Silver","pokemonsilver":"Pokémon Gold and Silver","pokemonblack":"Pokémon Black and White","pokemonwhite":"Pokémon Black and White","pokemonheartgold":"Pokémon HeartGold and SoulSilver","pokemonsoulsilver":"Pokémon HeartGold and SoulSilver"]
  let identity=pokemonAliases[Self.normalized(title)] ?? Self.canonicalTitle(model:model,name:title)
  let searchTitle=identity.replacingOccurrences(of:":",with:" ").replacingOccurrences(of:"Version",with:"",options:.caseInsensitive).split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")
  let platformIDs:[String:Set<String>]=["gba":["Q188642"],"gbc":["Q203992","Q941"],"nds":["Q170323"],"psp":["Q170325"],"3ds":["Q203597"]]
  var components=URLComponents(string:"https://www.wikidata.org/w/api.php")!;components.queryItems=[URLQueryItem(name:"action",value:"wbsearchentities"),URLQueryItem(name:"format",value:"json"),URLQueryItem(name:"language",value:Self.searchLanguage(identity)),URLQueryItem(name:"type",value:"item"),URLQueryItem(name:"limit",value:"5"),URLQueryItem(name:"search",value:searchTitle)]
  let candidates=json(components.url!)?["search"] as? [[String:Any]] ?? []
  for candidate in candidates{
   guard let id=candidate["id"] as? String,let entity=entity(id) else{continue}
   let labels=entity["labels"] as? [String:[String:Any]] ?? [:],aliases=entity["aliases"] as? [String:[[String:Any]]] ?? [:],names=labels.values.compactMap{$0["value"] as? String}+aliases.values.flatMap{$0}.compactMap{$0["value"] as? String}
   guard names.contains(where:{Self.normalized($0)==Self.normalized(identity)}) else{continue}
   let claims=entity["claims"] as? [String:[[String:Any]]] ?? [:]
   guard !Set(ids(claims["P400"] ?? [])).isDisjoint(with:platformIDs[model] ?? []) else{continue}
   result.title=labels["en"]?["value"] as? String ?? title;result.sourceURLs.append("https://www.wikidata.org/wiki/"+id)
   for (property,isPublisher) in [("P123",true),("P178",false)]{let names=ids(claims[property] ?? []).prefix(3).compactMap{item->String? in guard let data=self.entity(item),let labels=data["labels"] as? [String:[String:Any]] else{return nil};return labels["en"]?["value"] as? String};if !names.isEmpty{if isPublisher{result.publisher=result.publisher ?? names.joined(separator:" / ")}else{result.developer=result.developer ?? names.joined(separator:" / ")}}}
   let dates=claims["P577"] ?? [];let territory:String?=name.contains("USA") ? "Q30":name.contains("Europe") ? "Q46":name.contains("Japan") ? "Q17":nil
   let regional=dates.filter{row in let q=row["qualifiers"] as? [String:[[String:Any]]] ?? [:];return (q["P291"] ?? []).contains{(($0["datavalue"] as? [String:Any])?["value"] as? [String:Any])?["id"] as? String == territory || (territory=="Q30" && ((($0["datavalue"] as? [String:Any])?["value"] as? [String:Any])?["id"] as? String)=="Q49")}}
   let pool=regional.isEmpty ? dates:regional
   let date=pool.compactMap{row->String? in guard let v=self.value(row) as? [String:Any],let time=v["time"] as? String,let precision=v["precision"] as? Int,precision>=9 else{return nil};let referenced=(row["references"] as? [[String:Any]])?.isEmpty==false;let length=referenced ? (precision>=11 ? 10:precision==10 ? 7:4):4;return String(time.dropFirst().prefix(length))}.sorted().first
   if result.releaseDate==nil{result.releaseDate=date;result.releaseRegion=regional.isEmpty ? "首次发行":name.contains("USA") ? "北美":name.contains("Europe") ? "欧洲":"日本"}
   break
  }
  let pageTitle=Self.normalized(title)=="grandtheftautoadvance" ? "Grand Theft Auto Game Boy Advance":Self.canonicalTitle(model:model,name:title)
  let slug=pageTitle.folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"en_US_POSIX")).components(separatedBy:CharacterSet.alphanumerics.inverted).filter{!$0.isEmpty}.joined(separator:"-")
  if let url=URL(string:"https://www.metacritic.com/game/"+slug+"/"),let data=bytes(url),let html=String(data:data,encoding:.utf8){
   let variant=["(demo)","(kiosk)","(beta)","(proto)","(dpad)"];let meta=variant.contains(where:{name.lowercased().contains($0)}) ? nil:Self.parseMetacritic(html:html,model:model,title:title)
   if let meta{result.metacritic=meta.score;result.developer=meta.developer ?? result.developer;if let date=meta.date{result.releaseDate=date;result.releaseRegion="Metacritic · 本平台"};result.metacriticURL=url.absoluteString;result.sourceURLs.append(url.absoluteString);result.publisher=meta.publisher ?? result.publisher}
  }
  return result.sourceURLs.isEmpty ? nil:result
 }
 private static func matchingMCName(_ name:String,_ title:String,_ model:String)->Bool{normalized(name)==normalized(title) || normalized(canonicalTitle(model:model,name:name))==normalized(canonicalTitle(model:model,name:title)) || (model=="gba" && normalized(title)=="grandtheftautoadvance" && normalized(name)=="grandtheftauto")}
 private static func platformNames(_ model:String)->Set<String>{["gba":["Game Boy Advance"],"gbc":["Game Boy Color","Game Boy"],"nds":["DS","Nintendo DS"],"psp":["PSP","PlayStation Portable"],"3ds":["3DS","Nintendo 3DS"]][model] ?? []}
 private static func parseNuxt(_ html:String,_ model:String,_ title:String)->(score:Int,publisher:String?,developer:String?,date:String?)?{
  guard let regex=try? NSRegularExpression(pattern:"<script[^>]*id=[\"']__NUXT_DATA__[\"'][^>]*>(.*?)</script>",options:[.caseInsensitive,.dotMatchesLineSeparators]),let match=regex.firstMatch(in:html,range:NSRange(html.startIndex...,in:html)),let range=Range(match.range(at:1),in:html),let data=String(html[range]).data(using:.utf8),let pool=(try? JSONSerialization.jsonObject(with:data)) as? [Any],pool.count<100000 else{return nil}
  func resolve(_ input:Any?)->Any?{guard let input else{return nil};if let ref=input as? Int,ref>=0,ref<pool.count{return pool[ref]};return input}
  for case let main as [String:Any] in pool{
   guard let name=resolve(main["title"]) as? String,matchingMCName(name,title,model),let platformRefs=resolve(main["platforms"]) as? [Any],let production=resolve(main["production"]) as? [String:Any] else{continue}
   var developer=[String](),publisher=[String]()
   for item in resolve(production["companies"]) as? [Any] ?? []{guard let company=resolve(item) as? [String:Any],let name=resolve(company["name"]) as? String,let role=resolve(company["typeName"]) as? String else{continue};if role=="Developer"{developer.append(name)};if role=="Publisher"{publisher.append(name)}}
   for ref in platformRefs{guard let platform=resolve(ref) as? [String:Any],let platformName=resolve(platform["name"]) as? String,platformNames(model).contains(platformName),let scoreData=resolve(platform["criticScoreSummary"]) as? [String:Any],let max=resolve(scoreData["max"]) as? Int,max==100,let score=resolve(scoreData["score"]) as? Int,(0...100).contains(score),let count=resolve(scoreData["reviewCount"]) as? Int,count>0 else{continue}
    return (score,publisher.joined(separator:" / ").nilIfEmpty,developer.joined(separator:" / ").nilIfEmpty,(resolve(platform["releaseDate"]) as? String).map{String($0.prefix(10))})
   }
  };return nil
 }
 static func parseMetacritic(html:String,model:String,title:String)->(score:Int,publisher:String?,developer:String?,date:String?)?{
  if let record=parseNuxt(html,model,title){return record}
  let platforms:[String:Set<String>]=["gba":["Game Boy Advance"],"gbc":["Game Boy Color","Game Boy"],"nds":["DS","Nintendo DS"],"psp":["PSP","PlayStation Portable"],"3ds":["3DS","Nintendo 3DS"]]
  guard let regex=try? NSRegularExpression(pattern:"<script[^>]*type=[\"']application/ld\\+json[\"'][^>]*>(.*?)</script>",options:[.caseInsensitive,.dotMatchesLineSeparators]) else{return nil}
  for match in regex.matches(in:html,range:NSRange(html.startIndex...,in:html)){
   guard let range=Range(match.range(at:1),in:html),let data=String(html[range]).data(using:.utf8),let object=try? JSONSerialization.jsonObject(with:data) else{continue}
   let objects=(object as? [[String:Any]]) ?? (object as? [String:Any]).map{[$0]} ?? []
   for item in objects{
    guard item["@type"] as? String=="VideoGame",let name=item["name"] as? String,matchingMCName(name,title,model) else{continue}
    let list=(item["gamePlatform"] as? [String]) ?? (item["gamePlatform"] as? String).map{[$0]} ?? []
    // Multiple-platform aggregate scores are intentionally left blank.
    guard list.count==1,platforms[model]?.contains(list[0])==true,let rating=item["aggregateRating"] as? [String:Any],rating["name"] as? String=="Metascore",(rating["bestRating"] as? NSNumber)?.intValue==100,let score=(rating["ratingValue"] as? NSNumber)?.intValue,(0...100).contains(score),((rating["reviewCount"] as? NSNumber)?.intValue ?? 0)>0 else{continue}
    let publishers=item["publisher"] as? [[String:Any]] ?? []
    var developer:String?
    if let block=html.range(of:"data-testid=[\"']hero-summary-developer[\"'][^>]*>.*?</p>",options:[.regularExpression,.caseInsensitive]),let links=try? NSRegularExpression(pattern:"<a[^>]*href=[\"']/company/[^\"']+[\"'][^>]*>(.*?)</a>",options:[.caseInsensitive,.dotMatchesLineSeparators]){let text=String(html[block]),names=links.matches(in:text,range:NSRange(text.startIndex...,in:text)).compactMap{m->String? in guard let range=Range(m.range(at:1),in:text) else{return nil};return String(text[range]).replacingOccurrences(of:"<[^>]*>",with:"",options:.regularExpression).replacingOccurrences(of:"&amp;",with:"&").trimmingCharacters(in:.whitespacesAndNewlines)};developer=names.joined(separator:" / ").nilIfEmpty}
    return (score,publishers.compactMap{$0["name"] as? String}.joined(separator:" / ").nilIfEmpty,developer,(item["datePublished"] as? String).map{String($0.prefix(10))})
   }
  };return nil
 }
}
private extension String{var nilIfEmpty:String?{isEmpty ? nil:self}}
