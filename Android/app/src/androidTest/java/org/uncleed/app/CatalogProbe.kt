// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import java.io.File
import org.json.JSONObject

fun runCatalogProbe(probe:Instrumentation,consent:Boolean){val result=Bundle()
 try{
  if(consent){check(probe.targetContext.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE!=0);check(probe.targetContext.getSharedPreferences("resource-network-consent",0).edit().putBoolean("approved-v1",true).commit())}
  check(probe.targetContext.getSharedPreferences("resource-network-consent",0).getBoolean("approved-v1",false)){"Explicit resource network consent required"}
  val activity=probe.startActivitySync(Intent(probe.targetContext,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
  probe.runOnMainSync{activity.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)}
  val field=MainActivity::class.java.getDeclaredField("gameResources").apply{isAccessible=true};val resources=field.get(activity) as GameResources
  val games=GameLibrary(probe.targetContext.filesDir).games
  fun waitFor(game:Game,timeout:Long=90000){val deadline=SystemClock.uptimeMillis()+timeout;while(SystemClock.uptimeMillis()<deadline){if(resources.coverFile(game)!=null&&resources.cached(game)!=null)return;SystemClock.sleep(250)};error("Resource lookup incomplete: ${game.title}; ${resources.status(game)}")}
  val game=games.first{it.title.contains("FireRed")};waitFor(game)
  val silver=games.first{it.title.contains("Silver")};waitFor(silver)
  var networkCalls=0
  val offline=GameResources(probe.targetContext,transport={_,_->networkCalls++;error("Offline cache must not access network")},changed={})
  offline.request(game);val deadline=SystemClock.uptimeMillis()+5000;while(offline.cached(game)==null&&SystemClock.uptimeMillis()<deadline)SystemClock.sleep(100)
  check(offline.coverFile(game)!=null&&offline.cached(game)!=null&&networkCalls==0){"Offline resources unavailable"};offline.close()
  val id=java.security.MessageDigest.getInstance("SHA-256").digest(java.util.UUID.randomUUID().toString().toByteArray()).joinToString(""){"%02x".format(it)}
  val live=Game(id,Machine.GBA,"Advance Wars","$id.gba","Advance Wars (USA).gba")
  resources.request(live);waitFor(live)
  SystemClock.sleep(150)
  var liveOfflineCalls=0
  val reopened=GameResources(probe.targetContext,transport={_,_->liveOfflineCalls++;error("Offline")},changed={});reopened.request(live)
  val offlineDeadline=SystemClock.uptimeMillis()+5000;while(reopened.cached(live)==null&&SystemClock.uptimeMillis()<offlineDeadline)SystemClock.sleep(100)
  check(reopened.cached(live)!=null&&reopened.coverFile(live)!=null&&liveOfflineCalls==0){"Fresh online resources failed persisted offline reload"};reopened.close()
  val liveMeta=resources.cached(live)!!;check(liveMeta.optString("developer").isNotEmpty()&&liveMeta.optString("publisher").isNotEmpty())
  val report=JSONObject().put("fireRed",resources.cached(game)).put("silver",resources.cached(silver)).put("freshLiveLookup",liveMeta).put("offlineNetworkCalls",networkCalls).put("freshOfflineNetworkCalls",liveOfflineCalls).put("coveredGames",games.count{resources.coverFile(it)!=null}).put("libraryGames",games.size)
  File(probe.targetContext.filesDir,"catalog-qa.json").writeText(report.toString(2))
  result.putString("result","PASS: imported library auto cover/metadata, offline cache without network, fresh Advance Wars name-only online lookup");probe.finish(-1,result)
 }catch(e:Throwable){result.putString("error",e.toString());probe.finish(0,result)}
}
