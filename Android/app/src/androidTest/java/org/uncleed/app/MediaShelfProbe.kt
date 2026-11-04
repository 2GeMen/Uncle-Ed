// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.view.MotionEvent
import java.io.File
import org.json.JSONObject
import kotlin.math.abs

/** Checks other phone media geometries without pretending their emulator cores are ready. */
fun runMediaShelfProbe(probe:Instrumentation,key:String){val result=Bundle()
 try{
  val a=probe.startActivitySync(Intent(probe.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
  probe.runOnMainSync{a.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)}
  fun state():JSONObject{var s=JSONObject();probe.runOnMainSync{s=a.showcaseDiagnostics()};return s}
  fun waitFor(label:String,p:(JSONObject)->Boolean):JSONObject{val end=SystemClock.uptimeMillis()+45000;do{val s=state();if(p(s))return s;SystemClock.sleep(80)}while(SystemClock.uptimeMillis()<end);error("$label: ${state()}")}
  fun send(action:Int,down:Long,x:Float,y:Float){val e=MotionEvent.obtain(down,SystemClock.uptimeMillis(),action,x,y,0);probe.sendPointerSync(e);e.recycle()}
  fun tap(x:Float,y:Float){val d=SystemClock.uptimeMillis();send(0,d,x,y);SystemClock.sleep(40);send(1,d,x,y)}
  fun centre(){val s=state();tap(s.getInt("surfaceX")+s.getInt("surfaceWidth")*.5f,s.getInt("surfaceY")+s.getInt("surfaceHeight")*.5f)}
  val select=MainActivity::class.java.getDeclaredMethod("selectPage",Int::class.javaPrimitiveType).apply{isAccessible=true}
  waitFor("home"){it.optBoolean("assetReady")};val machine=Machine.available(false).indexOfFirst{it.key==key};check(machine>=0)
  probe.runOnMainSync{select.invoke(a,machine)};waitFor("machine"){it.optString("model")==key&&it.optBoolean("assetReady")&&abs(it.optDouble("presentedOffset"))<1};SystemClock.sleep(400);centre()
  waitFor("theme"){it.optString("stage")=="THEME"&&it.optBoolean("assetReady")};SystemClock.sleep(400);centre()
  val games=GameLibrary(probe.targetContext.filesDir).games.filter{it.machine.key==key};check(games.size>=2)
  val initial=waitFor("covered shelf"){it.optString("stage")=="MEDIA"&&it.optString("coverGame")==games[0].id&&it.optString("rightCover")==games[1].id}
  val dir=File(probe.targetContext.filesDir,"media-shelf-qa/$key").also{it.mkdirs()}
  fun capture(name:String){val b=probe.uiAutomation.takeScreenshot()!!;File(dir,name).outputStream().use{b.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};b.recycle()}
  SystemClock.sleep(350);capture("initial.png")
  tap(initial.getInt("surfaceX")+minOf(initial.getDouble("rightCenterX").toFloat(),initial.getInt("surfaceWidth")*.92f),initial.getInt("surfaceY")+initial.getInt("surfaceHeight")*.5f)
  val advanced=waitFor("neighbour tap selects without starting game"){it.optString("stage")=="MEDIA"&&it.optString("coverGame")==games[1].id&&it.optInt("primaryRoot")==initial.getInt("rightRoot")&&abs(it.optDouble("presentedOffset"))<1}
  check(advanced.getInt("modelLoads")==initial.getInt("modelLoads"));SystemClock.sleep(350);capture("advanced.png")
  probe.runOnMainSync{select.invoke(a,0)};waitFor("reverse restores first cover"){it.optString("coverGame")==games[0].id&&it.optInt("primaryRoot")==initial.getInt("primaryRoot")&&abs(it.optDouble("presentedOffset"))<1}
  val x=initial.getInt("surfaceX")+initial.getInt("surfaceWidth")*.5f;val y=initial.getInt("surfaceY")+initial.getInt("surfaceHeight")*.5f;val down=SystemClock.uptimeMillis();send(0,down,x,y);SystemClock.sleep(260);send(2,down,x+180,y+50)
  waitFor("media rotation"){it.optBoolean("presentedInspecting")&&abs(it.optDouble("yaw"))>25};capture("rotated.png");send(1,down,x+180,y+50)
  val final=waitFor("rotation returns in media"){it.optString("stage")=="MEDIA"&&abs(it.optDouble("yaw"))<.5};check(final.getInt("coverTextures")<=3)
  File(dir,"report.json").writeText(JSONObject().put("initial",initial).put("advanced",advanced).put("final",final).put("coreStarted",false).toString(2))
  result.putString("result","PASS: $key covered shelf, neighbour tap/promotion, reverse, rotation, bounded textures; no game core started");probe.finish(-1,result)
 }catch(e:Throwable){result.putString("error",e.toString());probe.finish(0,result)}
}
