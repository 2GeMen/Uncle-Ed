// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import android.app.Instrumentation
import android.os.Bundle
import java.io.*
import java.util.UUID
import java.util.zip.*
import org.json.JSONObject

/** Original byte fixtures in unique cache roots; never touches the real library. */
fun runImportIntegrityProbe(probe:Instrumentation){val result=Bundle();val base=File(probe.targetContext.cacheDir,"import-integrity-${UUID.randomUUID()}").also{it.mkdirs()}
 try{
  fun library(name:String)=GameLibrary(File(base,name).also{it.mkdirs()})
  fun zip(entries:List<Pair<String,ByteArray>>):ByteArray {val bytes=ByteArrayOutputStream();ZipOutputStream(bytes).use{out->entries.forEach{(name,data)->val e=ZipEntry(name);e.method=ZipEntry.STORED;e.size=data.size.toLong();e.compressedSize=e.size;e.crc=CRC32().also{it.update(data)}.value;out.putNextEntry(e);out.write(data);out.closeEntry()}};return bytes.toByteArray()}
  fun rejected(f:()->Unit){var rejected=false;try{f()}catch(_:Exception){rejected=true};check(rejected){"Expected rejected import"}}
  val duplicate=library("duplicate");val original=byteArrayOf(17,33,51,79);val g=duplicate.import(original.inputStream(),"Original Game (USA).gba").single();check(g.originalName=="Original Game (USA).gba")
  check(duplicate.import(original.inputStream(),"renamed.gba").isEmpty());check(duplicate.import(zip(listOf("folder/same.gba" to original)).inputStream(),"same.zip").isEmpty());check(duplicate.snapshot().size==1)
  val limit=library("limit");rejected{limit.import(zip((0..100).map{"game-$it.gba" to byteArrayOf(it.toByte(),1)}).inputStream(),"101.zip")};check(limit.snapshot().isEmpty());check(limit.import(zip((0..99).map{"game-$it.gba" to byteArrayOf(it.toByte(),1)}).inputStream(),"100.zip").size==100)
  val unsafe=library("unsafe");rejected{unsafe.import(zip(listOf("valid.gba" to original,"../escape.gba" to original)).inputStream(),"unsafe.zip")};check(unsafe.snapshot().isEmpty());check(!File(base,"escape.gba").exists())
  val crc=library("crc");val broken=zip(listOf("broken.gba" to original));val nameBytes=(broken[26].toInt() and 255) or ((broken[27].toInt() and 255) shl 8);val extraBytes=(broken[28].toInt() and 255) or ((broken[29].toInt() and 255) shl 8);broken[30+nameBytes+extraBytes]=99
  rejected{crc.import(broken.inputStream(),"damaged.zip")};check(crc.snapshot().isEmpty());check(File(base,"crc/roms").listFiles()!!.isEmpty())
  // A later damaged member must not hide an earlier successful import or
  // leave the damaged bytes in the library after reopening it.
  val mixed=library("mixed");val mixedZip=zip(listOf("first.gba" to original,"broken.gba" to byteArrayOf(91,92,93,94)))
  val firstLocalSize=30+"first.gba".toByteArray().size+original.size
  mixedZip[firstLocalSize+30+"broken.gba".toByteArray().size]=95
  rejected{mixed.import(mixedZip.inputStream(),"mixed.zip")};check(mixed.snapshot().single().id==g.id)
  check(library("mixed").snapshot().single().id==g.id);check(File(base,"mixed/roms").listFiles()!!.size==1)
  val partial=library("provider-failure");val failing=object:InputStream(){var reads=0;override fun read()=throw IOException("provider disconnected");override fun read(b:ByteArray,off:Int,len:Int):Int{if(reads++>0)throw IOException("provider disconnected");b[off]=12;return 1}}
  rejected{partial.import(failing,"partial.gba")};check(partial.snapshot().isEmpty());check(File(base,"provider-failure").listFiles()!!.none{it.extension=="part"})
  val rollback=library("rollback");check(File(base,"rollback/library.json").mkdir());rejected{rollback.import(original.inputStream(),"valid.gba")};check(rollback.snapshot().isEmpty());check(File(base,"rollback/roms").listFiles()!!.isEmpty());check(!File(base,"rollback/library.tmp").exists())
  val orphan=library("orphan");val id=java.security.MessageDigest.getInstance("SHA-256").digest(original).joinToString(""){"%02x".format(it)};val orphanFile=File(base,"orphan/roms/$id.gba");orphanFile.writeBytes(original);check(orphan.import(original.inputStream(),"Recovered (USA).gba").single().id==id);check(orphanFile.readBytes().contentEquals(original))
  val mismatch=library("mismatched-orphan");val wrongFile=File(base,"mismatched-orphan/roms/$id.gba");val wrong=byteArrayOf(1,2,3,4);wrongFile.writeBytes(wrong);rejected{mismatch.import(original.inputStream(),"Preserve.gba")};check(mismatch.snapshot().isEmpty());check(wrongFile.readBytes().contentEquals(wrong))
  check(base.walkTopDown().none{it.isFile&&(it.extension=="part"||it.name.startsWith("archive-"))})
  File(probe.targetContext.filesDir,"import-integrity-review.json").writeText(JSONObject().put("originalByteFixturesOnly",true).put("realLibraryUntouched",true).put("max100BeforeWrite",true).put("crcBeforeCommit",true).put("renamedAndZipDuplicate",true).put("unsafeBeforeWrite",true).put("providerAndPersistFailureCleanup",true).toString(2))
  result.putString("result","PASS: original-name retention, renamed/ZIP dedupe, 100 accepted/101 rejected before write, unsafe path preflight, CRC mismatch, provider interruption, persist rollback and verified orphan adoption; real library untouched");probe.finish(-1,result)
 }catch(e:Throwable){result.putString("error",e.stackTraceToString());probe.finish(0,result)}finally{base.deleteRecursively()}}
