// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.view.MotionEvent
import java.io.File
import org.json.JSONObject
import org.json.JSONArray

/** Browses cached artwork and stresses last-selection binding. Network uses persisted consent. */
fun runMediaLocalProbe(probe:Instrumentation){val result=Bundle()
 try{
  val activity=probe.startActivitySync(Intent(probe.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
  probe.runOnMainSync{activity.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)}
  fun state():JSONObject{var s=JSONObject();probe.runOnMainSync{s=activity.showcaseDiagnostics()};return s}
  fun waitFor(label:String,p:(JSONObject)->Boolean):JSONObject {val end=SystemClock.uptimeMillis()+60000;do{val s=state();if(p(s))return s;SystemClock.sleep(150)}while(SystemClock.uptimeMillis()<end);error("$label: ${state()}")}
  fun tapCentre(){val s=state();val x=s.getInt("surfaceX")+s.getInt("surfaceWidth")*.5f;val y=s.getInt("surfaceY")+s.getInt("surfaceHeight")*.5f;val down=SystemClock.uptimeMillis();val a=MotionEvent.obtain(down,down,0,x,y,0);probe.uiAutomation.injectInputEvent(a,false);a.recycle();SystemClock.sleep(40);val b=MotionEvent.obtain(down,down+40,1,x,y,0);probe.uiAutomation.injectInputEvent(b,false);b.recycle()}
  val select=MainActivity::class.java.getDeclaredMethod("selectPage",Int::class.javaPrimitiveType).apply{isAccessible=true}
  waitFor("home"){it.optBoolean("assetReady")};SystemClock.sleep(500);tapCentre();waitFor("theme"){it.optString("stage")=="THEME"&&it.optBoolean("assetReady")};SystemClock.sleep(400);tapCentre();waitFor("media"){it.optString("stage")=="MEDIA"&&it.optBoolean("assetReady")}
  val games=GameLibrary(probe.targetContext.filesDir).games.filter{it.machine==Machine.GBA};val rows=JSONArray();val dir=File(probe.targetContext.filesDir,"media-local-qa").also{it.mkdirs()}
  for(term in listOf("FireRed","Emerald")){
   val index=games.indexOfFirst{it.title.contains(term)};check(index>=0);probe.runOnMainSync{select.invoke(activity,index)}
   val s=waitFor("$term sticker and metadata"){it.optString("coverGame")==games[index].id&&it.optBoolean("coverMatched")&&it.optString("mediaCredits").contains("Nintendo")};SystemClock.sleep(500)
   val bitmap=probe.uiAutomation.takeScreenshot()!!;File(dir,"$term.png").outputStream().use{bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};bitmap.recycle();rows.put(s)
  }
  val target=games.indexOfFirst{it.title.contains("FireRed")};val other=games.indexOfFirst{it.title.contains("Emerald")}
  probe.runOnMainSync{for(index in listOf(target,other,target,other,target))select.invoke(activity,index)}
  rows.put(waitFor("rapid final sticker"){it.optString("coverGame")==games[target].id&&it.optBoolean("coverMatched")&&it.optString("mediaTitle").contains("FireRed")})
  File(dir,"report.json").writeText(rows.toString(2));result.putString("result","PASS: cached GBA art, credits, bounded media size and rapid last-selection sticker binding");probe.finish(-1,result)
 }catch(e:Throwable){result.putString("error",e.toString());probe.finish(0,result)}
}
