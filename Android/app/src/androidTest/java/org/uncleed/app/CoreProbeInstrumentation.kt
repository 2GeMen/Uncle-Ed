// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import android.app.Instrumentation
import android.os.Bundle
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Uses an original test program supplied privately; never any commercial ROM. */
class CoreProbeInstrumentation:Instrumentation() {
 private var mode=""
 private var consent=false
 override fun onCreate(arguments:Bundle?){mode=arguments?.getString("probe")?:"";assemblyReviewExistingTitle=arguments?.getString("assemblyTitle");inputBoundaryFamily=arguments?.getString("family");consent=arguments?.getString("resourceConsent")=="approved";privateJourneySampleSeconds=(arguments?.getString("sampleSeconds")?.toIntOrNull()?:30).coerceIn(30,300);privateJourneyExistingRun=arguments?.getString("saveRun");privateJourneyInteractiveSeconds=(arguments?.getString("interactiveSeconds")?.toIntOrNull()?:0).coerceIn(0,900);privateJourneyTitle=arguments?.getString("titleContains");privateJourneySkipKeys=arguments?.getString("skipKeys")=="true";super.onCreate(arguments);start()}
 override fun onStart(){
  if(mode=="import-integrity"){runImportIntegrityProbe(this);return}
  if(mode=="model-materials"){runModelMaterialsProbe(this);return}
  if(mode=="theme-carousel"){runThemeCarouselProbe(this);return}
  if(mode=="physical-bounds"){runPhysicalBoundsProbe(this);return}
  if(mode=="pagination"){runPaginationProbe(this);return}
  if(mode=="input-boundaries"){runInputBoundaryReview(this);return}
  if(mode=="caption-shelf"){runCaptionShelfReview(this);return}
  if(mode=="caption-gestures"){runCaptionGestureReview(this);return}
  if(mode=="repair-review"){runLibraryRepairReview(this);return}
  if(mode=="controls-review"){runControlsReview(this);return}
  if(mode=="library-maintenance"){runLibraryMaintenance(this);return}
  if(mode=="color-review"||mode=="shelf-review"){runParityReview(this,mode.substringBefore("-review").let{if(it=="color")"colors" else it});return}
  if(mode=="tablet-parity"){runTabletParityProbe(this);return}
  if(mode=="nds-book"){ndsBookReview=true;runNdsTabletUiProbe(this);return}
  if(mode=="nds-tablet-ui"){runNdsTabletUiProbe(this);return}
  if(mode=="nds-core"){runNdsCoreProbe(this);return}
  if(mode=="psp-core"){runPspCoreProbe(this);return}
  if(mode=="game-menu"){runGameMenuProbe(this);return}
  if(mode.startsWith("assembly-")){runAssemblyProbe(this,mode.removePrefix("assembly-"));return}
  if(mode=="media-shelf-gbc"||mode=="media-shelf-psp"){runMediaShelfProbe(this,mode.removePrefix("media-shelf-"));return}
  if(mode=="media-carousel"){runMediaCarouselProbe(this);return}
  if(mode=="catalog-ui"){runMediaLocalProbe(this);return}
  if(mode=="catalog-score"){runCatalogScoreProbe(this);return}
  if(mode=="catalog"){runCatalogProbe(this,consent);return}
  if(mode=="home-gestures"){runHomeGestureProbe(this);return}
  if(mode=="showcase"){runShowcaseProbe(this);return}
  if(mode=="private-import"){runPrivateImport(this);return}
  if(mode=="game-gba"||mode=="game-gbc"||mode=="game-psp"){runPrivateJourney(this,mode.removePrefix("game-"));return}
  val results=Bundle()
  try {
   val dir=File(targetContext.cacheDir,"core-probe").also{it.mkdirs()}
   val rom=File(dir,"probe.gba");check(rom.isFile){"Supply Tests/Fixtures/gba-input-probe.S compiled into target cache/core-probe/probe.gba"}
   val path=File(dir,"probe-save").path
   check(NativeCore.load("mgba_libretro",rom.path,dir.path,path)){NativeCore.error()}
   val rgba=ByteBuffer.allocateDirect(240*160*4);val pcm=ByteBuffer.allocateDirect(32768).order(ByteOrder.nativeOrder())
   var audioBytes=0;val begin=System.nanoTime()
   repeat(120){NativeCore.run();pcm.clear();audioBytes+=NativeCore.pullAudio(pcm)}
   val first=NativeCore.info();check(first[0]==240&&first[1]==160){"Unexpected frame geometry"}
   check(NativeCore.copyFrame(rgba,0,false)==240*160*4)
   val red=rgba.get(4*240*80+4*120).toInt() and 255
   NativeCore.input(1 shl 8,0,0,0,0,false)
   repeat(120){NativeCore.run();pcm.clear();audioBytes+=NativeCore.pullAudio(pcm)}
   NativeCore.copyFrame(rgba,0,false)
   val green=rgba.get(4*240*80+4*120+1).toInt() and 255
   check(red>200&&green>200){"Video conversion or A-button input failed ($red,$green)"}
   check(audioBytes>0){"No PCM produced"}
   results.putInt("frames",NativeCore.info()[4]);results.putInt("audioBytes",audioBytes)
   results.putDouble("coreRunMilliseconds",(System.nanoTime()-begin)/1e6)
   NativeCore.stop()
   val sram=File(path+".srm");check(sram.isFile&&sram.readBytes()[0].toInt()==1){"SRAM save failed"}
   check(NativeCore.load("mgba_libretro",rom.path,dir.path,path)){"Reload failed"}
   NativeCore.run();NativeCore.stop()
   val library=GameLibrary(File(dir,"library-fixture").also{it.mkdirs()})
   library.import(rom.inputStream(),"Original GBA Input Probe.gba")
   check(library.import(rom.inputStream(),"Duplicate.gba").isEmpty()){"ROM hash deduplication failed"}
   val zipped=java.io.ByteArrayOutputStream();java.util.zip.ZipOutputStream(zipped).use{zip->zip.putNextEntry(java.util.zip.ZipEntry("../escape.gba"));zip.write(1);zip.closeEntry()}
   var rejected=false;try{library.import(java.io.ByteArrayInputStream(zipped.toByteArray()),"unsafe.zip")}catch(_:IllegalStateException){rejected=true}catch(_:java.util.zip.ZipException){rejected=true};check(rejected){"ZIP traversal accepted"}
   results.putString("library","PASS: streamed import, hash deduplication, ZIP traversal rejection")
   results.putString("result","PASS: original GBA probe video, input, PCM, SRAM creation, reload")
   finish(-1,results)
  }catch(e:Throwable){NativeCore.stop();results.putString("error",e.toString());finish(0,results)}
 }
}
