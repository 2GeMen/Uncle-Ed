// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import android.app.Instrumentation
import android.os.Bundle
import java.io.ByteArrayInputStream
import java.io.File
import org.json.JSONArray

/** Exercise real archive transactions in a new cache sandbox, never the user's collection. */
fun runLibraryRepairReview(probe:Instrumentation){val result=Bundle();try{
    val base=File(probe.targetContext.cacheDir,"library-repair-${System.nanoTime()}").also{it.mkdirs()}
    val root=File(base,"collection").also{it.mkdirs()};val library=GameLibrary(root)
    val valid=library.import(ByteArrayInputStream(byteArrayOf(1,2,3)),"valid.gba").single()
    val missing=library.import(ByteArrayInputStream(byteArrayOf(4,5,6)),"missing.gba").single();check(library.file(missing).delete())
    val empty=library.import(ByteArrayInputStream(byteArrayOf(7,8,9)),"empty.gba").single();library.file(empty).writeBytes(byteArrayOf())
    val save=File(root,"saves/${valid.id}.srm").also{it.parentFile!!.mkdirs();it.writeText("keep this save")}
    val outside=File(base,"outside.gba").also{it.writeText("keep outside")}
    val orphan=File(root,"roms/orphan.gba").also{it.writeText("keep unindexed content")}
    val db=File(root,"library.json");val array=JSONArray(db.readText());array.put(valid.json());array.put(Game("outside",Machine.GBA,"Outside","../../outside.gba").json());db.writeText(array.toString())
    val reviewed=GameLibrary(root);val report=reviewed.archiveInvalidEntries()
    check(report.getInt("archived")==4&&reviewed.snapshot().single().id==valid.id)
    check(save.readText()=="keep this save"&&outside.readText()=="keep outside"&&orphan.readText()=="keep unindexed content")
    val archive=File(root,"archive/${report.getString("archive")}");check(File(archive,"library-before.json").isFile&&File(archive,empty.name).isFile)
    check(reviewed.archiveInvalidEntries().getInt("archived")==0)
    File(probe.targetContext.filesDir,"library-repair-review.json").writeText(report.put("savePreserved",true).put("outsidePreserved",true).put("orphanPreserved",true).put("idempotent",true).toString(2))
    result.putString("result","PASS: missing, duplicate, empty and unsafe records archived; valid ROM, save, outside and unindexed files retained; second repair changes nothing");probe.finish(-1,result)
}catch(e:Throwable){result.putString("error",e.stackTraceToString());probe.finish(0,result)}}
