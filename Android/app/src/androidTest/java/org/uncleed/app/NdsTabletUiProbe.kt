// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.opengl.Matrix
import com.google.android.filament.Box
import java.io.File
import org.json.JSONObject
import kotlin.math.abs

var ndsBookReview=false
fun runNdsTabletUiProbe(probe:Instrumentation){val result=Bundle()
 try{
  check(probe.targetContext.resources.configuration.smallestScreenWidthDp>=600)
  val fixture=File(probe.targetContext.cacheDir,"core-probe/original-nds.nds");check(fixture.isFile)
  val library=GameLibrary(probe.targetContext.filesDir);library.import(fixture.inputStream(),"Original Dual Screen Probe.nds");val game=library.games.first{it.originalName=="Original Dual Screen Probe.nds"}
  probe.targetContext.getSharedPreferences("resource-network-consent",0).edit().putBoolean("approved-v1",false).commit()
  val a=probe.startActivitySync(Intent(probe.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
  probe.runOnMainSync{a.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)}
  dismissFirstRunFullscreenHint(probe)
  fun state():JSONObject{var s=JSONObject();probe.runOnMainSync{s=a.showcaseDiagnostics()};return s}
  fun waitFor(label:String,p:(JSONObject)->Boolean){val end=SystemClock.uptimeMillis()+90000;do{if(p(state()))return;SystemClock.sleep(150)}while(SystemClock.uptimeMillis()<end);error("$label: ${state()}")}
  val select=MainActivity::class.java.getDeclaredMethod("selectPage",Int::class.javaPrimitiveType).apply{isAccessible=true};val confirm=MainActivity::class.java.getDeclaredMethod("confirm").apply{isAccessible=true}
  waitFor("home"){it.optBoolean("assetReady")};SystemClock.sleep(400);probe.runOnMainSync{confirm.invoke(a)};waitFor("theme"){it.optString("stage")=="THEME"&&it.optBoolean("assetReady")};SystemClock.sleep(400);probe.runOnMainSync{confirm.invoke(a)}
  waitFor("media"){it.optString("stage")=="MEDIA"&&it.optBoolean("assetReady")};val index=library.games.filter{it.machine==Machine.NDS}.indexOfFirst{it.id==game.id};probe.runOnMainSync{select.invoke(a,index)}
  waitFor("selected"){it.optString("coverGame")==game.id&&abs(it.optDouble("presentedOffset"))<1};probe.runOnMainSync{confirm.invoke(a)};waitFor("DS playing"){it.optString("stage")=="PLAYING"};SystemClock.sleep(1200)
  val field=MainActivity::class.java.getDeclaredField("scene").apply{isAccessible=true};val scene=field.get(a) as MachineSurface;var mapped:Pair<Float,Float>?=null
  probe.runOnMainSync{
   val asset=scene.viewer.asset!!;val e=asset.entities.first{asset.getName(it)=="screen:1"};val rm=scene.viewer.engine.renderableManager;val c=rm.getAxisAlignedBoundingBox(rm.getInstance(e),Box()).center
   val world=FloatArray(16);val tm=scene.viewer.engine.transformManager;tm.getWorldTransform(tm.getInstance(e),world)
   val projection=scene.viewer.camera.getProjectionMatrix(DoubleArray(16)).map{it.toFloat()}.toFloatArray();val pv=FloatArray(16);Matrix.multiplyMM(pv,0,projection,0,scene.viewer.camera.getViewMatrix(FloatArray(16)),0)
   val point=FloatArray(4);val clip=FloatArray(4);Matrix.multiplyMV(point,0,world,0,floatArrayOf(c[0],c[1],c[2],1f),0);Matrix.multiplyMV(clip,0,pv,0,point,0)
   mapped=scene.touchAt((clip[0]/clip[3]+1)*scene.width/2,(1-clip[1]/clip[3])*scene.height/2)
  }
  check(mapped!=null&&abs(mapped!!.first)<.02&&abs(mapped!!.second-.5f)<.02){"Lower-screen centre mapped to $mapped"}
  val dir=File(probe.targetContext.filesDir,"nds-tablet-ui-qa").also{it.mkdirs()};val b=probe.uiAutomation.takeScreenshot()!!;File(dir,"playing.png").outputStream().use{b.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};b.recycle();File(dir,"report.json").writeText(state().put("touchX",mapped!!.first).put("touchY",mapped!!.second).put("commercialGame",false).toString(2))
  if(ndsBookReview){
   fun button(view:android.view.View,text:String):android.widget.Button?{if(view is android.widget.Button&&view.text.toString()==text)return view;if(view is android.view.ViewGroup)for(i in 0 until view.childCount){button(view.getChildAt(i),text)?.let{return it}};return null}
   val menu=MainActivity::class.java.getDeclaredMethod("showGameMenu").apply{isAccessible=true}
   fun toggle(label:String){probe.runOnMainSync{menu.invoke(a);val target=checkNotNull(button(a.window.decorView,label)){"Missing NDS book action"};target.performClick()}}
   toggle("切换书本握法")
   waitFor("book orientation"){abs(it.optDouble("presentedBookAngle")-90)<.01&&!it.optBoolean("bookTransitioning")};SystemClock.sleep(250)
   probe.runOnMainSync{
    val centre=project(scene,"screen:1");val m=scene.touchAt(centre.first,centre.second);check(m!=null&&abs(m.first)<.02&&abs(m.second-.5f)<.02){"Book LCD centre $m"}
    val asset=scene.viewer.asset!!;val e=asset.entities.first{asset.getName(it)=="screen:1"};val rm=scene.viewer.engine.renderableManager;val box=rm.getAxisAlignedBoundingBox(rm.getInstance(e),Box());val c=box.center;val h=box.halfExtent
    val world=FloatArray(16);val tm=scene.viewer.engine.transformManager;tm.getWorldTransform(tm.getInstance(e),world)
    val pv=FloatArray(16);Matrix.multiplyMM(pv,0,scene.viewer.camera.getProjectionMatrix(DoubleArray(16)).map{it.toFloat()}.toFloatArray(),0,scene.viewer.camera.getViewMatrix(FloatArray(16)),0)
    for(sign in listOf(-1f,1f)){val point=FloatArray(4);val clip=FloatArray(4);Matrix.multiplyMV(point,0,world,0,floatArrayOf(c[0]+h[0]*.6f*sign,c[1]-h[1]*.6f*sign,c[2],1f),0);Matrix.multiplyMV(clip,0,pv,0,point,0);val mapped=scene.touchAt((clip[0]/clip[3]+1)*scene.width/2,(1-clip[1]/clip[3])*scene.height/2);check(mapped!=null&&abs(mapped.first-.6f*sign)<.02f&&abs(mapped.second-(.5f+.3f*sign))<.02f){"Book corner mapped $mapped"}}
    val pad=project(scene,"dpad");val x=pad.first;val y=pad.second-30*scene.resources.displayMetrics.density;val hit=scene.controlAt(x,y);check(hit?.first=="dpad"&&Motion.dpad(hit.second.first,hit.second.second)==setOf(7)){"Rotated physical-right mapping $hit"}
    val down=android.view.MotionEvent.obtain(SystemClock.uptimeMillis(),SystemClock.uptimeMillis(),0,x,y,0);scene.dispatchTouchEvent(down);down.recycle();check(scene.held==setOf(7))
    val up=android.view.MotionEvent.obtain(SystemClock.uptimeMillis(),SystemClock.uptimeMillis(),1,x,y,0);scene.dispatchTouchEvent(up);up.recycle();check(scene.held.isEmpty())
   }
   val book=probe.uiAutomation.takeScreenshot()!!;File(dir,"book.png").outputStream().use{book.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};book.recycle();File(dir,"book.json").writeText(state().toString(2))
   toggle("恢复双屏握法");waitFor("normal orientation restored"){abs(it.optDouble("presentedBookAngle"))<.01&&!it.optBoolean("bookTransitioning")}
  }
  val leave=MainActivity::class.java.getDeclaredMethod("leaveGame",Boolean::class.javaPrimitiveType).apply{isAccessible=true};probe.runOnMainSync{leave.invoke(a,false)};waitFor("return shelf"){it.optString("stage")=="MEDIA"&&it.optBoolean("assetReady")}
  result.putString("result","PASS: virtual-tablet DS loading/boot with original ARM loops, 256x384 dual frame and lower-LCD ray mapping; NDS book/return and projected physical-right checks when requested; no commercial title or in-game touch acceptance");probe.finish(-1,result)
 }catch(e:Throwable){NativeCore.stop();result.putString("error",e.toString());probe.finish(0,result)}
}
