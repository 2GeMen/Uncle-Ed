// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import android.content.Context
import java.io.File
import java.security.MessageDigest
import org.json.JSONObject

/** Versioned upstream runtime resources; preserve locally changed files and never install games/BIOS. */
object SystemResources {
 private fun sha(bytes:ByteArray)=MessageDigest.getInstance("SHA-256").digest(bytes).joinToString(""){"%02x".format(it)}
 fun install(context:Context,system:File){
  val manifest=runCatching{context.assets.open("systems/manifest.json").bufferedReader().use{JSONObject(it.readText())}}.getOrNull()?:return
  val record=File(system,".uncleed-resources.json");val previous=runCatching{JSONObject(record.readText())}.getOrDefault(JSONObject());val next=JSONObject(previous.toString())
  for(name in manifest.keys()){
   check(Motion.validZipPath(name));val target=File(system,name);check(target.canonicalPath.startsWith(system.canonicalPath+File.separator))
   val expected=manifest.getString(name)
   if(target.isFile){val current=sha(target.readBytes());if(current==expected){next.put(name,expected);continue};if(current!=previous.optString(name))continue}
   val bytes=context.assets.open("systems/$name").use{it.readBytes()};check(sha(bytes)==expected){"Runtime resource checksum mismatch"}
   target.parentFile!!.mkdirs();val temp=File(target.parentFile,target.name+".tmp");temp.writeBytes(bytes);check(temp.renameTo(target));next.put(name,expected)
  }
  val temp=File(system,record.name+".tmp");temp.writeText(next.toString());check(temp.renameTo(record))
 }
}
