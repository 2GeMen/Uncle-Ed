// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.view.View
import android.widget.TextView
import java.io.File
import org.json.JSONObject
import org.json.JSONArray

/** Real GPU model-only audit on any display. Does not enable unsupported device UI. */
fun runModelMaterialsProbe(probe:Instrumentation){val result=Bundle();try{
 val a=probe.startActivitySync(Intent(probe.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)) as MainActivity
 probe.runOnMainSync{a.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)};dismissFirstRunFullscreenHint(probe)
 fun field(name:String)=MainActivity::class.java.getDeclaredField(name).apply{isAccessible=true}.get(a)
 val scene=field("scene") as MachineSurface;val rim=field("rim") as RimOverlay
 fun state():JSONObject{var s=JSONObject();probe.runOnMainSync{s=a.showcaseDiagnostics()};return s}
 fun waitFor(label:String,p:(JSONObject)->Boolean):JSONObject{val end=SystemClock.uptimeMillis()+45000;do{val s=state();if(p(s))return s;SystemClock.sleep(100)}while(SystemClock.uptimeMillis()<end);error("$label ${state()}")}
 waitFor("initial model"){it.optBoolean("assetReady")};SystemClock.sleep(500)
 val dir=File(probe.targetContext.filesDir,"model-materials-qa").also{it.mkdirs()};val rows=JSONArray()
 probe.runOnMainSync{(field("logo") as View).visibility=View.GONE;(field("detail") as View).visibility=View.GONE;rim.effectEnabled=false;scene.previewProbeTime=0.0}
 for(kind in Machine.entries)for(theme in 0..3){
  val name="${kind.key}-$theme";val prepared=probe.targetContext.assets.open("models/$name.glb").use{NeighbourModel.buffer(it.readBytes())}
  probe.runOnMainSync{scene.show(prepared.buffer,kind,prepared.sha);scene.physicalComparison=true;scene.themeMode=true;scene.carouselEnabled=false;scene.inspecting=true;scene.alpha=1f;(field("title") as TextView).text="${kind.label} · ${kind.themes[theme]} · 模型核对"}
  waitFor(name){it.optString("model")==kind.key&&it.optBoolean("assetReady")&&it.optInt("primaryRoot")==scene.viewer.asset!!.root}
  for((label,angles) in listOf("front" to (0f to 0f),"angle" to (35f to 15f),"rear" to (175f to 5f))){
   val frames=state().optInt("presentedFrames");probe.runOnMainSync{scene.yaw=angles.first;scene.pitch=angles.second}
   val s=waitFor("$name $label"){it.optInt("presentedFrames")>=frames+8};SystemClock.sleep(100)
   val b=probe.uiAutomation.takeScreenshot()!!;File(dir,"$name-$label.png").outputStream().use{b.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};b.recycle();rows.put(JSONObject().put("model",name).put("pose",label).put("state",s));File(dir,"partial.json").writeText(rows.toString(2))

  }
 }
 File(dir,"report.json").writeText(JSONObject().put("cases",rows).put("modelOnly",true).put("physicalTablet",false).toString(2));result.putString("result","PASS: 20 models x front/angle/rear on actual GPU; model-only audit, screenshots require visual review, not tablet-page acceptance");probe.finish(-1,result)
 }catch(e:Throwable){result.putString("error",e.toString());probe.finish(0,result)}}
