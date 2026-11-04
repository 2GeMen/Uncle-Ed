// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.view.MotionEvent
import org.json.JSONObject
import org.json.JSONArray
import java.io.File
import kotlin.math.abs

/** Whole theme-page journey: visible neighbours, continuous drag, identity and no fade. */
fun runThemeCarouselProbe(probe:Instrumentation){val result=Bundle();try{
 val a=probe.startActivitySync(Intent(probe.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)) as MainActivity
 probe.runOnMainSync{a.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)}
 dismissFirstRunFullscreenHint(probe)
 fun state():JSONObject{var s=JSONObject();probe.runOnMainSync{s=a.showcaseDiagnostics()};return s}
 fun waitFor(label:String,p:(JSONObject)->Boolean):JSONObject{val end=SystemClock.uptimeMillis()+60000;do{val s=state();if(p(s))return s;SystemClock.sleep(80)}while(SystemClock.uptimeMillis()<end);error("$label ${state()}")}
 val select=MainActivity::class.java.getDeclaredMethod("selectPage",Int::class.javaPrimitiveType).apply{isAccessible=true}
 val confirm=MainActivity::class.java.getDeclaredMethod("confirm").apply{isAccessible=true}
 val scene=MainActivity::class.java.getDeclaredField("scene").apply{isAccessible=true}.get(a) as MachineSurface
 val dir=File(probe.targetContext.filesDir,"theme-carousel-qa").also{it.mkdirs()};val rows=JSONArray()
 fun capture(name:String){val b=probe.uiAutomation.takeScreenshot()!!;File(dir,name).outputStream().use{b.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};b.recycle()}
 fun send(action:Int,down:Long,x:Float,y:Float){val e=MotionEvent.obtain(down,SystemClock.uptimeMillis(),action,x,y,0);probe.sendPointerSync(e);e.recycle()}
 val virtualDevice=android.os.Build.MODEL.contains("sdk")||android.os.Build.FINGERPRINT.contains("generic")
 fun swipe(s:JSONObject,left:Boolean){
  val x=s.getInt("surfaceX")+s.getInt("surfaceWidth")*.55f;val y=s.getInt("surfaceY")+s.getInt("surfaceHeight")*.5f;val down=SystemClock.uptimeMillis();val dx=(if(left)-1 else 1)*s.getInt("surfaceWidth")*.48f
  if(virtualDevice){
   // Software GPU syncInputTransactions can stall sendPointerSync for seconds,
   // converting the intended short swipe into a real long hold. Exercise the
   // same Activity/View touch path, committing DOWN + first MOVE atomically.
   probe.runOnMainSync{for((action,px,time) in listOf(Triple(0,x,down),Triple(2,x+dx/8,down+1))){val e=MotionEvent.obtain(down,time,action,px,y,0);e.source=android.view.InputDevice.SOURCE_TOUCHSCREEN;a.dispatchTouchEvent(e);e.recycle()}}
   for(i in 2..8){SystemClock.sleep(35);probe.runOnMainSync{val e=MotionEvent.obtain(down,SystemClock.uptimeMillis(),2,x+dx*i/8,y,0);a.dispatchTouchEvent(e);e.recycle()}}
   probe.runOnMainSync{val e=MotionEvent.obtain(down,SystemClock.uptimeMillis(),1,x+dx,y,0);a.dispatchTouchEvent(e);e.recycle()}
  }else{send(0,down,x,y);SystemClock.sleep(25);for(i in 1..8){send(2,down,x+dx*i/8,y);SystemClock.sleep(18)};send(1,down,x+dx,y)}
 }

 waitFor("home"){var focused=false;probe.runOnMainSync{focused=a.hasWindowFocus()};focused&&it.optBoolean("assetReady")}
 for((index,kind) in Machine.available(probe.targetContext.resources.configuration.smallestScreenWidthDp>=600).withIndex()){
  probe.runOnMainSync{select.invoke(a,index)};waitFor("family"){it.optString("stage")=="MACHINE"&&it.optString("model")==kind.key&&!it.optBoolean("carouselSettling")&&it.optBoolean("assetReady")}
  probe.runOnMainSync{confirm.invoke(a)};waitFor("theme"){it.optString("stage")=="THEME"&&it.optBoolean("assetReady")}
  probe.runOnMainSync{select.invoke(a,0)}
  val first=waitFor("first theme neighbours"){it.optInt("theme")==0&&!it.optBoolean("carouselSettling")&&it.optBoolean("assetReady")&&it.optDouble("sceneAlpha")>.99&&it.optInt("readyNeighbours")>=1&&it.optString("rightModel")=="${kind.key}-1"};SystemClock.sleep(300);capture("${kind.key}-0.png")
  val frames=JSONArray();var sampling=true
  val sampler=object:android.view.Choreographer.FrameCallback{override fun doFrame(t:Long){if(sampling){frames.put(a.showcaseDiagnostics());android.view.Choreographer.getInstance().postFrameCallback(this)}}}
  probe.runOnMainSync{android.view.Choreographer.getInstance().postFrameCallback(sampler)};swipe(first,true)
  val next=waitFor("one-theme advance"){it.optInt("theme")==1&&!it.optBoolean("carouselSettling")&&it.optBoolean("assetReady")&&abs(it.optDouble("presentedOffset"))<1&&it.optInt("primaryRoot")==first.optInt("rightRoot")}
  probe.runOnMainSync{sampling=false;android.view.Choreographer.getInstance().removeFrameCallback(sampler)}
  check(next.optString("stage")=="THEME");check(next.optInt("modelLoads")==first.optInt("modelLoads"));check(next.optString("detail")==kind.themes[1])
  val positions=mutableSetOf<Int>();for(i in 0 until frames.length()){val f=frames.getJSONObject(i);check(f.optDouble("sceneAlpha")>.99){"Theme carousel faded"};positions+=f.optDouble("presentedOffset").toInt()};check(positions.size>=4){"No continuous theme slide"}
  File(dir,"${kind.key}-transition.json").writeText(frames.toString(2));capture("${kind.key}-1.png");rows.put(JSONObject().put("machine",kind.key).put("presentedPositions",positions.size).put("sameEntity",true).put("noReload",true).put("inputPath",if(virtualDevice)"Activity/View touch dispatch" else "OS touchscreen injection"))
  for(t in 2..3){probe.runOnMainSync{select.invoke(a,t)};waitFor("theme $t"){it.optInt("theme")==t&&!it.optBoolean("carouselSettling")&&it.optBoolean("assetReady")&&abs(it.optDouble("presentedOffset"))<1};SystemClock.sleep(200);capture("${kind.key}-$t.png")}
  probe.runOnMainSync{select.invoke(a,0)};waitFor("reverse to first"){it.optInt("theme")==0&&!it.optBoolean("carouselSettling")&&it.optBoolean("assetReady")}
  probe.runOnMainSync{scene.inspecting=true;scene.yaw=25f;scene.pitch=10f};SystemClock.sleep(500);capture("${kind.key}-light-angle.png")
  probe.runOnMainSync{scene.yaw=180f;scene.pitch=0f};SystemClock.sleep(500);capture("${kind.key}-rear.png")
  probe.runOnMainSync{scene.inspecting=false;scene.yaw=0f;scene.pitch=0f}
  probe.runOnMainSync{a.onBackPressed()};waitFor("back home"){it.optString("stage")=="MACHINE"&&it.optBoolean("assetReady")}
 }
 File(dir,"report.json").writeText(rows.toString(2));result.putString("result","PASS: all available families, four side-by-side themes, real swipe with presented intermediate frames, same entity/no reload/no fade, reverse and names");probe.finish(-1,result)
 }catch(e:Throwable){result.putString("error",e.toString());probe.finish(0,result)}}
