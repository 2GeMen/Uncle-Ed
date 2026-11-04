// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app

import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.view.MotionEvent
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.ByteBuffer

/** Opt-in local fixtures only. No ROM, title list or device path is bundled. */
fun runPrivateImport(probe:Instrumentation) {
 val result=Bundle()
 try {
  probe.startActivitySync(Intent(probe.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
  val root=probe.targetContext.filesDir;val incoming=File(probe.targetContext.cacheDir,"private-sync")
  val manifest=JSONArray(File(incoming,"manifest.json").readText());val library=GameLibrary(root);var added=0
  for(i in 0 until manifest.length()) {val entry=manifest.getJSONObject(i);val file=File(incoming,entry.getString("file"));check(file.canonicalFile.parentFile==incoming.canonicalFile);if(file.exists()){added+=library.import(file.inputStream(),entry.getString("name")).size;file.delete()}}
  val audit=JSONArray();library.games.filter{it.machine==Machine.GBA||it.machine==Machine.GBC}.forEach{game->
   val save=File(probe.targetContext.cacheDir,"private-game-probes/${game.id}").also{it.parentFile!!.mkdirs()}
   check(NativeCore.load(game.machine.core,library.file(game).path,File(root,"system").also{it.mkdirs()}.path,save.path)){NativeCore.error()}
   val pcm=ByteBuffer.allocateDirect(32768);var bytes=0;val start=System.nanoTime()
   repeat(600){NativeCore.run();pcm.clear();bytes+=NativeCore.pullAudio(pcm)}
   val info=NativeCore.info();val rgba=ByteBuffer.allocateDirect(info[0]*info[1]*4);check(NativeCore.copyFrame(rgba,0,false)>0);val colors=mutableSetOf<Int>();for(j in 0 until rgba.capacity() step 4)colors.add(rgba.getInt(j));NativeCore.stop()
   audit.put(JSONObject().put("id",game.id).put("title",game.title).put("frames",info[4]).put("pcmBytes",bytes).put("uniqueColors",colors.size).put("unpacedMs",(System.nanoTime()-start)/1e6))
  }
  File(root,"private-game-audit.json").writeText(JSONObject().put("added",added).put("libraryCount",library.games.size).put("coreSmoke",audit).put("commercialGameplayAccepted",false).toString(2))
  result.putString("result","PASS: private library imported; ${library.games.size} entries; ${audit.length()} GBA/GBC core smoke runs. Gameplay still requires UI review.");probe.finish(-1,result)
 }catch(e:Throwable){NativeCore.stop();result.putString("error",e.toString());probe.finish(0,result)}
}

internal var privateJourneySampleSeconds=30
internal var privateJourneyTitle:String?=null
internal var privateJourneySkipKeys=false
internal var privateJourneyInteractiveSeconds=0
internal var privateJourneyExistingRun:String?=null

fun runPrivateJourney(probe:Instrumentation,machine:String) {
 val result=Bundle()
 var runningActivity:MainActivity?=null
 try {
  val activity=probe.startActivitySync(Intent(probe.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)) as MainActivity
  runningActivity=activity
  val saveRun=privateJourneyExistingRun?:"run-${java.util.UUID.randomUUID()}"
  probe.runOnMainSync{activity.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);activity.useValidationSaves(File(probe.targetContext.cacheDir,"validation-saves/$saveRun"))}
  fun state():JSONObject {var s=JSONObject();probe.runOnMainSync{s=activity.showcaseDiagnostics()};return s}
  fun waitFor(label:String,predicate:(JSONObject)->Boolean):JSONObject {val deadline=SystemClock.uptimeMillis()+45000;do{val s=state();if(predicate(s))return s;SystemClock.sleep(200)}while(SystemClock.uptimeMillis()<deadline);error("$label: ${state()}")}
  fun send(action:Int,down:Long,x:Float,y:Float,time:Long=SystemClock.uptimeMillis()){val e=MotionEvent.obtain(down,time,action,x,y,0);probe.sendPointerSync(e);e.recycle()}
  fun tap(x:Float,y:Float){val down=SystemClock.uptimeMillis();send(0,down,x,y);SystemClock.sleep(50);send(1,down,x,y,down+50)}
  fun centreTap(){val s=state();tap(s.getInt("surfaceX")+s.getInt("surfaceWidth")*.5f,s.getInt("surfaceY")+s.getInt("surfaceHeight")*.5f)}
  waitFor("home"){it.optBoolean("assetReady")};SystemClock.sleep(500)
  if(machine=="psp"){val selectMachine=MainActivity::class.java.getDeclaredMethod("selectPage",Int::class.javaPrimitiveType).apply{isAccessible=true};probe.runOnMainSync{selectMachine.invoke(activity,2)};waitFor("PSP"){it.optString("model")=="psp"&&it.optBoolean("assetReady")&&kotlin.math.abs(it.optDouble("presentedOffset"))<1};SystemClock.sleep(500)}
  if(machine=="gbc") {val s=state();val x=s.getInt("surfaceX")+s.getInt("surfaceWidth")*.6f;val y=s.getInt("surfaceY")+s.getInt("surfaceHeight")*.5f;val down=SystemClock.uptimeMillis();send(0,down,x,y);send(2,down,x-220,y,down+70);send(1,down,x-220,y,down+100);waitFor("GBC"){it.optString("model")=="gbc"&&it.optBoolean("assetReady")};SystemClock.sleep(600)}
  centreTap();waitFor("theme"){it.optString("stage")=="THEME"&&it.optBoolean("assetReady")};SystemClock.sleep(400)
  centreTap();waitFor("media"){it.optString("stage")=="MEDIA"&&it.optBoolean("assetReady")};SystemClock.sleep(500)
  val wanted=privateJourneyTitle?:if(machine=="gbc")"Silver" else if(machine=="psp")"Vice City" else "FireRed"
  val selected=GameLibrary(probe.targetContext.filesDir).games.filter{it.machine.key==machine}.indexOfFirst{it.title.contains(wanted)}
  check(selected>=0){"Private game missing: $wanted"}
  val select=MainActivity::class.java.getDeclaredMethod("selectPage",Int::class.javaPrimitiveType).apply{isAccessible=true}
  probe.runOnMainSync{select.invoke(activity,selected)}
  val media=waitFor("selected private title"){it.optString("stage")=="MEDIA"&&it.optString("detail").contains(wanted)&&it.optBoolean("assetReady")};SystemClock.sleep(500)
  val dir=File(probe.targetContext.filesDir,"gameplay-qa/$machine").also{it.mkdirs()}
  fun capture(name:String){val b=probe.uiAutomation.takeScreenshot()!!;File(dir,name).outputStream().use{b.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};b.recycle()}
  capture("media.png");centreTap();waitFor("playing"){it.optString("stage")=="PLAYING"&&it.optBoolean("assetReady")}
  val frameStart=NativeCore.info()[4];val sampleStart=SystemClock.elapsedRealtime();SystemClock.sleep(6000);val sampledFrames=NativeCore.info()[4]-frameStart;val sampleMs=SystemClock.elapsedRealtime()-sampleStart;capture("boot.png")
  val field=MainActivity::class.java.getDeclaredField("scene").apply{isAccessible=true};val scene=field.get(activity) as MachineSurface
  fun key(name:String,holdMs:Long=150){var point:Pair<Float,Float>?=null;probe.runOnMainSync{
   val asset=scene.viewer.asset!!;val number=name.substringAfter(':').toInt();val targetName=if(asset.entities.any{asset.getName(it)==name})name else if(number in 10..11)"physical-shoulder:$number" else if(number in 4..7)"dpad" else name
   val entity=asset.entities.firstOrNull{asset.getName(it)==targetName}?:error("Projected key missing: $targetName")
   val engine=scene.viewer.engine;val tm=engine.transformManager;val world=FloatArray(16);tm.getWorldTransform(tm.getInstance(entity),world)
   val rm=engine.renderableManager;val ri=rm.getInstance(entity);val c=if(ri!=0)rm.getAxisAlignedBoundingBox(ri,com.google.android.filament.Box()).center else floatArrayOf(0f,0f,0f)
   val projection=scene.viewer.camera.getProjectionMatrix(DoubleArray(16)).map{it.toFloat()}.toFloatArray();val view=scene.viewer.camera.getViewMatrix(FloatArray(16));val pv=FloatArray(16);android.opengl.Matrix.multiplyMM(pv,0,projection,0,view,0)
   val global=FloatArray(4);val clip=FloatArray(4);android.opengl.Matrix.multiplyMV(global,0,world,0,floatArrayOf(c[0],c[1],c[2],1f),0);android.opengl.Matrix.multiplyMV(clip,0,pv,0,global,0)
   var x=(clip[0]/clip[3]+1)*scene.width/2;var y=(1-clip[1]/clip[3])*scene.height/2
   if(targetName=="dpad"){val travel=36*probe.targetContext.resources.displayMetrics.density;when(number){4->y-=travel;5->y+=travel;6->x-=travel;7->x+=travel}}
   check(scene.controlAt(x,y)?.first==targetName){"Key hit mapping mismatch: $name"}
   val loc=IntArray(2);scene.getLocationOnScreen(loc);point=Pair(x+loc[0],y+loc[1])
  };val p=point!!;val down=SystemClock.uptimeMillis();send(0,down,p.first,p.second);SystemClock.sleep(holdMs);send(1,down,p.first,p.second)}
  if(privateJourneyInteractiveSeconds>0){
   val controlId=java.util.UUID.randomUUID().toString();val command=File(dir,"command.json");command.delete()
   File(dir,"live-ready.json").writeText(JSONObject().put("id",controlId).put("saveRun",saveRun).put("state",state()).toString())
   var sequence=0;val end=SystemClock.uptimeMillis()+privateJourneyInteractiveSeconds*1000L
   while(SystemClock.uptimeMillis()<end){
    if(!command.exists()){SystemClock.sleep(100);continue}
    val c=JSONObject(command.readText());command.delete()
    check(c.getString("id")==controlId&&c.getInt("seq")>sequence){"Stale private QA command"};sequence=c.getInt("seq")
    val action=c.getString("action")
    when(action){
     "key"->{val number=c.getInt("key");check(number in 0..15);key("key:$number",c.optLong("holdMs",150).coerceIn(50,2000))}
     "keys"->{val keys=c.getJSONArray("keys");check(keys.length() in 1..30);repeat(keys.length()){val number=keys.getInt(it);check(number in 0..15);key("key:$number",c.optLong("holdMs",100).coerceIn(50,500));SystemClock.sleep(c.optLong("gapMs",200).coerceIn(100,500))}}
     "wait"->SystemClock.sleep(c.optLong("ms",1000).coerceIn(0,30000))
     "restart"->{
      val leave=MainActivity::class.java.getDeclaredMethod("leaveGame",Boolean::class.javaPrimitiveType).apply{isAccessible=true}
      probe.runOnMainSync{leave.invoke(activity,false)}
      waitFor("isolated game stop"){!it.optBoolean("coreWorkerAlive")&&it.optString("stage")=="MEDIA"&&it.optBoolean("assetReady")};centreTap()
      waitFor("isolated restart"){it.optString("stage")=="PLAYING"&&it.optBoolean("assetReady")}
     }
     "instant-save","instant-load","instant-auto"->{
      val field=MainActivity::class.java.getDeclaredField("session").apply{isAccessible=true};val core=field.get(activity) as CoreSession
      core.pause(true);val latch=java.util.concurrent.CountDownLatch(1);var code=0;var message=""
      core.state(action!="instant-save",if(action=="instant-auto")1 else 0){r,m->code=r;message=m;latch.countDown()}
      check(latch.await(60,java.util.concurrent.TimeUnit.SECONDS)){"State request timed out"};check(code==1){"State operation failed: $message"};core.pause(false)
     }
     "save-failure"->{
      check(machine=="gbc"||machine=="gba"){"Only frontend-managed cartridge saves"}
      val isolated=ValidationSaves.resolve(probe.targetContext.cacheDir,File(probe.targetContext.cacheDir,"validation-saves/$saveRun"))
      check(isolated.isDirectory)
      fun hashes(root:File)=root.walkTopDown().filter{it.isFile}.associate{it.relativeTo(root).path to java.security.MessageDigest.getInstance("SHA-256").digest(it.readBytes()).joinToString(""){b->"%02x".format(b)}}
      val before=hashes(isolated);check(before.isNotEmpty()){"First create an isolated in-game save"}
      val backup=File(isolated.parentFile,"${isolated.name}-fault-${java.util.UUID.randomUUID()}")
      val sessionField=MainActivity::class.java.getDeclaredField("session").apply{isAccessible=true}
      val session=sessionField.get(activity) as CoreSession
      check(isolated.renameTo(backup));var blockingFile=false
      try{
       check(isolated.createNewFile());blockingFile=true;session.pause(true)
       val deadline=SystemClock.uptimeMillis()+10000
       while(NativeCore.saveError().isEmpty()&&SystemClock.uptimeMillis()<deadline)SystemClock.sleep(50)
       check(NativeCore.saveError().isNotEmpty()){"Native write failure was not reported"}
       var warning:android.view.accessibility.AccessibilityNodeInfo?=null
       while(SystemClock.uptimeMillis()<deadline){warning=probe.uiAutomation.rootInActiveWindow?.findAccessibilityNodeInfosByText("卡带存档未能写入")?.firstOrNull();if(warning!=null)break;SystemClock.sleep(100)}
       check(warning!=null){"Save failure dialog missing"};capture("save-failure-dialog.png")
       check(hashes(backup)==before){"Previous isolated saves changed on failure"}
      }finally{
       if(blockingFile)check(isolated.delete()){"Could not remove test-only blocker"}
       check(backup.renameTo(isolated)){"Restore isolated save directory before continuing"}
      }
      val button=probe.uiAutomation.rootInActiveWindow?.findAccessibilityNodeInfosByText("好")?.firstOrNull()
      check(button?.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK)==true){"Cannot dismiss save warning"}
      val frozen=state().getJSONObject("core").getLong("frames");session.pause(false)
      waitFor("game resumes after save failure"){it.getJSONObject("core").getLong("frames")>frozen+8}
      session.pause(true)
      val deadline=SystemClock.uptimeMillis()+10000
      while(NativeCore.saveError().isNotEmpty()&&SystemClock.uptimeMillis()<deadline)SystemClock.sleep(50)
      check(NativeCore.saveError().isEmpty()){"Saving did not recover after restoring directory"}
      session.pause(false)
      File(dir,"save-failure-review.json").writeText(JSONObject().put("isolatedSavesOnly",true).put("priorFilesHashUnchangedOnFailure",true).put("warningVisible",true).put("gameResumed",true).put("retrySucceeded",true).put("saveRun",saveRun).toString(2))
     }
     "background"->{
      check(probe.uiAutomation.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_HOME))
      waitFor("actual system background"){it.getJSONObject("core").optBoolean("paused")};SystemClock.sleep(300)
      val frozen=state().getJSONObject("core").getLong("frames");SystemClock.sleep(500);check(state().getJSONObject("core").getLong("frames")<=frozen+1){"Core kept advancing in background"}
      probe.targetContext.startActivity(Intent(probe.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP))
      waitFor("same game resumes"){!it.getJSONObject("core").optBoolean("paused")&&it.getJSONObject("core").optLong("frames")>frozen+8};check(state().getJSONArray("held").length()==0)
     }
     "audio-interruption"->{
      val manager=probe.targetContext.getSystemService(android.media.AudioManager::class.java)
      val focus=android.media.AudioFocusRequest.Builder(android.media.AudioManager.AUDIOFOCUS_GAIN_TRANSIENT).setAudioAttributes(android.media.AudioAttributes.Builder().setUsage(android.media.AudioAttributes.USAGE_MEDIA).build()).setOnAudioFocusChangeListener{}.build()
      try{check(manager.requestAudioFocus(focus)==android.media.AudioManager.AUDIOFOCUS_REQUEST_GRANTED)
       waitFor("transient audio focus loss"){it.getJSONObject("core").optBoolean("audioFocusLost")};SystemClock.sleep(300)
       val frozen=state().getJSONObject("core").getLong("frames");SystemClock.sleep(500);check(state().getJSONObject("core").getLong("frames")<=frozen+1){"Core kept advancing during audio interruption"}
      }finally{manager.abandonAudioFocusRequest(focus)}
      val frozen=state().getJSONObject("core").getLong("frames");waitFor("audio focus restored"){!it.getJSONObject("core").optBoolean("audioFocusLost")&&it.getJSONObject("core").optLong("frames")>frozen+8}
     }
     "stop"->{}
     else->error("Unknown private QA action")
    }
    SystemClock.sleep(250);capture("live-$sequence.png")
    File(dir,"ack.json").writeText(JSONObject().put("seq",sequence).put("state",state()).toString(2))
    if(action=="stop")break
   }
  }
  if(!privateJourneySkipKeys)repeat(3){key("key:3");SystemClock.sleep(1500);key(if(machine=="psp")"key:0" else "key:8");SystemClock.sleep(1500)}
  capture("after-input.png")
  val info=NativeCore.info();val raw=ByteBuffer.allocateDirect(info[0]*info[1]*4);check(NativeCore.copyFrame(raw,0,false)>0)
  val colors=mutableSetOf<Int>();for(i in 0 until raw.capacity() step 4)colors.add((raw.get(i).toInt() and 255 shl 16) or (raw.get(i+1).toInt() and 255 shl 8) or (raw.get(i+2).toInt() and 255))
  raw.rewind();val lcd=android.graphics.Bitmap.createBitmap(info[0],info[1],android.graphics.Bitmap.Config.ARGB_8888);lcd.copyPixelsFromBuffer(raw);File(dir,"lcd.png").outputStream().use{lcd.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};lcd.recycle()
  File(dir,"lcd-colors.json").writeText(JSONObject().put("uniqueRgb",colors.size).put("videoSerial",info.getOrElse(6){-1}).toString())
  check(colors.size>(if(machine=="psp")8 else 1)){"LCD has no meaningful game image: ${colors.size} RGB colors"}
  if(machine=="psp"){val sustained=JSONArray();repeat(privateJourneySampleSeconds/5){val before=NativeCore.info()[4];val tick=SystemClock.elapsedRealtime();SystemClock.sleep(5000);sustained.put(state().put("intervalMs",SystemClock.elapsedRealtime()-tick).put("coreFrameDelta",NativeCore.info()[4]-before))};capture("sustained.png");File(dir,"sustained.json").writeText(sustained.toString(2))}
  File(dir,"report.json").writeText(JSONObject().put("selectedTitle",media.optString("detail")).put("state",state()).put("coreFrames",NativeCore.info()[4]).put("sampleMs",sampleMs).put("sampledCoreFrames",sampledFrames).put("pacedCoreFps",sampledFrames*1000.0/sampleMs).put("isolatedSaves",true).put("gameplayAccepted",false).toString(2))
  // Finish the core gracefully before ending instrumentation. Killing it here would
  // discard its on-exit shader cache and make every later "repeat" a cold start.
  val leave=MainActivity::class.java.getDeclaredMethod("leaveGame",Boolean::class.javaPrimitiveType).apply{isAccessible=true}
  probe.runOnMainSync{leave.invoke(activity,true)}
  val stopDeadline=SystemClock.uptimeMillis()+15000
  while(state().optBoolean("coreWorkerAlive")&&SystemClock.uptimeMillis()<stopDeadline)SystemClock.sleep(50)
  check(!state().optBoolean("coreWorkerAlive")){"Core still saving on test shutdown"}
  File(dir,"shutdown.json").writeText(state().put("gracefulCoreStop",true).toString(2))
  result.putString("result","PASS: $machine actual navigation and boot; inputsSkipped=$privateJourneySkipKeys; screenshots require review");probe.finish(-1,result)
 }catch(e:Throwable){
  // A failed assertion must still give the core a chance to flush and unload.
  runCatching{runningActivity?.let{activity->
   val leave=MainActivity::class.java.getDeclaredMethod("leaveGame",Boolean::class.javaPrimitiveType).apply{isAccessible=true}
   probe.runOnMainSync{leave.invoke(activity,true)}
   val deadline=SystemClock.uptimeMillis()+15000
   do{var alive=false;probe.runOnMainSync{alive=activity.showcaseDiagnostics().optBoolean("coreWorkerAlive")};if(!alive)break;SystemClock.sleep(50)}while(SystemClock.uptimeMillis()<deadline)
  }}.exceptionOrNull()?.let{e.addSuppressed(it)}
  result.putString("error",e.toString());probe.finish(0,result)
 }
}
