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
import kotlin.math.abs

/** Actual installed library, caption gestures only; never confirms or starts a game. */
fun runCaptionShelfReview(probe:Instrumentation){
 val result=Bundle();var activity:MainActivity?=null
 try{
  val a=probe.startActivitySync(Intent(probe.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)) as MainActivity;activity=a
  probe.runOnMainSync{a.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)};dismissFirstRunFullscreenHint(probe)
  fun state():JSONObject{var s=JSONObject();probe.runOnMainSync{s=a.showcaseDiagnostics()};return s}
  fun waitFor(label:String,p:(JSONObject)->Boolean){val end=SystemClock.uptimeMillis()+60000;do{if(p(state()))return;SystemClock.sleep(100)}while(SystemClock.uptimeMillis()<end);error("$label ${state()}")}
  val select=MainActivity::class.java.getDeclaredMethod("selectPage",Int::class.javaPrimitiveType).apply{isAccessible=true};val confirm=MainActivity::class.java.getDeclaredMethod("confirm").apply{isAccessible=true}
  val library=GameLibrary(probe.targetContext.filesDir);val dir=File(probe.targetContext.filesDir,"caption-shelf-qa").also{it.mkdirs()};val rows=JSONArray()
  fun event(action:Int,down:Long,x:Float,y:Float){val e=MotionEvent.obtain(down,SystemClock.uptimeMillis(),action,x,y,0);probe.sendPointerSync(e);e.recycle()}
  fun caption(id:String):Pair<Float,Float>{waitFor("caption ready"){s->val labels=s.getJSONArray("mediaLabels");(0 until labels.length()).any{labels.getJSONObject(it).getString("id")==id}};val s=state();val labels=s.getJSONArray("mediaLabels");val row=(0 until labels.length()).map{labels.getJSONObject(it)}.first{it.getString("id")==id};return row.getDouble("x").toFloat()+s.getInt("surfaceX") to row.getDouble("bottom").toFloat()+s.getInt("surfaceY")+15*probe.targetContext.resources.displayMetrics.density}
  waitFor("home"){it.optBoolean("assetReady")}
  for((index,kind) in Machine.available(DeviceProfile.isTablet(a)).withIndex()){
   val games=library.snapshot().filter{it.machine==kind};if(games.size<2)continue
   probe.runOnMainSync{select.invoke(a,index)};waitFor("family"){it.optString("model")==kind.key&&it.optBoolean("assetReady")&&!it.optBoolean("carouselSettling")}
   probe.runOnMainSync{confirm.invoke(a)};waitFor("theme"){it.optString("stage")=="THEME"&&it.optBoolean("assetReady")};probe.runOnMainSync{confirm.invoke(a)}
   waitFor("shelf"){it.optString("stage")=="MEDIA"&&it.optString("coverGame")==games[0].id}
   val neighbour=caption(games[1].id);val down=SystemClock.uptimeMillis();event(0,down,neighbour.first,neighbour.second);SystemClock.sleep(55);event(1,down,neighbour.first,neighbour.second)
   waitFor("caption selects neighbour"){it.optString("stage")=="MEDIA"&&it.optString("coverGame")==games[1].id&&!it.optBoolean("carouselSettling")}
   val centre=caption(games[1].id);val hold=SystemClock.uptimeMillis();event(0,hold,centre.first,centre.second);waitFor("hold"){it.optBoolean("presentedInspecting")};event(2,hold,centre.first-100,centre.second-15);SystemClock.sleep(180);event(1,hold,centre.first-100,centre.second-15)
   waitFor("returns"){it.optString("stage")=="MEDIA"&&abs(it.optDouble("yaw"))<.5}
   val p=caption(games[1].id);val swipe=SystemClock.uptimeMillis();val distance=90*probe.targetContext.resources.displayMetrics.density;event(0,swipe,p.first,p.second);SystemClock.sleep(30);event(2,swipe,p.first+distance,p.second);SystemClock.sleep(30);event(1,swipe,p.first+distance,p.second)
   waitFor("swipe previous"){it.optString("coverGame")==games[0].id&&!it.optBoolean("carouselSettling")}
   check(state().getString("stage")=="MEDIA");val b=probe.uiAutomation.takeScreenshot()!!;File(dir,"${kind.key}.png").outputStream().use{b.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};b.recycle()
   rows.put(JSONObject().put("machine",kind.key).put("neighbourCaption",true).put("holdRotate",true).put("swipe",true).put("coreStarted",false));File(dir,"report.json").writeText(rows.toString(2))
   probe.runOnMainSync{a.onBackPressed();a.onBackPressed()};waitFor("home restored"){it.optString("stage")=="MACHINE"&&it.optBoolean("assetReady")}
  }
  check(rows.length()>0){"No actual library with neighbours"};result.putString("result","PASS: actual-library caption neighbour selection, hold rotation and swipe; no core or save used")
 }catch(e:Throwable){result.putString("error",e.stackTraceToString())}
 finally{activity?.let{a->probe.runOnMainSync{a.finish()}}}
 probe.finish(if(result.containsKey("error"))0 else -1,result)
}
