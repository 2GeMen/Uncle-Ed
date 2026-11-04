// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import android.app.Instrumentation
import android.os.Bundle
import java.io.File
import java.nio.ByteBuffer

/** Original synthetic MIPS executable only, not commercial-game compatibility evidence. */
fun runPspCoreProbe(probe:Instrumentation){val result=Bundle()
 try{
  check(android.os.Build.MODEL.contains("sdk")||android.os.Build.FINGERPRINT.contains("generic")){"Emulator-only probe"}
  val root=probe.targetContext.filesDir;val system=File(root,"system").also{it.mkdirs()};SystemResources.install(probe.targetContext,system)
  val rom=File(probe.targetContext.cacheDir,"core-probe/original-psp.pbp");check(rom.isFile)
  val save=File(probe.targetContext.cacheDir,"psp-probe-saves/original").also{it.parentFile!!.mkdirs()}
  check(NativeCore.load("ppsspp_libretro",rom.path,system.path,save.path)){NativeCore.error()}
  val begin=System.nanoTime();val pcm=ByteBuffer.allocateDirect(32768);var count=0
  while(count<180&&(count<30||NativeCore.info()[0]==0)){NativeCore.run();pcm.clear();NativeCore.pullAudio(pcm);android.os.SystemClock.sleep(8);count++}
  val info=NativeCore.info();val frame=ByteBuffer.allocateDirect(2048*2048*4);check(NativeCore.copyFrame(frame,0,false)>0){"No frame from PSP hardware renderer"}
  NativeCore.stop();result.putString("result","PASS: official PPSSPP ARM64 core loads original MIPS probe, advances ${info[4]} frames at ${info[0]}x${info[1]}; no commercial title tested");result.putDouble("unpacedMs",(System.nanoTime()-begin)/1e6);probe.finish(-1,result)
 }catch(e:Throwable){NativeCore.stop();result.putString("error",e.toString());probe.finish(0,result)}
}
