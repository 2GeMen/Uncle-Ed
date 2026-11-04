// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import java.io.File
import org.json.JSONArray
import org.json.JSONObject

/** Independent virtual tablet; all captures remain local private QA. */
fun runTabletParityProbe(probe:Instrumentation){val result=Bundle()
 try{
  check(probe.targetContext.resources.configuration.smallestScreenWidthDp>=600){"Tablet viewport required"}
  check(android.os.Build.MODEL.contains("sdk")||android.os.Build.FINGERPRINT.contains("generic"))
  probe.targetContext.getSharedPreferences("resource-network-consent",0).edit().putBoolean("approved-v1",false).commit()
  val a=probe.startActivitySync(Intent(probe.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
  probe.runOnMainSync{a.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)}
  dismissFirstRunFullscreenHint(probe)
  fun state():JSONObject{var s=JSONObject();probe.runOnMainSync{s=a.showcaseDiagnostics()};return s}
  fun waitFor(label:String,p:(JSONObject)->Boolean):JSONObject{val end=SystemClock.uptimeMillis()+120000;do{val s=state();if(p(s))return s;SystemClock.sleep(180)}while(SystemClock.uptimeMillis()<end);error("$label: ${state()}")}
  val select=MainActivity::class.java.getDeclaredMethod("selectPage",Int::class.javaPrimitiveType).apply{isAccessible=true};val confirm=MainActivity::class.java.getDeclaredMethod("confirm").apply{isAccessible=true}
  val field=MainActivity::class.java.getDeclaredField("scene").apply{isAccessible=true};val scene=field.get(a) as MachineSurface
  val dir=File(probe.targetContext.filesDir,"tablet-parity-qa").also{it.mkdirs()};val rows=JSONArray()
  fun capture(name:String){val b=probe.uiAutomation.takeScreenshot()!!;File(dir,name).outputStream().use{b.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};b.recycle()}
  waitFor("home"){it.optBoolean("assetReady")}
  for((index,kind) in Machine.available(true).withIndex()){
   File(dir,"before-$index.json").writeText(state().toString(2))
   probe.runOnMainSync{select.invoke(a,index)};waitFor("${kind.key} home"){it.optString("stage")=="MACHINE"&&it.optString("model")==kind.key&&kotlin.math.abs(it.optDouble("presentedOffset"))<1&&it.optBoolean("assetReady")};SystemClock.sleep(500);capture("${kind.key}-home.png")
   probe.runOnMainSync{confirm.invoke(a)};waitFor("theme"){it.optString("stage")=="THEME"&&it.optBoolean("assetReady")}
   for(theme in 0..3){
    probe.runOnMainSync{scene.inspecting=false;scene.yaw=0f;scene.pitch=0f;select.invoke(a,theme)}
    val s=waitFor("${kind.key}-$theme rendered"){it.optString("shownModel")=="${kind.key}-$theme"&&!it.optBoolean("busy")&&it.optBoolean("assetReady")&&it.optDouble("sceneAlpha")>.99}
    SystemClock.sleep(500);capture("${kind.key}-$theme-front.png");rows.put(s);File(dir,"partial.json").writeText(rows.toString(2))
    probe.runOnMainSync{scene.inspecting=true;scene.yaw=172f;scene.pitch=12f};waitFor("reverse"){it.optBoolean("presentedInspecting")};SystemClock.sleep(300);capture("${kind.key}-$theme-back.png")
   }
   probe.runOnMainSync{scene.inspecting=false;scene.yaw=0f;scene.pitch=0f;a.onBackPressed()};waitFor("back home"){it.optString("stage")=="MACHINE"&&it.optBoolean("assetReady")}
  }
  File(dir,"report.json").writeText(JSONObject().put("smallestDp",probe.targetContext.resources.configuration.smallestScreenWidthDp).put("themes",rows).put("physicalTablet",false).toString(2))
  result.putString("result","PASS: virtual tablet five families and 20 theme front/back captures; screenshots require review; no physical device used");probe.finish(-1,result)
 }catch(e:Throwable){result.putString("error",e.toString());probe.finish(0,result)}
}
