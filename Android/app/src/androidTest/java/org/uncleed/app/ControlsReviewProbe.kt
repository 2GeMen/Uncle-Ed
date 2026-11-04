// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app

import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.view.MotionEvent
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Physical hit/animation/haptic path without sending arbitrary inputs to a user's save. */
fun runControlsReview(probe:Instrumentation){val result=Bundle();try{
    val a=probe.startActivitySync(Intent(probe.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)) as MainActivity
    probe.runOnMainSync{a.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)}
    dismissFirstRunFullscreenHint(probe)
    fun state():JSONObject{var s=JSONObject();probe.runOnMainSync{s=a.showcaseDiagnostics()};return s}
    fun waitFor(label:String,p:(JSONObject)->Boolean){val end=SystemClock.uptimeMillis()+60000;do{if(p(state()))return;SystemClock.sleep(100)}while(SystemClock.uptimeMillis()<end);error("$label ${state()}")}
    val select=MainActivity::class.java.getDeclaredMethod("selectPage",Int::class.javaPrimitiveType).apply{isAccessible=true}
    val confirm=MainActivity::class.java.getDeclaredMethod("confirm").apply{isAccessible=true}
    val refresh=MainActivity::class.java.getDeclaredMethod("refresh").apply{isAccessible=true}
    val field=MainActivity::class.java.getDeclaredField("scene").apply{isAccessible=true};val scene=field.get(a) as MachineSurface
    val shown=MainActivity::class.java.getDeclaredField("shownModel").apply{isAccessible=true}
    val stage=MainActivity::class.java.getDeclaredField("stage").apply{isAccessible=true};fun stage(name:String)=stage.type.enumConstants.first{(it as Enum<*>).name==name}
    val dir=File(probe.targetContext.filesDir,"parity-review/controls").also{it.mkdirs()};val rows=JSONArray()
    fun capture(name:String){val b=probe.uiAutomation.takeScreenshot()!!;File(dir,name).outputStream().use{b.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};b.recycle()}
    waitFor("home"){it.optBoolean("assetReady")}
    for((index,kind) in Machine.available(probe.targetContext.resources.configuration.smallestScreenWidthDp>=600).withIndex()){
        probe.runOnMainSync{select.invoke(a,index)};waitFor("family"){it.optString("model")==kind.key&&it.optBoolean("assetReady")&&!it.optBoolean("carouselSettling")}
        probe.runOnMainSync{confirm.invoke(a)};waitFor("theme"){it.optString("stage")=="THEME"&&it.optBoolean("assetReady")}
        val open=if(kind==Machine.NDS||kind==Machine.N3DS)probe.targetContext.assets.open("models/${kind.key}-open-0.glb").use{it.readBytes()}else null
        probe.runOnMainSync{stage.set(a,stage("PLAYING"));refresh.invoke(a);if(open!=null){val buffer=java.nio.ByteBuffer.allocateDirect(open.size).apply{put(open);flip()};scene.show(buffer,kind,"")};scene.playing=true}
        waitFor("operating model"){it.optBoolean("assetReady")}
        SystemClock.sleep(500)
        var names=emptyList<String>();probe.runOnMainSync{val asset=scene.viewer.asset!!;names=asset.entities.map{asset.getName(it)}.filterNotNull().filter{it.startsWith("key:")||it.startsWith("physical-shoulder:")||it=="dpad"||it=="stick"||it.startsWith("utility:")||it=="psp-power-switch"}.distinct()}
        for(name in names){
            var point=Pair(0f,0f);var before=FloatArray(16);var after=FloatArray(16)
            fun pose():FloatArray{val asset=scene.viewer.asset!!;val e=asset.entities.first{asset.getName(it)==name};val tm=scene.viewer.engine.transformManager;return FloatArray(16).also{tm.getTransform(tm.getInstance(e),it)}}
            probe.runOnMainSync{point=project(scene,name);if(name=="dpad"||name=="stick")point=Pair(point.first+35*scene.resources.displayMetrics.density,point.second);before=pose();check(scene.controlAt(point.first,point.second)?.first==name){"Hit mismatch $name -> ${scene.controlAt(point.first,point.second)}"}}
            val loc=IntArray(2);probe.runOnMainSync{scene.getLocationOnScreen(loc)};val down=SystemClock.uptimeMillis()
            val e=MotionEvent.obtain(down,down,0,point.first+loc[0],point.second+loc[1],0);probe.sendPointerSync(e);e.recycle();SystemClock.sleep(180)
            probe.runOnMainSync{after=pose()};check(before.indices.any{kotlin.math.abs(before[it]-after[it])>.00001f}){"No 3D travel $name"}
            if(name.startsWith("physical-shoulder:")||name=="key:8"||name=="stick")capture("${kind.key}-${name.replace(':','-')}-pressed.png")
            val u=MotionEvent.obtain(down,SystemClock.uptimeMillis(),if(name=="utility:0"||name=="psp-power-switch")3 else 1,point.first+loc[0],point.second+loc[1],0);probe.sendPointerSync(u);u.recycle();SystemClock.sleep(200)
            check(scene.held.isEmpty()){"Stuck key $name"}
            rows.put(JSONObject().put("machine",kind.key).put("control",name).put("travel",true).put("released",true).put("haptics",state().getJSONObject("haptics")))
            File(dir,"partial.json").writeText(rows.toString(2))
        }
        probe.runOnMainSync{scene.playing=false;shown.set(a,null);stage.set(a,stage("MACHINE"));refresh.invoke(a)};waitFor("home restored"){it.optString("stage")=="MACHINE"&&it.optBoolean("assetReady")}
    }
    File(dir,"report.json").writeText(rows.toString(2));result.putString("result","PASS: projected physical controls, 3D travel/release and haptic requests; no core/game/save involved");probe.finish(-1,result)
}catch(e:Throwable){result.putString("error",e.stackTraceToString());probe.finish(0,result)}}
