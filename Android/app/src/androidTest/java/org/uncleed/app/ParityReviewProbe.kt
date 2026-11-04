// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app

import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.view.MotionEvent
import com.google.android.filament.Box
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

fun runLibraryMaintenance(probe:Instrumentation){val result=Bundle();try{
    val library=GameLibrary(probe.targetContext.filesDir)
    val report=library.archiveInvalidEntries(true)
    report.put("remainingFiles",JSONArray(library.snapshot().map{g->JSONObject().put("id",g.id).put("title",g.title).put("bytes",library.file(g).length()).put("present",library.file(g).isFile)}))
    File(probe.targetContext.filesDir,"library-maintenance.json").writeText(report.toString(2))
    result.putString("result","PASS: library audit and recoverable archive; ${report.optInt("archived")} entries archived; saves untouched");probe.finish(-1,result)
}catch(e:Throwable){result.putString("error",e.stackTraceToString());probe.finish(0,result)}}

/** Product UI evidence; generated solid RGB checks use no game or commercial image. */
fun runParityReview(probe:Instrumentation,mode:String){val result=Bundle();try{
    val a=probe.startActivitySync(Intent(probe.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)) as MainActivity
    probe.runOnMainSync{a.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)}
    dismissFirstRunFullscreenHint(probe)
    fun state():JSONObject{var s=JSONObject();probe.runOnMainSync{s=a.showcaseDiagnostics()};return s}
    fun waitFor(label:String,p:(JSONObject)->Boolean){val end=SystemClock.uptimeMillis()+90000;do{if(p(state()))return;SystemClock.sleep(120)}while(SystemClock.uptimeMillis()<end);error("$label ${state()}")}
    val select=MainActivity::class.java.getDeclaredMethod("selectPage",Int::class.javaPrimitiveType).apply{isAccessible=true}
    val confirm=MainActivity::class.java.getDeclaredMethod("confirm").apply{isAccessible=true}
    val field=MainActivity::class.java.getDeclaredField("scene").apply{isAccessible=true};val scene=field.get(a) as MachineSurface
    val dir=File(probe.targetContext.filesDir,"parity-review/$mode").also{it.mkdirs()};val rows=JSONArray()
    fun capture(name:String){probe.waitForIdleSync();SystemClock.sleep(400);val b=probe.uiAutomation.takeScreenshot()!!;File(dir,name).outputStream().use{b.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};b.recycle()}
    waitFor("home"){it.optBoolean("assetReady")}
    val kinds=Machine.available(probe.targetContext.resources.configuration.smallestScreenWidthDp>=600)
    for(kind in if(mode=="colors"){if(kinds.size==5)kinds else listOf(Machine.GBA)}else kinds){
        probe.runOnMainSync{select.invoke(a,kinds.indexOf(kind))};waitFor("family"){it.optString("model")==kind.key&&it.optBoolean("assetReady")&&!it.optBoolean("carouselSettling")}
        probe.runOnMainSync{confirm.invoke(a)};waitFor("theme"){it.optString("stage")=="THEME"&&it.optBoolean("assetReady")}
        if(mode=="shelf"){
            probe.runOnMainSync{confirm.invoke(a)};waitFor("media"){it.optString("stage")=="MEDIA"&&it.optBoolean("assetReady")&&it.optBoolean("coverMatched")};SystemClock.sleep(700)
            capture("${kind.key}-shelf.png");rows.put(state())
            if(GameLibrary(probe.targetContext.filesDir).snapshot().count{it.machine==kind}>1){probe.runOnMainSync{select.invoke(a,1)};waitFor("second"){!it.optBoolean("carouselSettling")&&kotlin.math.abs(it.optDouble("presentedOffset"))<1&&it.optBoolean("coverMatched")};capture("${kind.key}-second.png");rows.put(state())}
            probe.runOnMainSync{a.onBackPressed()};waitFor("back theme"){it.optString("stage")=="THEME"&&it.optBoolean("assetReady")}
        }else{
            probe.runOnMainSync{select.invoke(a,0)};waitFor("first theme"){it.optString("shownModel")=="${kind.key}-0"&&!it.optBoolean("busy")&&it.optBoolean("assetReady")}
            val open=if(kind==Machine.NDS||kind==Machine.N3DS)probe.targetContext.assets.open("models/${kind.key}-open-0.glb").use{it.readBytes()}else null
            probe.runOnMainSync{if(open!=null){val buffer=java.nio.ByteBuffer.allocateDirect(open.size).apply{put(open);flip()};scene.show(buffer,kind,"")};scene.playing=true;scene.clearNeighbours();scene.yaw=0f;scene.pitch=0f}
            waitFor("screen model"){it.optBoolean("assetReady")}
            for(rgb in listOf(0,32,64,96,128,160,192,224,255).map{it*0x010101}+listOf(0xff0000,0x00ff00,0x0000ff,0x804020,0x20a0c0)){
                val expected=listOf(rgb shr 16 and 255,rgb shr 8 and 255,rgb and 255)
                val names=if(kind==Machine.NDS||kind==Machine.N3DS)listOf("screen:0","screen:1")else listOf("screen:0")
                probe.runOnMainSync{scene.diagnosticScreenRgb=rgb}
                val started=SystemClock.uptimeMillis();var bitmap:android.graphics.Bitmap?=null;var samples=emptyList<List<Int>>()
                var matched=false
                while(SystemClock.uptimeMillis()-started<10000){
                    SystemClock.sleep(160);val points=mutableListOf<Pair<Float,Float>>();val loc=IntArray(2)
                    probe.runOnMainSync{names.forEach{points+=project(scene,it)};scene.getLocationOnScreen(loc)}
                    bitmap?.recycle();bitmap=probe.uiAutomation.takeScreenshot()!!
                    samples=points.map{point->val pixel=bitmap!!.getPixel((point.first+loc[0]).toInt(),(point.second+loc[1]).toInt());listOf(android.graphics.Color.red(pixel),android.graphics.Color.green(pixel),android.graphics.Color.blue(pixel))}
                    matched=samples.all{actual->expected.zip(actual).all{kotlin.math.abs(it.first-it.second)<=2}}
                    if(matched)break
                }
                samples.forEachIndexed{i,actual->rows.put(JSONObject().put("machine",kind.key).put("screen",names[i]).put("input",JSONArray(expected)).put("output",JSONArray(actual)).put("settledMs",SystemClock.uptimeMillis()-started))}
                File(dir,"report.json").writeText(rows.toString(2));check(matched){"LCD color mismatch $expected -> $samples"}
                if(rgb==0x808080)File(dir,"${kind.key}-gray128.png").outputStream().use{bitmap!!.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};bitmap?.recycle()
            }
            probe.runOnMainSync{scene.diagnosticScreenRgb=null;scene.playing=false;MainActivity::class.java.getDeclaredField("shownModel").apply{isAccessible=true}.set(a,null)}
        }
        probe.runOnMainSync{a.onBackPressed()};waitFor("home again"){it.optString("stage")=="MACHINE"&&it.optBoolean("assetReady")}
    }
    File(dir,"report.json").writeText(rows.toString(2));result.putString("result","PASS: $mode UI captures generated; inspect measured pixels and screenshots");probe.finish(-1,result)
}catch(e:Throwable){result.putString("error",e.stackTraceToString());probe.finish(0,result)}}

internal fun project(scene:MachineSurface,name:String):Pair<Float,Float>{
    val asset=scene.viewer.asset!!;val e=asset.entities.first{asset.getName(it)==name};val tm=scene.viewer.engine.transformManager;val w=FloatArray(16);tm.getWorldTransform(tm.getInstance(e),w)
    val rm=scene.viewer.engine.renderableManager;val i=rm.getInstance(e);val c=if(i!=0)rm.getAxisAlignedBoundingBox(i,Box()).center else floatArrayOf(0f,0f,0f)
    val pv=FloatArray(16);android.opengl.Matrix.multiplyMM(pv,0,scene.viewer.camera.getProjectionMatrix(DoubleArray(16)).map{it.toFloat()}.toFloatArray(),0,scene.viewer.camera.getViewMatrix(FloatArray(16)),0)
    val world=FloatArray(4);val clip=FloatArray(4);android.opengl.Matrix.multiplyMV(world,0,w,0,floatArrayOf(c[0],c[1],c[2],1f),0);android.opengl.Matrix.multiplyMV(clip,0,pv,0,world,0)
    return Pair((clip[0]/clip[3]+1)*scene.width/2,(1-clip[1]/clip[3])*scene.height/2)
}
