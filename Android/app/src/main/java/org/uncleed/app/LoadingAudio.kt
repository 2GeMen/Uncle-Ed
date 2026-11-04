// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool

class LoadingAudio(context:Context){
 private val pool=SoundPool.Builder().setMaxStreams(4).setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()).build()
 private val sounds=mutableMapOf<String,Int>();private val ready=mutableSetOf<Int>();private val streams=mutableListOf<Int>();private val sent=mutableSetOf<String>()
 init{pool.setOnLoadCompleteListener{_,id,status->if(status==0)ready+=id};for(name in LoadingMotion.events(Machine.PSP,1.0)+LoadingMotion.events(Machine.GBA,1.0)){runCatching{context.assets.openFd("sounds/$name.wav").use{sounds[name]=pool.load(it,1)}}}}
 fun begin(){stop();sent.clear()}
 fun advance(machine:Machine,t:Double){for(name in LoadingMotion.events(machine,t))if(sent.add(name)){sounds[name]?.takeIf{it in ready}?.let{streams+=pool.play(it,.65f,.65f,1,0,1f)}}}
 fun stop(){streams.forEach{pool.stop(it)};streams.clear()}
 fun close(){stop();pool.release()}
 fun events()=sent.toList()
}
