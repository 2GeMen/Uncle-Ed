// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.view.MotionEvent
import java.io.File
import org.json.JSONObject

fun runHomeGestureProbe(probe:Instrumentation){val result=Bundle()
 try{
  val a=probe.startActivitySync(Intent(probe.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
  probe.runOnMainSync{a.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)}
  fun state():JSONObject{var s=JSONObject();probe.runOnMainSync{s=a.showcaseDiagnostics()};return s}
  fun waitFor(label:String,p:(JSONObject)->Boolean):JSONObject{val end=SystemClock.uptimeMillis()+30000;do{val s=state();if(p(s))return s;SystemClock.sleep(100)}while(SystemClock.uptimeMillis()<end);error("$label: ${state()}")}
  fun send(action:Int,down:Long,x:Float,y:Float){val e=MotionEvent.obtain(down,SystemClock.uptimeMillis(),action,x,y,0);probe.sendPointerSync(e);e.recycle()}
  val initial=waitFor("GBA"){it.optBoolean("assetReady")&&it.optString("model")=="gba"&&it.optInt("readyNeighbours")>=1};val x=initial.getInt("surfaceX")+initial.getInt("surfaceWidth")*.6f;val y=initial.getInt("surfaceY")+initial.getInt("surfaceHeight")*.5f
  val dir=File(probe.targetContext.filesDir,"home-gesture-qa").also{it.mkdirs()}
  fun capture(name:String){val bitmap=probe.uiAutomation.takeScreenshot()!!;File(dir,name).outputStream().use{bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};bitmap.recycle()}
  SystemClock.sleep(400);capture("home-neighbours.png")
  val transition=org.json.JSONArray();var sampling=true
  val sampler=object:android.view.Choreographer.FrameCallback{override fun doFrame(time:Long){if(!sampling)return;transition.put(a.showcaseDiagnostics().put("timeNanos",time));android.view.Choreographer.getInstance().postFrameCallback(this)}}
  probe.runOnMainSync{android.view.Choreographer.getInstance().postFrameCallback(sampler)}
  var down=SystemClock.uptimeMillis();send(0,down,x,y);SystemClock.sleep(40);send(2,down,x-70,y)
  for(i in 1..8){SystemClock.sleep(65);send(2,down,x-70-i*28,y);if(i==4){check(state().optDouble("carouselOffset")< -100);capture("drag-neighbours.png")};check(!state().optBoolean("inspecting")){"Committed slow swipe became rotation"}}
  send(1,down,x-294,y)
  val swiped=waitFor("one slow swipe selects GBC"){it.optString("model")=="gbc"&&it.optBoolean("assetReady")&&it.optInt("readyNeighbours")==2};check(swiped.getString("stage")=="MACHINE")
  probe.runOnMainSync{sampling=false;android.view.Choreographer.getInstance().removeFrameCallback(sampler)}
  check(swiped.getInt("modelLoads")==initial.getInt("modelLoads")){"Swipe reloaded the primary GLB"}
  check(swiped.getInt("primaryRoot")==initial.getInt("rightRoot")){"Incoming entity was recreated instead of promoted"}
  var oldLast:JSONObject?=null;var firstNew:JSONObject?=null;var intermediate=0;val distinctOffsets=mutableSetOf<Int>()
  for(i in 0 until transition.length()){val frame=transition.getJSONObject(i);check(frame.getDouble("sceneAlpha")>.99){"Carousel faded instead of sliding"};if(frame.optString("model")=="gba"){oldLast=frame;if(kotlin.math.abs(frame.optDouble("presentedOffset"))>20)intermediate++;distinctOffsets.add(kotlin.math.round(frame.optDouble("presentedOffset")).toInt())}else if(frame.optString("model")=="gbc"&&firstNew==null)firstNew=frame}
  check(distinctOffsets.size>=8){"Presented motion has too few distinct positions"}
  check(intermediate>=4){"Too few presented intermediate positions"}
  check(oldLast!=null&&firstNew!=null){"Missing promotion boundary"}
  val boundaryJump=kotlin.math.abs(oldLast!!.getDouble("rightCenterX")-firstNew!!.getDouble("focusCenterX"))
  check(boundaryJump<4){"Promotion moved the displayed centre by $boundaryJump px"}
  File(dir,"transition.json").writeText(transition.toString(2))
  check(kotlin.math.abs(oldLast!!.getDouble("rightRootScale")/oldLast!!.getDouble("halfHeight")-firstNew!!.getDouble("primaryRootScale")/firstNew!!.getDouble("halfHeight"))<.03){"Promotion changed the incoming model screen scale"}
  File(dir,"transition.json").writeText(transition.toString(2))
  SystemClock.sleep(400);capture("gbc-neighbours.png")
  val sceneField=MainActivity::class.java.getDeclaredField("scene").apply{isAccessible=true};val scene=sceneField.get(a) as MachineSurface
  var neighbourHit:Int?=null;probe.runOnMainSync{neighbourHit=scene.previewPageAt(scene.width-180f,scene.height*.5f)};check(neighbourHit==1){"Right neighbour hit does not select right page"}
  val nx=swiped.getInt("surfaceX")+swiped.getInt("surfaceWidth")-180f;val ny=swiped.getInt("surfaceY")+swiped.getInt("surfaceHeight")*.5f
  down=SystemClock.uptimeMillis()
  send(0,down,nx,ny);SystemClock.sleep(40);send(1,down,nx,ny)
  waitFor("neighbour tap selects PSP"){it.optString("model")=="psp"&&it.optBoolean("assetReady")&&it.optString("stage")=="MACHINE"}
  val select=MainActivity::class.java.getDeclaredMethod("selectPage",Int::class.javaPrimitiveType).apply{isAccessible=true}
  probe.runOnMainSync{for(index in listOf(0,2,0,2,1))select.invoke(a,index)}
  waitFor("last rapid selection wins"){it.optString("model")=="gbc"&&it.optBoolean("assetReady")&&it.optInt("readyNeighbours")==2}
  SystemClock.sleep(300);val before=state().getInt("presentedFrames");val sampleStart=SystemClock.elapsedRealtime();SystemClock.sleep(2000);val sampleMs=SystemClock.elapsedRealtime()-sampleStart;val presentedDelta=state().getInt("presentedFrames")-before
  capture("rapid-final.png")
  val cx=swiped.getInt("surfaceX")+swiped.getInt("surfaceWidth")*.5f;val cy=swiped.getInt("surfaceY")+swiped.getInt("surfaceHeight")*.5f
  down=SystemClock.uptimeMillis();send(0,down,cx,cy);SystemClock.sleep(320);check(state().getBoolean("inspecting")){"Stationary hold did not start inspection"};send(1,down,cx,cy);SystemClock.sleep(350);check(state().getString("stage")=="MACHINE"){"Hold release confirmed machine"}
  down=SystemClock.uptimeMillis();send(0,down,cx,cy);SystemClock.sleep(280);send(2,down,cx+220,cy+80);waitFor("hold drag"){it.optBoolean("presentedInspecting")&&kotlin.math.abs(it.optDouble("yaw"))>35};send(1,down,cx+220,cy+80)
  val returned=waitFor("return"){!it.optBoolean("inspecting")&&kotlin.math.abs(it.optDouble("yaw"))<.5};check(returned.getString("stage")=="MACHINE")
  down=SystemClock.uptimeMillis();send(0,down,cx,cy);SystemClock.sleep(40);send(1,down,cx,cy);val theme=waitFor("short tap confirms"){it.optString("stage")=="THEME"&&it.optBoolean("assetReady")}
  SystemClock.sleep(400)
  val icon=probe.targetContext.packageManager.getApplicationIcon(probe.targetContext.packageName);check(icon is android.graphics.drawable.AdaptiveIconDrawable){"Launcher still uses legacy icon"}
  val iconBitmap=android.graphics.Bitmap.createBitmap(256,256,android.graphics.Bitmap.Config.ARGB_8888);icon.setBounds(0,0,256,256);icon.draw(android.graphics.Canvas(iconBitmap));File(dir,"icon.png").outputStream().use{iconBitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};iconBitmap.recycle()
  val bitmap=probe.uiAutomation.takeScreenshot()!!;File(dir,"theme.png").outputStream().use{bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};bitmap.recycle()
  File(dir,"report.json").writeText(JSONObject().put("initial",initial).put("incomingEntity",initial.getInt("rightRoot")).put("promotedEntity",swiped.getInt("primaryRoot")).put("distinctIntermediateOffsets",distinctOffsets.size).put("promotionBoundaryJumpPx",boundaryJump).put("presentedIntermediateFrames",intermediate).put("presentedDelta",presentedDelta).put("sampleMs",sampleMs).put("presentedFps",presentedDelta*1000.0/sampleMs).put("slowSwipe",swiped).put("returned",returned).put("theme",theme).toString(2))
  result.putString("result","PASS: slow swipe stays swipe and advances one machine; stationary hold starts inspection without confirming; hold-drag returns; short tap confirms; neighbour tap and rapid target selection passed");probe.finish(-1,result)
 }catch(e:Throwable){result.putString("error",e.toString());probe.finish(0,result)}
}
