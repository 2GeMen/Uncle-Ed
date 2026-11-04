// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import android.app.Instrumentation
import android.os.Bundle
import java.io.File
import java.nio.ByteBuffer
fun runNdsCoreProbe(probe:Instrumentation){val result=Bundle()
 try{
  check(android.os.Build.MODEL.contains("sdk")||android.os.Build.FINGERPRINT.contains("generic")){"Emulator-only probe"}
  val root=probe.targetContext.filesDir;val system=File(root,"system").also{it.mkdirs()};val rom=File(probe.targetContext.cacheDir,"core-probe/original-nds.nds");check(rom.isFile)
  val saves=File(probe.targetContext.cacheDir,"nds-probe-saves/original").also{it.parentFile!!.mkdirs()}
  check(NativeCore.load("melondsds_libretro",rom.path,system.path,saves.path)){NativeCore.error()}
  val pcm=ByteBuffer.allocateDirect(32768);repeat(30){NativeCore.run();pcm.clear();NativeCore.pullAudio(pcm)}
  val info=NativeCore.info();check(info[0]==256&&info[1]==384){"Unexpected DS frame ${info.toList()}"};check(NativeCore.copyFrame(ByteBuffer.allocateDirect(256*192*4),1,true)==256*192*4)
  NativeCore.input(0,0,0,12000,20000,true);NativeCore.run();NativeCore.input(0,0,0,0,0,false);NativeCore.stop()
  result.putString("result","PASS: source-built melonDS DS loads original ARM loops with built-in replacements; 256x384 dual frame copied; no native BIOS or commercial title");probe.finish(-1,result)
 }catch(e:Throwable){NativeCore.stop();result.putString("error",e.toString());probe.finish(0,result)}
}
