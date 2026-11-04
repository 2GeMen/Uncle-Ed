// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import org.json.JSONArray
import org.json.JSONObject

/** Only Metacritic's explicit critic summary for an exact matching platform/title. */
object CatalogScore {
 fun parse(html:String,machine:Machine,title:String):JSONObject? {
  val data=Regex("<script[^>]*id=[\"']__NUXT_DATA__[\"'][^>]*>(.*?)</script>",setOf(RegexOption.IGNORE_CASE,RegexOption.DOT_MATCHES_ALL)).find(html)?.groupValues?.get(1)?:return null
  val pool=runCatching{JSONArray(data)}.getOrNull()?:return null;if(pool.length()>100000)return null
  fun resolve(v:Any?):Any?=if(v is Int&&v>=0&&v<pool.length())pool.opt(v)else v
  val platforms=when(machine){Machine.GBA->setOf("Game Boy Advance");Machine.GBC->setOf("Game Boy Color","Game Boy");Machine.NDS->setOf("DS","Nintendo DS");Machine.PSP->setOf("PSP","PlayStation Portable");Machine.N3DS->setOf("3DS","Nintendo 3DS")}
  for(i in 0 until pool.length()){
   val item=pool.optJSONObject(i)?:continue;val name=resolve(item.opt("title")) as? String?:continue
   val same=ResourceMatch.normalized(name)==ResourceMatch.normalized(title)||(machine==Machine.GBA&&ResourceMatch.normalized(title)=="grandtheftautoadvance"&&ResourceMatch.normalized(name)=="grandtheftauto")
   if(!same||ResourceMatch.variant(title).isNotEmpty())continue
   val list=resolve(item.opt("platforms")) as? JSONArray?:continue
   for(j in 0 until list.length()){
    val platform=resolve(list.opt(j)) as? JSONObject?:continue;if(resolve(platform.opt("name")) !in platforms)continue
    val critic=resolve(platform.opt("criticScoreSummary")) as? JSONObject?:continue
    val max=(resolve(critic.opt("max")) as? Number)?.toInt();val score=(resolve(critic.opt("score")) as? Number)?.toInt();val count=(resolve(critic.opt("reviewCount")) as? Number)?.toInt()?:0
    if(max!=100||score==null||score !in 0..100||count<=0)continue
    val result=JSONObject().put("metacritic",score)
    (resolve(platform.opt("releaseDate")) as? String)?.takeIf{it.matches(Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}.*"))}?.let{result.put("releaseDate",it.take(10)).put("releaseRegion","Metacritic · 本平台")}
    val production=resolve(item.opt("production")) as? JSONObject;val companies=production?.let{resolve(it.opt("companies")) as? JSONArray}
    for((role,key) in listOf("Developer" to "developer","Publisher" to "publisher")){val names=mutableListOf<String>();if(companies!=null)for(k in 0 until companies.length()){val company=resolve(companies.opt(k)) as? JSONObject?:continue;if(resolve(company.opt("typeName"))==role)(resolve(company.opt("name")) as? String)?.let(names::add)};if(names.isNotEmpty())result.put(key,names.joinToString(" / "))}
    return result
   }
  };return null
 }
}
