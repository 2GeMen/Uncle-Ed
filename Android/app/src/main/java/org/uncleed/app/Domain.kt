package org.uncleed.app

import java.io.*
import java.security.MessageDigest
import java.util.zip.ZipFile
import java.util.zip.CRC32
import org.json.JSONArray
import org.json.JSONObject

enum class Machine(val label:String,val extensionSet:Set<String>,val maxBytes:Long,val core:String,val themes:List<String>) {
    GBC("Game Boy Color",setOf("gb","gbc"),16L*1024*1024,"mgba_libretro",listOf("宝可梦中心限定","经典原始配色","经典黄配色","黑磨砂")),
    GBA("Game Boy Advance",setOf("gba"),64L*1024*1024,"mgba_libretro",listOf("原生黄色","索尼克定制","EVA 定制","白色磨砂半透明")),
    NDS("Nintendo DS",setOf("nds"),1024L*1024*1024,"melondsds_libretro",listOf("宝可梦黑白限定版","马里奥限定版","塞尔达限定版","黑磨砂")),
    PSP("PlayStation Portable",setOf("iso","cso","pbp","chd"),2560L*1024*1024,"ppsspp_libretro",listOf("最终幻想限定","怪物猎人限定","实况足球限定","黑磨砂")),
    N3DS("Nintendo 3DS",setOf("3ds","cci","cxi","3dsx"),8L*1024*1024*1024,"azahar_libretro",listOf("塞尔达限定","宝可梦日月限定","大乱斗限定","黑磨砂"));
    val key:String get()=if(this==N3DS) "3ds" else name.lowercase()
    companion object { fun detect(name:String)=entries.firstOrNull{name.substringAfterLast('.').lowercase() in it.extensionSet};fun available(tablet:Boolean)=if(tablet) listOf(NDS,GBA,GBC,PSP,N3DS) else listOf(GBA,GBC,PSP) }
}
data class Game(val id:String,val machine:Machine,val title:String,val name:String,val originalName:String=name) {
    fun json()=JSONObject().put("id",id).put("machine",machine.name).put("title",title).put("name",name).put("originalName",originalName)
}
object Motion {
    fun clampPage(current:Int,delta:Int,count:Int)=(current+delta.coerceIn(-1,1)).coerceIn(0,(count-1).coerceAtLeast(0))
    fun dpad(x:Float,y:Float):Set<Int> {
        if(x*x+y*y<0.01f) return emptySet()
        return buildSet { if(x<-.3f)add(6);if(x>.3f)add(7);if(y<-.3f)add(4);if(y>.3f)add(5) }
    }
    fun validZipPath(s:String)=s.isNotEmpty()&&!s.startsWith('/')&&!s.contains('\\')&&!s.contains('\u0000')&&!s.contains(':')&&s.split('/').none{it==".."}
    fun gameTitle(name:String)=name.substringBeforeLast('.').replace(Regex("\\s*\\([^)]*\\)|\\s*\\[[^]]*]"),"").trim().ifEmpty{"Untitled"}
    fun originalForm(m:Machine)=if(m==Machine.GBC) "portrait" else "landscape"
    fun stick(x:Float,y:Float):Pair<Float,Float>{val length=kotlin.math.hypot(x,y).coerceAtLeast(1f);return x/length to y/length}
    fun displayTitle(name:String):String {
        var value=gameTitle(name)
        val article=Regex(", The",RegexOption.IGNORE_CASE)
        if(article.containsMatchIn(value))value="The "+value.replace(article,"")
        return value.replace(" - ",": ").replace(Regex("\\s+")," ").trim()
    }
}
class InputState {
    private val pointers=mutableMapOf<Int,Set<Int>>()
    @Synchronized fun replace(pointer:Int,buttons:Set<Int>):Set<Int>{pointers[pointer]=buttons;return held()}
    @Synchronized fun release(pointer:Int):Set<Int>{pointers.remove(pointer);return held()}
    @Synchronized fun clear(){pointers.clear()}
    @Synchronized fun held()=pointers.values.flatten().toSet()
    @Synchronized fun mask()=held().fold(0){a,b->a or (1 shl b)}
}
class GameLibrary(private val root:File) {
    private val db=File(root,"library.json")
    private val roms=File(root,"roms").also{it.mkdirs()}
    val games=mutableListOf<Game>()
    init { if(db.exists()) {val a=JSONArray(db.readText());for(i in 0 until a.length()){val o=a.getJSONObject(i);games+=Game(o.getString("id"),Machine.valueOf(o.getString("machine")),o.getString("title"),o.getString("name"),o.optString("originalName",o.getString("name")))}} }
    @Synchronized fun snapshot()=games.toList()
    @Synchronized private fun persist(){val a=JSONArray();games.forEach{a.put(it.json())};val tmp=File(root,"library.tmp");try{tmp.writeText(a.toString());check(tmp.renameTo(db)){"Cannot commit library"}}finally{tmp.delete()}}
    fun file(g:Game)=File(roms,g.name)
    /** Archive records rather than deleting user data; saves are never touched. */
    @Synchronized fun archiveInvalidEntries(includeDevelopment:Boolean=false):JSONObject {
        val knownProbe="a98622cf30dc00204b04217f4f5e41d6d7649e31fdcf5d21b0b465c3ad7c222b"
        val seen=mutableSetOf<String>();val removed=JSONArray();val keep=mutableListOf<Game>()
        for(g in games){
            val f=file(g);val inside=g.name==File(g.name).name&&f.canonicalFile.parentFile==roms.canonicalFile
            val reason=when{!inside->"invalid-path";g.id in seen->"duplicate-record";!f.isFile->"missing-file";f.length()==0L->"empty-file";includeDevelopment&&g.id==knownProbe&&f.length()==272L&&MessageDigest.getInstance("SHA-256").digest(f.readBytes()).joinToString(""){"%02x".format(it)}==knownProbe->"development-fixture";else->null}
            if(reason==null){keep+=g;seen+=g.id} else removed.put(JSONObject().put("game",g.json()).put("reason",reason))
        }
        if(removed.length()==0)return JSONObject().put("archived",0).put("remaining",games.size)
        val archive=File(root,"archive/library-${System.currentTimeMillis()}").also{check(it.mkdirs())}
        if(db.isFile)db.copyTo(File(archive,"library-before.json"))
        File(archive,"manifest.json").writeText(removed.toString(2))
        // Preserve the verified in-house fixture and zero-length files for recovery.
        val old=games.toList();val moved=mutableListOf<Pair<File,File>>()
        try{for(i in 0 until removed.length()) {val row=removed.getJSONObject(i);if(row.getString("reason") in setOf("development-fixture","empty-file")){
            val name=row.getJSONObject("game").getString("name");val f=File(roms,name)
            if(keep.none{it.name==name}&&f.isFile){val target=File(archive,name);check(f.renameTo(target)){"Cannot archive unusable content"};moved+=f to target}
        }}
        games.clear();games+=keep;persist()}catch(e:Exception){games.clear();games+=old;moved.asReversed().forEach{(original,archived)->check(archived.renameTo(original)){"Restore archive ${archive.name} before retrying"}};throw e}
        return JSONObject().put("archived",removed.length()).put("remaining",games.size).put("archive",archive.name).put("entries",removed).put("savesTouched",false)
    }
    @Synchronized fun import(input:InputStream,name:String):List<Game> {
        val result=mutableListOf<Game>()
        if(name.endsWith(".zip",true)) {
            // A local central-directory preflight enforces the same 100-ROM
            // limit as iOS before any member becomes visible in the library.
            val archive=File.createTempFile("archive-",".zip",root)
            try {
                input.use{source->archive.outputStream().buffered().use{out->val bytes=ByteArray(128*1024);var compressed=0L;while(true){val n=source.read(bytes);if(n<0)break;compressed+=n;check(compressed<=12L*1024*1024*1024){"压缩包过大"};out.write(bytes,0,n)}}}
                ZipFile(archive).use{zip->
                    val entries=zip.entries().toList();check(entries.size<=256){"ZIP 条目过多"};check(entries.all{Motion.validZipPath(it.name)}){"压缩包包含不安全路径"}
                    val supported=entries.filter{!it.isDirectory&&Machine.detect(it.name)!=null}
                    check(supported.isNotEmpty()){"压缩包中没有支持的 ROM"};check(supported.size<=100){"单个 ZIP 最多导入 100 个 ROM，请拆分压缩包"}
                    val budget=DecodeBudget(12L*1024*1024*1024);val discard=ByteArray(128*1024)
                    for(entry in entries){if(entry.isDirectory)continue
                        val m=Machine.detect(entry.name)
                        zip.getInputStream(entry).use{source->
                            val decoded=object:InputStream(){
                                override fun read():Int{val value=source.read();if(value>=0)budget.add(1);return value}
                                override fun read(bytes:ByteArray,offset:Int,length:Int):Int{val n=source.read(bytes,offset,length);if(n>0)budget.add(n.toLong());return n}
                            }
                            if(m!=null){check(entry.size<=m.maxBytes){"文件大小超过该机型范围"};copy(decoded,File(entry.name).name,m,entry.crc)?.let(result::add)}
                            else while(decoded.read(discard)>=0){}
                        }
                    }
                }
            }finally{archive.delete()}
        } else input.use{val m=Machine.detect(name)?:error("Unsupported file. Import a ROM or ZIP.");copy(it,name,m)?.let(result::add)}
        return result
    }
    private fun copy(input:InputStream,name:String,m:Machine,expectedCrc:Long?=null):Game? {
        val tmp=File.createTempFile("import-",".part",root);val sha=MessageDigest.getInstance("SHA-256");val crc=CRC32();var size=0L
        try {tmp.outputStream().buffered().use{out->val b=ByteArray(128*1024);while(true){val n=input.read(b);if(n<0)break;size+=n;check(size<=m.maxBytes){"File too large"};sha.update(b,0,n);if(expectedCrc!=null)crc.update(b,0,n);out.write(b,0,n)}};check(size>0){"Empty file"};check(expectedCrc==null||expectedCrc>=0&&crc.value==expectedCrc){"ZIP 校验失败，文件可能已损坏"};val id=sha.digest().joinToString(""){"%02x".format(it)}
            if(games.any{it.id==id})return null
            val fileName=id+"."+name.substringAfterLast('.').lowercase();val target=File(roms,fileName);val existing=target.exists()
            if(existing){check(target.canonicalFile.parentFile==roms.canonicalFile&&target.isFile&&target.length()==size){"目标资源文件异常，未覆盖原文件"};val digest=MessageDigest.getInstance("SHA-256");target.inputStream().buffered().use{stream->val b=ByteArray(128*1024);while(true){val n=stream.read(b);if(n<0)break;digest.update(b,0,n)}};check(digest.digest().joinToString(""){"%02x".format(it)}==id){"目标资源内容不一致，未覆盖原文件"}}
            else check(tmp.renameTo(target)){"Cannot store ROM"}
            val g=Game(id,m,Motion.gameTitle(name),fileName,name);games+=g;try{persist()}catch(e:Exception){games.remove(g);if(!existing)target.delete();throw e};return g
        }finally{tmp.delete()}
    }
}

/** Counts actual inflated bytes, including ignored entries and unknown ZIP lengths. */
class DecodeBudget(private val limit:Long) {
    var used:Long=0;private set
    fun add(bytes:Long){require(bytes>=0);check(bytes<=limit-used){"Archive too large"};used+=bytes}
}
