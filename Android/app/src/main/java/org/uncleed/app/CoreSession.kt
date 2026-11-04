// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app

import android.media.*
import android.os.Process
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.locks.LockSupport

/** The core and its graphics context have one owner thread for their entire life. */
class CoreSession(private val directory:File,private val context:android.content.Context,private val saveDirectory:File=File(directory,"saves"),private val onSaveFailure:()->Unit={},private val onReady:(Boolean,String)->Unit) {
    private val active=AtomicBoolean(false)
    @Volatile private var paused=false
    @Volatile private var saveRequested=false
    @Volatile private var focusLost=false
    @Volatile var underruns=0;private set
    @Volatile var frames=0L;private set
    @Volatile var lateFrames=0L;private set
    @Volatile var pcmBytes=0L;private set
    @Volatile private var audioBufferedMs=0L
    @Volatile private var audioRecoveries=0L
    @Volatile private var suspendedNanos=0L
    @Volatile private var suspensionBegan=0L
    @Volatile private var audioFocusLosses=0
    @Volatile var volume=1f
    private val starvationEvents=ArrayDeque<org.json.JSONObject>()
    @Volatile private var playbackStartedMs=0L
    @Volatile private var previousUnderruns=0
    private val stateRequests=java.util.concurrent.ConcurrentLinkedQueue<Triple<Boolean,Int,(Int,String)->Unit>>()
    fun state(restore:Boolean,slot:Int,done:(Int,String)->Unit){if(!active.get()){done(0,"游戏未运行");return};stateRequests.add(Triple(restore,slot,done))}
    private var worker:Thread?=null
    private var saveFailureNotified=false
    private fun reportSaveFailure(){if(!saveFailureNotified){saveFailureNotified=true;runCatching{onSaveFailure()}}}
    private val frameMicros=LongArray(600)
    @Volatile private var measuredFrames=0L
    @Volatile private var runLifetimeMaxMicros=0L
    @Volatile private var runStartupMaxMicros=0L
    @Volatile private var runAfterAudioStartMaxMicros=0L
    fun diagnostics():org.json.JSONObject{val count=minOf(measuredFrames,600).toInt();val samples=frameMicros.copyOf(count).sorted();return org.json.JSONObject().put("frames",frames).put("lateFrames",lateFrames).put("audioUnderruns",underruns).put("pcmBytes",pcmBytes).put("audioBufferedMs",audioBufferedMs).put("audioRecoveries",audioRecoveries).put("audioUnderrunEvents",synchronized(starvationEvents){org.json.JSONArray(starvationEvents.toList())}).put("paused",paused).put("audioFocusLost",focusLost).put("audioFocusLosses",audioFocusLosses).put("suspendedMs",(suspendedNanos+(if(suspensionBegan>0)System.nanoTime()-suspensionBegan else 0))/1_000_000).put("runLifetimeMaxMicros",runLifetimeMaxMicros).put("runStartupMaxMicros",runStartupMaxMicros).put("runAfterAudioStartMaxMicros",runAfterAudioStartMaxMicros).put("runP95Micros",if(count>0)samples[((count-1)*.95).toInt()]else 0).put("runMaxMicros",samples.lastOrNull()?:0)}
    fun start(game:Game,rom:File) {
        check(worker==null)
        active.set(true)
        worker=Thread({
            Process.setThreadPriority(Process.THREAD_PRIORITY_DISPLAY)
            var track:AudioTrack?=null
            val audioManager=context.getSystemService(AudioManager::class.java)
            val focus=AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN).setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()).setAcceptsDelayedFocusGain(true).setWillPauseWhenDucked(true).setOnAudioFocusChangeListener{change->focusLost=change<=0;if(focusLost){audioFocusLosses++;saveRequested=true;NativeCore.input(0,0,0,0,0,false)}}.build()
            try {
                val system=File(directory,"system").also{check(it.isDirectory||it.mkdirs()){"Cannot create system directory"}}
                val saves=saveDirectory.also{check(it.isDirectory||it.mkdirs()){"Cannot create save directory"}}
                if(!NativeCore.load(game.machine.core,rom.path,system.path,File(saves,game.id).path)) {
                    onReady(false,NativeCore.error());return@Thread
                }
                val coreHash=java.util.zip.ZipFile(context.applicationInfo.sourceDir).use{apk->
                    val entry=android.os.Build.SUPPORTED_ABIS.firstNotNullOfOrNull{abi->apk.getEntry("lib/$abi/lib${game.machine.core}.so")}?:error("Cannot identify core build")
                    val digest=java.security.MessageDigest.getInstance("SHA-256");apk.getInputStream(entry).use{stream->val b=ByteArray(128*1024);while(true){val n=stream.read(b);if(n<0)break;digest.update(b,0,n)}};digest.digest().joinToString(""){"%02x".format(it)}
                }
                NativeCore.stateIdentity(game.id,coreHash)
                val info=NativeCore.info();val sampleRate=info[2];val step=(1e12/info[3]).toLong()
                val minimum=AudioTrack.getMinBufferSize(sampleRate,AudioFormat.CHANNEL_OUT_STEREO,AudioFormat.ENCODING_PCM_16BIT)
                check(minimum>0){"Unsupported audio output"}
                track=AudioTrack.Builder().setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                    .setAudioFormat(AudioFormat.Builder().setSampleRate(sampleRate).setChannelMask(AudioFormat.CHANNEL_OUT_STEREO).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
                    .setTransferMode(AudioTrack.MODE_STREAM).setBufferSizeInBytes(maxOf(minimum*2,sampleRate/10*4)).setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY).build()
                check(track.state==AudioTrack.STATE_INITIALIZED){"Audio output failed"}
                focusLost=audioManager.requestAudioFocus(focus)!=AudioManager.AUDIOFOCUS_REQUEST_GRANTED
                onReady(true,"")
                val pcm=ByteBuffer.allocateDirect(32768);var next=System.nanoTime();var queued=0;var primed=false;var writtenFrames=0L;var previousHead=0L;var headWrap=0L;var appliedVolume= -1f
                val primeBytes=minOf(track.bufferSizeInFrames*4*3/4,sampleRate*4*64/1000)
                while(active.get()) {
                    while(true){val request=stateRequests.poll()?:break;if(track.playState==AudioTrack.PLAYSTATE_PLAYING)track.pause();track.flush();primed=false;queued=0;writtenFrames=0;previousHead=0;headWrap=0;next=System.nanoTime();val result=NativeCore.stateOperation(request.first,request.second);request.third(result,NativeCore.stateError());if(result == -2)active.set(false)}
                    if(saveRequested){saveRequested=false;if(!NativeCore.flushSave())reportSaveFailure()}
                    val targetVolume=volume.coerceIn(0f,1f);if(targetVolume!=appliedVolume){track.setVolume(targetVolume);appliedVolume=targetVolume}
                    if(paused||focusLost){if(suspensionBegan==0L)suspensionBegan=System.nanoTime();if(track.playState==AudioTrack.PLAYSTATE_PLAYING)track.pause();track.flush();primed=false;queued=0;writtenFrames=0L;previousHead=0L;headWrap=0L;audioBufferedMs=0;next=System.nanoTime();LockSupport.parkNanos(10_000_000);continue}
                    if(suspensionBegan>0){suspendedNanos+=System.nanoTime()-suspensionBegan;suspensionBegan=0L}
                    if(primed&&track.playState!=AudioTrack.PLAYSTATE_PLAYING)track.play()
                    val runStart=System.nanoTime();NativeCore.run();val measuredRun=(System.nanoTime()-runStart)/1000;frameMicros[(measuredFrames%600).toInt()]=measuredRun;runLifetimeMaxMicros=maxOf(runLifetimeMaxMicros,measuredRun);if(measuredFrames<180)runStartupMaxMicros=maxOf(runStartupMaxMicros,measuredRun);if(primed)runAfterAudioStartMaxMicros=maxOf(runAfterAudioStartMaxMicros,measuredRun);measuredFrames++;frames++
                    pcm.clear();val bytes=NativeCore.pullAudio(pcm)
                    pcmBytes+=bytes;underruns=track.underrunCount
                    pcm.limit(bytes);while(pcm.hasRemaining()&&active.get()) {
                        val n=track.write(pcm,pcm.remaining(),AudioTrack.WRITE_NON_BLOCKING)
                        check(n>=0){"Audio output disconnected ($n)"}
                        if(n>0)writtenFrames+=n/4
                        if(!primed&&n>0){queued+=n;if(queued>=primeBytes){track.play();primed=true;if(playbackStartedMs==0L)playbackStartedMs=android.os.SystemClock.elapsedRealtime()}}
                        if(n==0){if(!primed&&queued>0){track.play();primed=true;if(playbackStartedMs==0L)playbackStartedMs=android.os.SystemClock.elapsedRealtime()};LockSupport.parkNanos(1_000_000)}
                    }
                    // A late GPU/core frame must not permanently drain the audio reserve.
                    // Catch up real emulation (no skipped game/video/audio frames) before sleeping.
                    val head=track.playbackHeadPosition.toLong() and 0xffffffffL
                    if(head<previousHead)headWrap+=1L shl 32;previousHead=head
                    val buffered=(writtenFrames-headWrap-head).coerceAtLeast(0)
                    audioBufferedMs=buffered*1000/sampleRate
                    val observedUnderruns=track.underrunCount
                    if(observedUnderruns>previousUnderruns){
                        val timing=NativeCore.timing()
                        val event=org.json.JSONObject().put("nativeRunMicros",timing[0]).put("videoCallbackMicros",timing[1]).put("frame",frames).put("sincePlaybackMs",android.os.SystemClock.elapsedRealtime()-playbackStartedMs).put("count",observedUnderruns-previousUnderruns).put("bufferedMs",audioBufferedMs).put("runMicros",frameMicros[((measuredFrames-1)%600).toInt()])
                        synchronized(starvationEvents){starvationEvents.addLast(event);while(starvationEvents.size>12)starvationEvents.removeFirst()}
                    }
                    previousUnderruns=observedUnderruns;underruns=observedUnderruns
                    next+=step
                    if(primed&&bytes>0&&buffered<primeBytes/4){audioRecoveries++;next=System.nanoTime();continue}
                    val remain=next-System.nanoTime()
                    if(remain>0)LockSupport.parkNanos(remain) else if(remain < -step*3){lateFrames++;next=System.nanoTime()}
                }
            } catch(e:Exception){onReady(false,e.message?:"Core failure")}
            finally {runCatching{track?.pause();track?.flush()};NativeCore.input(0,0,0,0,0,false);NativeCore.stop();if(NativeCore.saveError().isNotEmpty())reportSaveFailure();track?.stop();track?.release();audioManager.abandonAudioFocusRequest(focus);active.set(false)}
        },"UncleEd-core").also{it.start()}
    }
    fun pause(value:Boolean){if(value)saveRequested=true;paused=value;if(value)NativeCore.input(0,0,0,0,0,false)}
    fun close(){active.set(false);worker?.interrupt() /* No main-thread join: a core may be finishing a frame. */}
    fun isAlive()=worker?.isAlive==true
}
