// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app

import android.content.Context
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/** Names/platform/region only leave the device. ROMs and saves are never read here. */
class GameResources(private val context:Context,private val transport:((String,Int)->ByteArray)?=null,private val changed:(String)->Unit) {
 private val root=File(context.filesDir,"game-resources").also{it.mkdirs()}
 private val covers=Executors.newFixedThreadPool(2)
 private val metadata=Executors.newSingleThreadExecutor()
 private val main=Handler(Looper.getMainLooper())
 private val records=ConcurrentHashMap<String,JSONObject>()
 private val pending=ConcurrentHashMap.newKeySet<String>()
 private val failed=ConcurrentHashMap<String,Long>()
 private val errors=ConcurrentHashMap<String,String>()
 private val completed=ConcurrentHashMap<String,Long>()
 private val indexes=ConcurrentHashMap<Machine,Map<String,String>>()
 private val locks=Machine.entries.associateWith{Any()}
 private var seed=JSONObject()
 init{metadata.execute{seed=runCatching{context.assets.open("catalog/catalog-v1.json").bufferedReader().use{JSONObject(it.readText())}}.getOrDefault(JSONObject())}}
 fun cached(game:Game)=records[game.id]
 internal fun status(game:Game)=JSONObject().put("coverCached",coverFile(game)!=null).put("metadataCached",cached(game)!=null).put("coverPending",pending.contains("cover:${game.id}")).put("metadataPending",pending.contains("meta:${game.id}")).put("coverError",errors["cover:${game.id}"]?:"").put("metadataError",errors["meta:${game.id}"]?:"")
 fun coverFile(game:Game)=File(root,game.id+".png").takeIf{it.isFile}
 private fun notify(id:String){main.post{changed(id)}}
 fun request(game:Game){
  for(kind in listOf("cover","meta")){
   val key="$kind:${game.id}";if((failed[key]?:0)>System.currentTimeMillis()-30*60*1000||(completed[key]?:0)>System.currentTimeMillis()-7*86400000L||!pending.add(key))continue
   failed.remove(key)
   val worker=if(kind=="cover")covers else metadata
   worker.execute{try{
    if(kind=="cover"){
     if(coverFile(game)==null){val index=index(game.machine);val match=ResourceMatch.cover(game.originalName,index.keys.toList());if(match!=null){val url=index.getValue(match);val bytes=get(url,8*1024*1024);val bounds=BitmapFactory.Options().apply{inJustDecodeBounds=true};BitmapFactory.decodeByteArray(bytes,0,bytes.size,bounds);check(bounds.outWidth in 1..8192&&bounds.outHeight in 1..8192&&bounds.outWidth.toLong()*bounds.outHeight<=20000000){"Invalid artwork"};atomic(File(root,game.id+".png"),bytes);atomic(File(root,game.id+"-cover.json"),JSONObject().put("name",match).put("url",url).put("source","Libretro thumbnails").put("machine",game.machine.key).toString().toByteArray())}else failed[key]=System.currentTimeMillis()}
    }else{
     val file=File(root,game.id+".json");var record=runCatching{JSONObject(file.readText())}.getOrNull()?:seed.optJSONObject(ResourceMatch.key(game))?.let{JSONObject(it.toString()).put("checkedMs",System.currentTimeMillis())}
     if(record!=null){records[game.id]=record;notify(game.id)}
     if(record==null||record.optLong("checkedMs")<System.currentTimeMillis()-7*86400000L){record=lookup(game)}
     if(record!=null){records[game.id]=record;atomic(file,record.toString().toByteArray())}else failed[key]=System.currentTimeMillis()
    }
   if(!failed.containsKey(key))completed[key]=System.currentTimeMillis()
   }catch(e:Exception){failed[key]=System.currentTimeMillis();errors[key]=e.toString()}finally{pending.remove(key);notify(game.id)}}
  }
 }
 private fun atomic(file:File,bytes:ByteArray){val tmp=File(file.parentFile,file.name+".tmp");tmp.writeBytes(bytes);check(tmp.renameTo(file))}
 private fun index(machine:Machine):Map<String,String> = synchronized(locks.getValue(machine)) {
  indexes[machine]?.let{return@synchronized it}
  val file=File(root,"index-${machine.key}.json")
  var array=runCatching{JSONArray(file.readText())}.getOrNull()?:runCatching{context.assets.open("catalog/cover-index-${machine.key}.json").bufferedReader().use{JSONArray(it.readText())}}.getOrNull()
  if(array==null){
   val repo=mapOf(Machine.GBA to "Nintendo_-_Game_Boy_Advance",Machine.GBC to "Nintendo_-_Game_Boy_Color",Machine.NDS to "Nintendo_-_Nintendo_DS",Machine.PSP to "Sony_-_PlayStation_Portable",Machine.N3DS to "Nintendo_-_Nintendo_3DS").getValue(machine)
   val category=repo.replace('_',' ');val tree=JSONObject(String(get("https://api.github.com/repos/libretro-thumbnails/$repo/git/trees/master?recursive=1",16*1024*1024))).getJSONArray("tree")
   array=JSONArray();for(i in 0 until tree.length()){val path=tree.getJSONObject(i).optString("path");if(path.startsWith("Named_Boxarts/")&&path.endsWith(".png")){val url="https://thumbnails.libretro.com/"+(category+"/"+path).split('/').joinToString("/"){URLEncoder.encode(it,"UTF-8").replace("+","%20")};array.put(JSONObject().put("name",path.removePrefix("Named_Boxarts/").removeSuffix(".png")).put("url",url))}}
  }
  check(array.length()>0);atomic(file,array.toString().toByteArray());val result=buildMap<String,String>{for(i in 0 until array.length()){val e=array.getJSONObject(i);put(e.getString("name"),e.getString("url"))}};indexes[machine]=result;result
 }
 private fun get(address:String,limit:Int):ByteArray {
  transport?.let{return it(address,limit)}
  check(context.getSharedPreferences("resource-network-consent",0).getBoolean("approved-v1",false)){"等待自动匹配的联网授权"}
  var url=URL(address);repeat(4){
   check(url.protocol=="https"&&url.host in setOf("api.github.com","thumbnails.libretro.com","www.wikidata.org","www.metacritic.com")){"Unsupported resource host"}
   val c=url.openConnection() as HttpURLConnection;c.connectTimeout=8000;c.readTimeout=12000;c.instanceFollowRedirects=false;c.setRequestProperty("User-Agent","UncleEd/1.0 (personal game library)")
   try{val code=c.responseCode;if(code in 300..399){url=URL(url,c.getHeaderField("Location"));return@repeat};check(code==200){"HTTP $code"};check(c.contentLengthLong<=limit)
    return c.inputStream.use{input->val out=java.io.ByteArrayOutputStream();val b=ByteArray(32768);while(true){val n=input.read(b);if(n<0)break;check(out.size()+n<=limit);out.write(b,0,n)};out.toByteArray()}
   }finally{c.disconnect()}
  };error("Too many redirects")
 }
 private fun entity(id:String):JSONObject {check(id.matches(Regex("Q[0-9]+")));return JSONObject(String(get("https://www.wikidata.org/wiki/Special:EntityData/$id.json",5000000))).getJSONObject("entities").getJSONObject(id)}
 private fun ids(claims:JSONObject,property:String):List<String> {val rows=claims.optJSONArray(property)?:return emptyList();return (0 until rows.length()).mapNotNull{rows.getJSONObject(it).optJSONObject("mainsnak")?.optJSONObject("datavalue")?.optJSONObject("value")?.optString("id")?.takeIf{it.matches(Regex("Q[0-9]+"))}}}
 private fun lookup(game:Game):JSONObject? {
  var record=runCatching{lookupWikidata(game)}.getOrNull()
  if(ResourceMatch.variant(game.originalName).isEmpty())runCatching{
   val name=ResourceMatch.title(game.originalName)
   val plain=java.text.Normalizer.normalize(name,java.text.Normalizer.Form.NFD).replace(Regex("\\p{M}+"),"").lowercase(java.util.Locale.ROOT)
   val slug=plain.replace(Regex("[^a-z0-9]+"),"-").trim('-');val url="https://www.metacritic.com/game/$slug/"
   CatalogScore.parse(String(get(url,5000000)),game.machine,name)?.let{score->
    if(record==null)record=JSONObject().put("title",name).put("checkedMs",System.currentTimeMillis()).put("sourceURLs",JSONArray())
    val target=record!!;for(key in score.keys())target.put(key,score.get(key));target.put("metacriticURL",url);target.getJSONArray("sourceURLs").put(url)
   }
  }
  return record
 }
 private fun lookupWikidata(game:Game):JSONObject? {
  if(ResourceMatch.variant(game.originalName).isNotEmpty())return null
  val title=ResourceMatch.title(game.originalName);val identity=ResourceMatch.identity(game.originalName)
  val platforms=mapOf(Machine.GBA to setOf("Q188642"),Machine.GBC to setOf("Q203992","Q941"),Machine.NDS to setOf("Q170323"),Machine.PSP to setOf("Q170325"),Machine.N3DS to setOf("Q203597"))
  val query=URLEncoder.encode(identity.replace(":"," "),"UTF-8")
  val candidates=JSONObject(String(get("https://www.wikidata.org/w/api.php?action=wbsearchentities&format=json&language=en&type=item&limit=5&search=$query",5000000))).getJSONArray("search")
  for(i in 0 until candidates.length()){
   val id=candidates.getJSONObject(i).getString("id");val data=entity(id);val labels=data.optJSONObject("labels")?:continue;val names=labels.keys().asSequence().map{labels.getJSONObject(it).optString("value")}.toMutableList()
   data.optJSONObject("aliases")?.let{aliases->for(lang in aliases.keys()){val a=aliases.getJSONArray(lang);for(j in 0 until a.length())names+=a.getJSONObject(j).optString("value")}}
   if(names.none{ResourceMatch.normalized(it)==ResourceMatch.normalized(identity)})continue
   val claims=data.getJSONObject("claims");if(ids(claims,"P400").none{it in platforms.getValue(game.machine)})continue
   val record=JSONObject().put("title",title).put("checkedMs",System.currentTimeMillis()).put("sourceURLs",JSONArray().put("https://www.wikidata.org/wiki/$id"))
   for((property,key) in listOf("P178" to "developer","P123" to "publisher")){val values=ids(claims,property).take(3).mapNotNull{entity(it).optJSONObject("labels")?.optJSONObject("en")?.optString("value")};if(values.isNotEmpty())record.put(key,values.joinToString(" / "))}
   val dates=claims.optJSONArray("P577");val times=mutableListOf<String>();if(dates!=null)for(j in 0 until dates.length()){val d=dates.getJSONObject(j).optJSONObject("mainsnak")?.optJSONObject("datavalue")?.optJSONObject("value");if(d!=null&&d.optInt("precision")>=11){val time=d.optString("time").removePrefix("+").take(10);if(time.matches(Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}")))times+=time}}
   times.minOrNull()?.let{record.put("releaseDate",it).put("releaseRegion","首次发行")}
   // Never infer a score from another platform or from user ratings. Existing
   // verified platform-specific records are reused; absent scores display '/'.
   return record
  };return null
 }
 fun retryAfterConsent(games:List<Game>){failed.clear();errors.clear();completed.clear();games.forEach{request(it)}}
 fun close(){covers.shutdownNow();metadata.shutdownNow()}
}
