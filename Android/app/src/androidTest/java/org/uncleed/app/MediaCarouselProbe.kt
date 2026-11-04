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

fun runMediaCarouselProbe(probe:Instrumentation){val result=Bundle()
 try{
  val a=probe.startActivitySync(Intent(probe.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
  probe.runOnMainSync{a.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)}
  fun state():JSONObject{var s=JSONObject();probe.runOnMainSync{s=a.showcaseDiagnostics()};return s}
  fun waitFor(label:String,p:(JSONObject)->Boolean):JSONObject{val end=SystemClock.uptimeMillis()+45000;do{val s=state();if(p(s))return s;SystemClock.sleep(80)}while(SystemClock.uptimeMillis()<end);error("$label: ${state()}")}
  fun send(action:Int,down:Long,x:Float,y:Float){val e=MotionEvent.obtain(down,SystemClock.uptimeMillis(),action,x,y,0);probe.sendPointerSync(e);e.recycle()}
  fun tapCentre(){val s=state();val x=s.getInt("surfaceX")+s.getInt("surfaceWidth")*.5f;val y=s.getInt("surfaceY")+s.getInt("surfaceHeight")*.5f;val d=SystemClock.uptimeMillis();send(0,d,x,y);SystemClock.sleep(40);send(1,d,x,y)}
  waitFor("home"){it.optBoolean("assetReady")};SystemClock.sleep(400);tapCentre();waitFor("theme"){it.optString("stage")=="THEME"&&it.optBoolean("assetReady")};SystemClock.sleep(400);tapCentre();waitFor("media"){it.optString("stage")=="MEDIA"&&it.optBoolean("assetReady")}
  val games=GameLibrary(probe.targetContext.filesDir).games.filter{it.machine==Machine.GBA};val index=games.indexOfFirst{it.title.contains("Emerald")};check(index in 1 until games.lastIndex);val target=games[index+1]
  val select=MainActivity::class.java.getDeclaredMethod("selectPage",Int::class.javaPrimitiveType).apply{isAccessible=true};probe.runOnMainSync{select.invoke(a,index)}
  val initial=waitFor("Emerald and two covered neighbours"){it.optString("coverGame")==games[index].id&&it.optString("leftCover").isNotEmpty()&&it.optString("rightCover")==target.id&&abs(it.optDouble("presentedOffset"))<1}
  val dir=File(probe.targetContext.filesDir,"media-carousel-qa").also{it.mkdirs()}
  fun capture(name:String){val b=probe.uiAutomation.takeScreenshot()!!;File(dir,name).outputStream().use{b.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};b.recycle()}
  SystemClock.sleep(300);capture("neighbours.png")
  val transition=JSONArray();var sampling=true
  val sampler=object:android.view.Choreographer.FrameCallback{override fun doFrame(time:Long){if(!sampling)return;transition.put(a.showcaseDiagnostics().put("timeNanos",time));android.view.Choreographer.getInstance().postFrameCallback(this)}}
  probe.runOnMainSync{android.view.Choreographer.getInstance().postFrameCallback(sampler)}
  val x=initial.getInt("surfaceX")+initial.getInt("surfaceWidth")*.5f;val y=initial.getInt("surfaceY")+initial.getInt("surfaceHeight")*.5f
  var down=SystemClock.uptimeMillis();send(0,down,x,y);SystemClock.sleep(40);send(2,down,x-70,y)
  repeat(8){i->SystemClock.sleep(65);send(2,down,x-70-(i+1)*28,y);check(!state().optBoolean("inspecting"));if(i==3)capture("drag.png")};send(1,down,x-294,y)
  val advanced=waitFor("one page and original incoming entity"){it.optInt("primaryRoot")==initial.getInt("rightRoot")&&it.optString("coverGame")==target.id&&it.optString("mediaTitle")==target.title&&abs(it.optDouble("presentedOffset"))<1}
  probe.runOnMainSync{transition.put(a.showcaseDiagnostics());sampling=false;android.view.Choreographer.getInstance().removeFrameCallback(sampler)}
  check(advanced.getInt("modelLoads")==initial.getInt("modelLoads")){"Primary model reloaded"}
  check(advanced.optString("leftCover")==games[index].id){"Outgoing cover lost"}
  var lastOld:JSONObject?=null;var firstNew:JSONObject?=null;val positions=mutableSetOf<Int>()
  for(i in 0 until transition.length()){val s=transition.getJSONObject(i);check(s.optDouble("sceneAlpha")>.99);if(s.optInt("primaryRoot")==initial.getInt("primaryRoot")){lastOld=s;positions+=s.optDouble("presentedOffset").toInt()}else if(s.optInt("primaryRoot")==initial.getInt("rightRoot")&&firstNew==null)firstNew=s}
  File(dir,"transition.json").writeText(transition.toString(2))
  File(dir,"partial.json").writeText(JSONObject().put("initial",initial).put("advanced",advanced).put("distinctPositions",positions.size).toString(2))
  check(lastOld!=null&&firstNew!=null&&positions.size>=8){"Missing continuous presented movement (${positions.size}, old=${lastOld!=null}, new=${firstNew!=null})"}
  val jump=abs(lastOld!!.getDouble("rightCenterX")-firstNew!!.getDouble("focusCenterX"));check(jump<4){"Promotion jump $jump px"}
  check(abs(initial.getDouble("halfHeight")-advanced.getDouble("halfHeight"))<.001){"Media resized on promotion"}
  SystemClock.sleep(300);capture("promoted.png")
  probe.runOnMainSync{select.invoke(a,index)};val reversed=waitFor("reverse reuses outgoing entity"){it.optString("coverGame")==games[index].id&&it.optInt("primaryRoot")==initial.getInt("primaryRoot")&&abs(it.optDouble("presentedOffset"))<1}
  down=SystemClock.uptimeMillis();send(0,down,x,y);SystemClock.sleep(260);send(2,down,x+150,y+30);waitFor("media can rotate"){it.optBoolean("presentedInspecting")&&abs(it.optDouble("yaw"))>20};capture("inspection.png");send(1,down,x+150,y+30);waitFor("inspection returns without loading game"){it.optString("stage")=="MEDIA"&&abs(it.optDouble("yaw"))<.5}
  probe.runOnMainSync{for(i in listOf(1,index+1,0,index))select.invoke(a,i)}
  val final=waitFor("rapid final cover and title"){it.optString("coverGame")==games[index].id&&it.optString("mediaTitle")==games[index].title&&abs(it.optDouble("presentedOffset"))<1}
  SystemClock.sleep(300);check(state().getInt("coverTextures")<=3){"Unbounded cover textures"};capture("rapid-final.png")
  File(dir,"transition.json").writeText(transition.toString(2));File(dir,"report.json").writeText(JSONObject().put("initial",initial).put("advanced",advanced).put("reversed",reversed).put("final",final).put("distinctPositions",positions.size).put("promotionJumpPx",jump).toString(2))
  result.putString("result","PASS: covered neighbours, continuous slow swipe, same-entity promotion/reverse, hold rotation, rapid final binding and bounded textures");probe.finish(-1,result)
 }catch(e:Throwable){result.putString("error",e.toString());probe.finish(0,result)}
}
