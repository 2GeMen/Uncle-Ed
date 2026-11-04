// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.abs

/** Local emulator only: generated non-executable fixture, never commercial ROM or a core launch. */
internal var assemblyReviewExistingTitle:String?=null

fun runAssemblyProbe(probe:Instrumentation,key:String){val result=Bundle()
 try{
  val existingTitle=assemblyReviewExistingTitle
  check(existingTitle!=null||android.os.Build.FINGERPRINT.contains("generic")||android.os.Build.MODEL.contains("sdk")){"Explicit local title or emulator required"}
  probe.targetContext.getSharedPreferences("resource-network-consent",0).edit().putBoolean("approved-v1",false).commit()
  val kind=Machine.entries.first{it.key==key};val library=GameLibrary(probe.targetContext.filesDir)
  val name="Original Assembly Fixture.${kind.extensionSet.first()}"
  if(existingTitle==null)library.import(byteArrayOf(0x55,0x45,kind.ordinal.toByte()).inputStream(),name)
  val fixture=if(existingTitle==null)library.games.first{it.originalName==name}else library.games.first{it.machine==kind&&it.title.contains(existingTitle)}
  val a=probe.startActivitySync(Intent(probe.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
  probe.runOnMainSync{a.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);if(existingTitle!=null)a.useValidationSaves(File(probe.targetContext.cacheDir,"validation-saves/run-${java.util.UUID.randomUUID()}"))}
  fun state():JSONObject{var s=JSONObject();probe.runOnMainSync{s=a.showcaseDiagnostics()};return s}
  fun waitFor(label:String,p:(JSONObject)->Boolean):JSONObject{val end=SystemClock.uptimeMillis()+90000;do{val s=state();if(p(s))return s;SystemClock.sleep(150)}while(SystemClock.uptimeMillis()<end);error("$label: ${state()}")}
  val select=MainActivity::class.java.getDeclaredMethod("selectPage",Int::class.javaPrimitiveType).apply{isAccessible=true}
  val confirm=MainActivity::class.java.getDeclaredMethod("confirm").apply{isAccessible=true}
  waitFor("home"){it.optBoolean("assetReady")};probe.runOnMainSync{select.invoke(a,Machine.available(DeviceProfile.isTablet(probe.targetContext)).indexOf(kind))};waitFor("model"){it.optString("model")==key&&abs(it.optDouble("presentedOffset"))<1&&it.optBoolean("assetReady")};SystemClock.sleep(500);probe.runOnMainSync{confirm.invoke(a)}
  waitFor("theme"){it.optString("stage")=="THEME"&&it.optBoolean("assetReady")};SystemClock.sleep(400);probe.runOnMainSync{confirm.invoke(a)}
  waitFor("media"){it.optString("stage")=="MEDIA"&&it.optBoolean("assetReady")};val index=GameLibrary(probe.targetContext.filesDir).games.filter{it.machine==kind}.indexOfFirst{it.id==fixture.id};probe.runOnMainSync{select.invoke(a,index)}
  waitFor("fixture cover"){it.optString("coverGame")==fixture.id&&abs(it.optDouble("presentedOffset"))<1}
  val field=MainActivity::class.java.getDeclaredField("scene").apply{isAccessible=true};val scene=field.get(a) as MachineSurface
  val dir=File(probe.targetContext.filesDir,"assembly-qa/$key").also{it.mkdirs()};val rows=JSONArray()
  probe.runOnMainSync{scene.assemblyProbeElapsed=0.0;confirm.invoke(a)}
  waitFor("rig and slot"){it.optInt("assemblyStage")==2&&(if(kind==Machine.PSP)it.optInt("hatchEntity")!=0 else it.optInt("slotEntity")!=0)}
  for(p in listOf(0.0,.18,.50,.65,.84,.86,.999)){
   probe.runOnMainSync{scene.assemblyProbeElapsed=p*LoadingMotion.duration(kind)}
   val s=waitFor("presented $p"){abs(it.optDouble("presentedLoadingProgress",-1.0)-p)<.002};SystemClock.sleep(150)
   val b=probe.uiAutomation.takeScreenshot()!!;File(dir,"${(p*1000).toInt()}.png").outputStream().use{b.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};b.recycle();rows.put(s)
  }
  if(kind==Machine.PSP){for((label,extra) in listOf("flip-start" to 0.0,"flip-mid" to .325,"flip-end" to .649)){
   val count=state().optInt("presentedFrames");probe.runOnMainSync{scene.assemblyProbeElapsed=LoadingMotion.duration(kind)+extra}
   val s=waitFor(label){it.optInt("presentedFrames")>=count+8&&it.optDouble("presentedLoadingProgress")>=.999};check(s.optString("stage")=="INSERTING")
   val b=probe.uiAutomation.takeScreenshot()!!;File(dir,"$label.png").outputStream().use{b.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};b.recycle();rows.put(s.put("flipElapsed",extra))
  }}
  val final=state();check(final.optString("stage")=="INSERTING");val sounds=final.getJSONArray("loadingSounds");check(sounds.length()==LoadingMotion.events(kind,1.0).size){"Missing or duplicated sound events"}
  probe.runOnMainSync{a.onBackPressed();scene.assemblyProbeElapsed=null}
  val restored=waitFor("cancel restores same game"){it.optString("stage")=="MEDIA"&&it.optString("coverGame")==fixture.id&&it.optInt("assemblyStage")==0&&it.optBoolean("assetReady")}
  File(dir,"report.json").writeText(JSONObject().put("frames",rows).put("restored",restored).put("commercialROMUsed",existingTitle!=null).put("coreLaunched",false).toString(2))
  result.putString("result","PASS: $key loading keyframes, real slot/hatch, event ordering and cancellation; existing local title or generated fixture; core not launched; screenshots require review");probe.finish(-1,result)
 }catch(e:Throwable){result.putString("error",e.toString());probe.finish(0,result)}
}
