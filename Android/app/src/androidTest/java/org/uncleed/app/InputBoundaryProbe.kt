// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app

import android.app.Instrumentation
import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** View input / constrained-window regression without loading any ROM or save. */
var inputBoundaryFamily:String?=null
fun runInputBoundaryReview(probe:Instrumentation){
    val result=Bundle();var activity:MainActivity?=null
    try{
        val virtual=android.os.Build.MODEL.contains("sdk")||android.os.Build.FINGERPRINT.contains("generic")
        val a=probe.startActivitySync(Intent(probe.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)) as MainActivity;activity=a
        probe.runOnMainSync{a.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)};dismissFirstRunFullscreenHint(probe)
        fun state():JSONObject{var s=JSONObject();probe.runOnMainSync{s=a.showcaseDiagnostics()};return s}
        fun waitFor(label:String,p:(JSONObject)->Boolean){val end=SystemClock.uptimeMillis()+60000;do{if(p(state()))return;SystemClock.sleep(120)}while(SystemClock.uptimeMillis()<end);error("$label ${state()}")}
        val select=MainActivity::class.java.getDeclaredMethod("selectPage",Int::class.javaPrimitiveType).apply{isAccessible=true}
        val refresh=MainActivity::class.java.getDeclaredMethod("refresh").apply{isAccessible=true}
        val shown=MainActivity::class.java.getDeclaredField("shownModel").apply{isAccessible=true}
        val stage=MainActivity::class.java.getDeclaredField("stage").apply{isAccessible=true};fun stage(name:String)=stage.type.enumConstants.first{(it as Enum<*>).name==name}
        val scene=MainActivity::class.java.getDeclaredField("scene").apply{isAccessible=true}.get(a) as MachineSurface
        val root=MainActivity::class.java.getDeclaredField("root").apply{isAccessible=true}.get(a) as FrameLayout
        val dir=File(probe.targetContext.filesDir,"input-boundary-qa").also{it.mkdirs()};val rows=JSONArray();File(dir,"report.json").writeText("[]")
        fun capture(name:String){val b=probe.uiAutomation.takeScreenshot()!!;File(dir,name).outputStream().use{b.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};b.recycle()}
        var down=0L
        fun event(action:Int,vararg points:Triple<Int,Float,Float>){
            if(action==MotionEvent.ACTION_DOWN)down=SystemClock.uptimeMillis()
            val properties=points.map{p->MotionEvent.PointerProperties().apply{id=p.first;toolType=MotionEvent.TOOL_TYPE_FINGER}}.toTypedArray()
            val coords=points.map{p->MotionEvent.PointerCoords().apply{x=p.second;y=p.third;pressure=1f;size=.1f}}.toTypedArray()
            val e=MotionEvent.obtain(down,SystemClock.uptimeMillis(),action,points.size,properties,coords,0,0,1f,1f,0,0,android.view.InputDevice.SOURCE_TOUCHSCREEN,0)
            probe.runOnMainSync{scene.dispatchTouchEvent(e)};e.recycle();SystemClock.sleep(70)
        }
        fun key(name:String):Pair<Float,Float>{var p=0f to 0f;probe.runOnMainSync{p=project(scene,name);check(scene.controlAt(p.first,p.second)?.first==name){"Control mismatch $name"}};return p}
        fun finger(id:Int,p:Pair<Float,Float>)=Triple(id,p.first,p.second)
        fun held(vararg keys:Int){check(scene.held==keys.toSet()){"Expected ${keys.toList()}, got ${scene.held}"}}
        waitFor("home"){it.optBoolean("assetReady")}
        for((index,kind) in Machine.available(DeviceProfile.isTablet(a)).withIndex()){
            if(inputBoundaryFamily!=null&&kind.key!=inputBoundaryFamily)continue
            probe.runOnMainSync{select.invoke(a,index)};waitFor("family"){it.optString("model")==kind.key&&it.optBoolean("assetReady")&&!it.optBoolean("carouselSettling")}
            val open=if(kind==Machine.NDS||kind==Machine.N3DS)probe.targetContext.assets.open("models/${kind.key}-open-0.glb").use{it.readBytes()}else null
            probe.runOnMainSync{stage.set(a,stage("PLAYING"));refresh.invoke(a);if(open!=null)scene.show(java.nio.ByteBuffer.allocateDirect(open.size).apply{put(open);flip()},kind,"");scene.playing=true}
            waitFor("operating"){it.optBoolean("assetReady")};SystemClock.sleep(300)
            val pa=key("key:8");val pb=key("key:0")
            event(0,finger(3,pa));held(8)
            event(5 or (1 shl 8),finger(3,pa),finger(9,pb));held(8,0)
            event(6,finger(3,pa),finger(9,pb));held(0)
            event(3,finger(9,pb));held()
            if(kind==Machine.GBA||kind==Machine.PSP){
                val shoulder=key("physical-shoulder:10")
                event(0,finger(3,pa));event(5 or (1 shl 8),finger(3,pa),finger(9,shoulder));held(8,10)
                event(6,finger(3,pa),finger(9,shoulder));held(10);event(1,finger(9,shoulder));held()
            }
            if(kind==Machine.PSP){
                val stick=key("stick");val outside=stick.first+180*scene.resources.displayMetrics.density to stick.second
                event(0,finger(7,stick));event(2,finger(7,outside));check(scene.axisX>.98f&&kotlin.math.abs(scene.axisY)<.05f){"Captured stick reset outside circle"}
                event(5 or (1 shl 8),finger(7,outside),finger(11,pa));held(8);check(scene.axisX>.98f);capture("psp-stick-outside-with-A.png")
                event(6,finger(7,outside),finger(11,pa));held(8);check(scene.axisX==0f&&scene.axisY==0f)
                event(3,finger(11,pa));held()
            }
            if(kind==Machine.NDS||kind==Machine.N3DS){
                var touch=0f to 0f;probe.runOnMainSync{touch=project(scene,"screen:1");check(scene.touchAt(touch.first,touch.second)!=null)}
                event(0,finger(5,touch));event(5 or (1 shl 8),finger(5,touch),finger(13,pa));held(8)
                event(6,finger(5,touch),finger(13,pa));held(8);event(3,finger(13,pa));held()
            }
            // Deliberately constrain the actual content view while retaining device identity.
            val original=Configuration(a.resources.configuration)
            if(virtual){
            val narrow=Configuration(original).apply{smallestScreenWidthDp=400;screenWidthDp=540}
            check(DeviceProfile.isTablet(a.createConfigurationContext(narrow))){"Tablet capability lost in narrow context"}
            probe.runOnMainSync{root.layoutParams=root.layoutParams.apply{width=(540*a.resources.displayMetrics.density).toInt();height=(700*a.resources.displayMetrics.density).toInt()};a.onConfigurationChanged(Configuration(original).apply{smallestScreenWidthDp=400;screenWidthDp=540})}
            SystemClock.sleep(300);waitFor("resized"){it.optBoolean("assetReady")}
            }
            check(state().getInt("availableMachines")==Machine.available(DeviceProfile.isTablet(a)).size&&state().getString("model")==kind.key)
            val resizedA=key("key:8");event(0,finger(3,resizedA));held(8)
            probe.runOnMainSync{a.onWindowFocusChanged(false)};held();check(scene.axisX==0f&&scene.axisY==0f)
            probe.runOnMainSync{a.onWindowFocusChanged(true)}
            val menu=MainActivity::class.java.getDeclaredMethod("showGameMenu").apply{isAccessible=true};probe.runOnMainSync{menu.invoke(a)};SystemClock.sleep(200)
            val drawer=root.getChildAt(root.childCount-1) as GameMenu;val panel=drawer.getChildAt(0);check(panel.width<=drawer.width&&panel.width>0)
            fun hasBook(v:android.view.View):Boolean{if(v is android.widget.Button&&v.text.toString().contains("书本握法"))return true;return v is android.view.ViewGroup&&(0 until v.childCount).any{hasBook(v.getChildAt(it))}}
            check(hasBook(drawer)==(kind==Machine.NDS)){"Book action offered for wrong machine"}
            capture("${kind.key}-constrained-menu.png")
            val hide=MainActivity::class.java.getDeclaredMethod("hideGameMenu",Boolean::class.javaPrimitiveType).apply{isAccessible=true}
            probe.runOnMainSync{hide.invoke(a,true);root.layoutParams=root.layoutParams.apply{width=android.view.ViewGroup.LayoutParams.MATCH_PARENT;height=android.view.ViewGroup.LayoutParams.MATCH_PARENT};a.onConfigurationChanged(original);scene.playing=false;shown.set(a,null);stage.set(a,stage("MACHINE"));refresh.invoke(a)}
            waitFor("restored"){it.optString("stage")=="MACHINE"&&it.optBoolean("assetReady")}
            rows.put(JSONObject().put("machine",kind.key).put("independentPointers",true).put("cancelAndFocusRelease",true).put("constrainedView",virtual).put("drawerFits",true))
            File(dir,"report.json").writeText(rows.toString(2))
        }
        result.putString("result","PASS: available families independent pointers/release/cancel/focus, captured PSP stick; constrained-content check on emulator only; no ROM or save used")
    }catch(e:Throwable){result.putString("error",e.stackTraceToString())}
    finally{activity?.let{a->probe.runOnMainSync{a.finish()}}}
    probe.finish(if(result.containsKey("error"))0 else -1,result)
}
