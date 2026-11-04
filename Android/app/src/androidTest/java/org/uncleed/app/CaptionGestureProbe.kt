// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app

import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.view.MotionEvent
import org.json.JSONObject
import java.io.File

/** Real caption gestures in an emulator with three original program/art fixtures. */
fun runCaptionGestureReview(probe:Instrumentation){
    val result=Bundle();var activity:MainActivity?=null
    val root=probe.targetContext.filesDir;val db=File(root,"library.json");val backup=if(db.isFile)db.readBytes()else null
    val created=mutableListOf<File>();val prefs=probe.targetContext.getSharedPreferences("resource-network-consent",0);val hadConsent=prefs.contains("approved-v1");val oldConsent=prefs.getBoolean("approved-v1",false)
    try{
        check(android.os.Build.MODEL.contains("sdk")||android.os.Build.FINGERPRINT.contains("generic")){"Emulator-only fixtures"}
        val program=File(probe.targetContext.cacheDir,"core-probe/probe.gba").readBytes();check(program.size==272)
        prefs.edit().putBoolean("approved-v1",false).commit()
        val library=GameLibrary(root);val games=(0..2).map{i->
            val game=library.import((program+"caption-${System.nanoTime()}-$i".toByteArray()).inputStream(),"Original Shelf ${listOf("Amber","Blue","Green")[i]}.gba").single()
            created+=library.file(game)
            val art=File(root,"game-resources/${game.id}.png").also{it.parentFile!!.mkdirs()};created+=art
            val bitmap=android.graphics.Bitmap.createBitmap(32,32,android.graphics.Bitmap.Config.ARGB_8888);bitmap.eraseColor(listOf(0xffc89e43.toInt(),0xff3877af.toInt(),0xff4c8a65.toInt())[i]);art.outputStream().use{bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};bitmap.recycle()
            created+=File(root,"saves/${game.id}.srm");created+=File(root,"saves/${game.id}.rtc");game
        }
        val a=probe.startActivitySync(Intent(probe.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)) as MainActivity;activity=a
        probe.runOnMainSync{a.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)};dismissFirstRunFullscreenHint(probe)
        fun state():JSONObject{var s=JSONObject();probe.runOnMainSync{s=a.showcaseDiagnostics()};return s}
        fun waitFor(label:String,p:(JSONObject)->Boolean){val end=SystemClock.uptimeMillis()+90000;do{if(p(state()))return;SystemClock.sleep(120)}while(SystemClock.uptimeMillis()<end);error("$label ${state()}")}
        val select=MainActivity::class.java.getDeclaredMethod("selectPage",Int::class.javaPrimitiveType).apply{isAccessible=true};val confirm=MainActivity::class.java.getDeclaredMethod("confirm").apply{isAccessible=true}
        waitFor("home"){it.optBoolean("assetReady")};probe.runOnMainSync{select.invoke(a,if(probe.targetContext.resources.configuration.smallestScreenWidthDp>=600)1 else 0)};waitFor("GBA"){it.optString("model")=="gba"&&!it.optBoolean("carouselSettling")&&it.optBoolean("assetReady")}
        probe.runOnMainSync{confirm.invoke(a)};waitFor("theme"){it.optString("stage")=="THEME"&&it.optBoolean("assetReady")};probe.runOnMainSync{confirm.invoke(a)};waitFor("shelf"){it.optString("stage")=="MEDIA"&&it.optBoolean("assetReady")}
        val index=library.snapshot().filter{it.machine==Machine.GBA}.indexOfFirst{it.id==games[1].id};probe.runOnMainSync{select.invoke(a,index)};waitFor("middle"){it.optString("coverGame")==games[1].id&&!it.optBoolean("carouselSettling")};SystemClock.sleep(400)
        fun caption(id:String):Pair<Float,Float>{waitFor("caption ready $id"){s->val rows=s.getJSONArray("mediaLabels");(0 until rows.length()).any{rows.getJSONObject(it).getString("id")==id}};val s=state();val rows=s.getJSONArray("mediaLabels");val row=(0 until rows.length()).map{rows.getJSONObject(it)}.first{it.getString("id")==id};return Pair(row.getDouble("x").toFloat()+s.getInt("surfaceX"),row.getDouble("bottom").toFloat()+s.getInt("surfaceY")+15*probe.targetContext.resources.displayMetrics.density)}
        fun event(action:Int,down:Long,p:Pair<Float,Float>){val e=MotionEvent.obtain(down,SystemClock.uptimeMillis(),action,p.first,p.second,0);probe.sendPointerSync(e);e.recycle()}
        fun tap(id:String){val p=caption(id);val down=SystemClock.uptimeMillis();event(0,down,p);SystemClock.sleep(60);event(1,down,p)}
        tap(games[2].id);waitFor("neighbour caption selects"){it.optString("coverGame")==games[2].id&&!it.optBoolean("carouselSettling")};check(state().getString("stage")=="MEDIA")
        val p=caption(games[2].id);val down=SystemClock.uptimeMillis();event(0,down,p);waitFor("caption hold rotates"){it.optBoolean("presentedInspecting")};event(2,down,Pair(p.first-75,p.second-12));SystemClock.sleep(200);event(1,down,Pair(p.first-75,p.second-12));SystemClock.sleep(250);check(state().getString("stage")=="MEDIA")
        val swipe=caption(games[2].id);val drag=SystemClock.uptimeMillis();event(0,drag,swipe);SystemClock.sleep(30);event(2,drag,Pair(swipe.first+100,swipe.second));SystemClock.sleep(30);event(1,drag,Pair(swipe.first+150,swipe.second));waitFor("caption swipe previous"){it.optString("coverGame")==games[1].id&&!it.optBoolean("carouselSettling")}
        tap(games[1].id);waitFor("focused caption confirms"){it.optString("stage")=="INSERTING"||it.optString("stage")=="PLAYING"}
        val label=MainActivity::class.java.getDeclaredField("shelfLabels").apply{isAccessible=true};check((label.get(a) as android.view.View).visibility==android.view.View.GONE)
        probe.runOnMainSync{a.onBackPressed()}
        result.putString("result","PASS: neighbour caption selects, hold rotates, swipe changes page, focused caption confirms; captions hidden during loading; emulator original fixtures only")
    }catch(e:Throwable){result.putString("error",e.stackTraceToString())}
    finally{
        activity?.let{a->probe.runOnMainSync{a.finish()}}
        SystemClock.sleep(350)
        if(backup!=null)db.writeBytes(backup)else db.delete()
        created.forEach{it.delete()};if(hadConsent)prefs.edit().putBoolean("approved-v1",oldConsent).commit()else prefs.edit().remove("approved-v1").commit()
    }
    probe.finish(if(result.containsKey("error"))0 else -1,result)
}
