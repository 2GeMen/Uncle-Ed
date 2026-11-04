import XCTest
@testable import UncleEdDomain
final class GameCatalogTests:XCTestCase {
 func testRegionalAliasesResolveWithoutConfusingOriginalSNESGame(){
  let roman="Fire Emblem - Shin Monshou no Nazo - Hikari to Kage no Eiyuu (Japan)"
  let jp="ファイアーエムブレム 新・紋章の謎 ～光と影の英雄～"
  for name in [roman,jp,"Fire Emblem: New Mystery of the Emblem","火焰纹章 新纹章之谜 光与影的英雄"] {
   XCTAssertEqual(GameCatalog.canonicalTitle(model:"nds",name:name),"Fire Emblem: New Mystery of the Emblem")
   let record=GameCatalog.verifiedRegionalRecord(model:"nds",name:name)
   XCTAssertEqual(record?.developer,"Intelligent Systems");XCTAssertEqual(record?.releaseDate,"2010-07-15");XCTAssertEqual(record?.scoreText,"/")
  }
  XCTAssertNil(GameCatalog.verifiedRegionalRecord(model:"snes",name:roman))
  XCTAssertNil(GameCatalog.verifiedRegionalRecord(model:"nds",name:"Fire Emblem - Monshou no Nazo"))
  XCTAssertEqual(GameCatalog.searchLanguage(jp),"ja");XCTAssertEqual(GameCatalog.searchLanguage("火焰纹章"),"zh");XCTAssertEqual(GameCatalog.searchLanguage("Fire Emblem"),"en")
 }
 private func page(platforms:String="[\"Game Boy Advance\"]",name:String="Metascore",title:String="Pokemon Emerald Version")->String{
  "<script type=\"application/ld+json\">{\"@type\":\"VideoGame\",\"name\":\"\(title)\",\"gamePlatform\":\(platforms),\"aggregateRating\":{\"name\":\"\(name)\",\"bestRating\":100,\"ratingValue\":76,\"reviewCount\":28}}</script>"
 }
 func testOfficialCriticScoreRequiresMatchingPlatformAndTitle(){
  XCTAssertEqual(GameCatalog.parseMetacritic(html:page(),model:"gba",title:"Pokemon - Emerald Version (USA)")?.score,76)
  XCTAssertNil(GameCatalog.parseMetacritic(html:page(),model:"gbc",title:"Pokemon Emerald"))
  XCTAssertNil(GameCatalog.parseMetacritic(html:page(),model:"gba",title:"Pokemon FireRed"))
 }
 func testNeverUsesUserOrMultiplePlatformAggregate(){
  XCTAssertNil(GameCatalog.parseMetacritic(html:page(name:"User score"),model:"gba",title:"Pokemon Emerald"))
  XCTAssertNil(GameCatalog.parseMetacritic(html:page(platforms:"[\"Game Boy Advance\",\"Nintendo Switch\"]"),model:"gba",title:"Pokemon Emerald"))
 }
 func testFullSubtitleAndRegionRemainDistinct(){
  XCTAssertEqual(GameCatalog.title("Legend of Zelda, The - Oracle of Ages (USA).gbc"),"The Legend of Zelda: Oracle of Ages")
  XCTAssertNotEqual(GameCatalog.key(model:"gba",name:"Pokemon Emerald (USA)"),GameCatalog.key(model:"gba",name:"Pokemon Emerald (Japan)"))
  XCTAssertEqual(GameCatalogRecord(title:"Unknown").scoreText,"/")
 }
 func testMultiPlatformPageReadsOnlyExactPlatformCriticSummary(){
  let pool:[Any]=[["title":1,"platforms":2,"production":3],"Pokemon Emerald Version",[4,5],["companies":6],["name":7,"criticScoreSummary":8,"releaseDate":9],["name":10,"criticScoreSummary":11,"releaseDate":12],[],"Game Boy Advance",["max":13,"score":14,"reviewCount":15],"2005-04-30","Nintendo Switch",["max":13,"score":16,"reviewCount":15],"2026-02-27",100,76,28,94]
  let json=String(data:try! JSONSerialization.data(withJSONObject:pool),encoding:.utf8)!
  let html="<script id=\"__NUXT_DATA__\" type=\"application/json\">"+json+"</script>"
  XCTAssertEqual(GameCatalog.parseMetacritic(html:html,model:"gba",title:"Pokemon Emerald")?.score,76)
  XCTAssertNil(GameCatalog.parseMetacritic(html:html,model:"nds",title:"Pokemon Emerald"))
 }

}
