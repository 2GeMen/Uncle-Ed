// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import java.io.File
import org.json.JSONObject

fun runGameMenuProbe(probe:Instrumentation){val result=Bundle()
 try{
  check(android.os.Build.MODEL.contains("sdk")||android.os.Build.FINGERPRINT.contains("generic"))
  val root=probe.targetContext.filesDir;val fixture=File(probe.targetContext.cacheDir,"core-probe/probe.gba");check(fixture.length()==272L)
  val library=GameLibrary(root);library.import(fixture.inputStream(),"Original GBA Input Probe.gba");val game=library.games.first{it.originalName=="Original GBA Input Probe.gba"}
  probe.targetContext.getSharedPreferences("resource-network-consent",0).edit().putBoolean("approved-v1",false).commit()
  val a=probe.startActivitySync(Intent(probe.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
  val validationRoot=File(probe.targetContext.cacheDir,"validation-saves/run-${java.util.UUID.randomUUID()}")
  fun userSaveHashes()=File(root,"saves").walkTopDown().filter{it.isFile}.associate{it.relativeTo(root).path to java.security.MessageDigest.getInstance("SHA-256").digest(it.readBytes()).joinToString(""){b->"%02x".format(b)}}
  val originalSaves=userSaveHashes()
  probe.runOnMainSync{a.useValidationSaves(validationRoot)}
  probe.runOnMainSync{a.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)}
  dismissFirstRunFullscreenHint(probe)
  fun state():JSONObject{var s=JSONObject();probe.runOnMainSync{s=a.showcaseDiagnostics()};return s}
  fun waitFor(label:String,p:(JSONObject)->Boolean){val end=SystemClock.uptimeMillis()+90000;do{if(p(state()))return;SystemClock.sleep(150)}while(SystemClock.uptimeMillis()<end);error("$label: ${state()}")}
  val confirm=MainActivity::class.java.getDeclaredMethod("confirm").apply{isAccessible=true};val select=MainActivity::class.java.getDeclaredMethod("selectPage",Int::class.javaPrimitiveType).apply{isAccessible=true}
  waitFor("home"){it.optBoolean("assetReady")};if(probe.targetContext.resources.configuration.smallestScreenWidthDp>=600){probe.runOnMainSync{select.invoke(a,1)};waitFor("GBA tablet home"){it.optString("model")=="gba"&&kotlin.math.abs(it.optDouble("presentedOffset"))<1&&it.optBoolean("assetReady")}};SystemClock.sleep(400);probe.runOnMainSync{confirm.invoke(a)};waitFor("theme"){it.optString("stage")=="THEME"&&it.optBoolean("assetReady")};SystemClock.sleep(400);probe.runOnMainSync{confirm.invoke(a)}
  waitFor("media"){it.optString("stage")=="MEDIA"&&it.optBoolean("assetReady")};val index=library.games.filter{it.machine==Machine.GBA}.indexOfFirst{it.id==game.id};probe.runOnMainSync{select.invoke(a,index)}
  waitFor("selected"){it.optString("coverGame")==game.id&&kotlin.math.abs(it.optDouble("presentedOffset"))<1};probe.runOnMainSync{confirm.invoke(a)}
  waitFor("playing after real-time insertion"){it.optString("stage")=="PLAYING"};SystemClock.sleep(1000);check(NativeCore.info()[0]==240)
  NativeCore.input(1 shl 8,0,0,0,0,false);SystemClock.sleep(500);NativeCore.input(0,0,0,0,0,false)
  val save=File(validationRoot,"${game.id}.srm");save.parentFile!!.mkdirs();save.writeBytes(ByteArray(32768){0x55.toByte()})
  val open=MainActivity::class.java.getDeclaredMethod("showGameMenu").apply{isAccessible=true};probe.runOnMainSync{open.invoke(a)}
  val menu=MainActivity::class.java.getDeclaredField("gameMenu").apply{isAccessible=true};check(menu.get(a)!=null)
  val deadline=SystemClock.uptimeMillis()+5000;while((!save.isFile||save.readBytes().firstOrNull()?.toInt() !in 0..1)&&SystemClock.uptimeMillis()<deadline)SystemClock.sleep(100)
  check(save.isFile&&save.readBytes()[0].toInt() in 0..1){"Menu pause did not flush SRAM"}
  probe.waitForIdleSync();SystemClock.sleep(600);check((menu.get(a) as android.view.View).isShown)
  val dir=File(root,"game-menu-qa").also{it.mkdirs()};val b=probe.uiAutomation.takeScreenshot()!!;File(dir,"drawer.png").outputStream().use{b.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};b.recycle()
  SystemClock.sleep(250);val pausedFrame=NativeCore.info()[4];SystemClock.sleep(300);check(NativeCore.info()[4]==pausedFrame){"Core advanced behind pause menu"}
  val resume=MainActivity::class.java.getDeclaredMethod("hideGameMenu",Boolean::class.javaPrimitiveType).apply{isAccessible=true};probe.runOnMainSync{resume.invoke(a,true)};SystemClock.sleep(500);check(NativeCore.info()[4]>pausedFrame+3){"Core did not resume after menu/audio flush"}
  probe.runOnMainSync{open.invoke(a)}
  val leave=MainActivity::class.java.getDeclaredMethod("leaveGame",Boolean::class.javaPrimitiveType).apply{isAccessible=true};probe.runOnMainSync{leave.invoke(a,false)};waitFor("shelf"){it.optString("stage")=="MEDIA"&&it.optBoolean("assetReady")}
  waitFor("core shutdown"){!it.optBoolean("coreWorkerAlive")}
  check(state().optBoolean("validationSavesActive"));check(userSaveHashes()==originalSaves){"Normal saves changed during isolated QA"}
  File(dir,"isolation.json").writeText(JSONObject().put("normalSavesUnchanged",true).put("isolatedSramCreated",save.isFile).put("commercialGameplayAccepted",false).toString(2))
  result.putString("result","PASS: original GBA probe loads after real-time insertion, menu pauses and flushes current SRAM over the sentinel, resumes core/audio then returns to shelf; no commercial game");probe.finish(-1,result)
 }catch(e:Throwable){NativeCore.stop();result.putString("error",e.toString());probe.finish(0,result)}
}
