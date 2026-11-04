// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app

import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.view.MotionEvent
import org.json.JSONObject
import java.io.File
import kotlin.math.abs

/** Actual activity / touch injection. It does not import or execute any game. */
fun runShowcaseProbe(probe:Instrumentation){
    val report=Bundle();var activity:MainActivity?=null
    try {
        activity=probe.startActivitySync(Intent(probe.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        fun state():JSONObject {var result=JSONObject();probe.runOnMainSync{result=activity.showcaseDiagnostics()};return result}
        fun waitFor(label:String,timeout:Long=45000,predicate:(JSONObject)->Boolean):JSONObject {
            val deadline=SystemClock.uptimeMillis()+timeout
            do {val value=state();if(predicate(value))return value;SystemClock.sleep(200)}while(SystemClock.uptimeMillis()<deadline)
            error("Timed out: $label; ${state()}")
        }
        val directory=File(probe.targetContext.filesDir,"showcase-qa").also{it.mkdirs()}
        fun capture(name:String){val bitmap=probe.uiAutomation.takeScreenshot()?:error("Screenshot unavailable");File(directory,name).outputStream().use{bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};bitmap.recycle()}
        val home=waitFor("home model and geometric rim"){it.optBoolean("assetReady")&&it.getJSONObject("rim").optBoolean("loaded")&&it.getJSONObject("rim").optDouble("opacity")>.9}
        check(home.getBoolean("contained"));check(home.getJSONObject("rim").getInt("frameCount")==16);check(home.getJSONObject("rim").getInt("alphaBytes")<=32*1024*1024)
        capture("home.png")
        val x=home.getInt("surfaceX")+home.getInt("surfaceWidth")*.5f;val y=home.getInt("surfaceY")+home.getInt("surfaceHeight")*.5f
        fun send(action:Int,down:Long,px:Float,py:Float,time:Long=SystemClock.uptimeMillis()){val event=MotionEvent.obtain(down,time,action,px,py,0);probe.sendPointerSync(event);event.recycle()}
        var down=SystemClock.uptimeMillis();send(MotionEvent.ACTION_DOWN,down,x,y);SystemClock.sleep(30);send(MotionEvent.ACTION_UP,down,x,y,down+30)
        val theme=waitFor("theme page"){it.optString("stage")=="THEME"&&it.optDouble("sceneAlpha",1.0)>.99&&it.optBoolean("assetReady")&&it.getJSONObject("rim").optBoolean("loaded")&&it.getJSONObject("rim").optDouble("opacity")>.9}
        check(theme.getString("detail")=="原生黄色")
        check(home.getInt("modelLoads")==theme.getInt("modelLoads")){"Same-model transition reloads geometry"}
        check(home.getInt("surfaceWidth")==theme.getInt("surfaceWidth")&&home.getInt("surfaceHeight")==theme.getInt("surfaceHeight")){"Page transition changes viewport"}
        check(abs(home.getDouble("halfHeight")-theme.getDouble("halfHeight"))<.0001){"Page transition changes scale"}
        capture("theme.png")
        down=SystemClock.uptimeMillis();send(MotionEvent.ACTION_DOWN,down,x,y);SystemClock.sleep(260)
        val dx=theme.getInt("surfaceWidth")*.18f;val dy=theme.getInt("surfaceHeight")*.12f
        for(index in 1..12){send(MotionEvent.ACTION_MOVE,down,x+dx*index/12,y+dy*index/12);SystemClock.sleep(35)}
        val rotated=waitFor("rotation hides only rim",10000){it.optBoolean("inspecting")&&it.optBoolean("presentedInspecting")&&abs(it.optDouble("yaw"))>45&&it.getJSONObject("rim").optDouble("opacity")<.001}
        check(rotated.getString("stage")=="THEME"&&rotated.getBoolean("contained"));check(abs(rotated.getDouble("yaw"))>45)
        capture("rotated.png")
        send(MotionEvent.ACTION_UP,down,x+dx,y+dy)
        val returned=waitFor("release returns and restores rim",10000){!it.optBoolean("inspecting")&&abs(it.optDouble("yaw"))<.5&&abs(it.optDouble("pitch"))<.5&&it.getJSONObject("rim").optDouble("opacity")>.8}
        check(returned.getString("stage")=="THEME"&&returned.getBoolean("contained"));capture("returned.png")
        File(directory,"report.json").writeText(JSONObject().put("home",home).put("theme",theme).put("rotated",rotated).put("returned",returned).put("visualAcceptance",false).toString(2))
        report.putString("result","PASS: real page transition, equal scale, projected containment, physical silhouette mask, hold/rotate/release; visual review still required")
        probe.finish(-1,report)
    }catch(e:Throwable){report.putString("error",e.toString());probe.finish(0,report)}
}
