// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app

import android.content.Context
import android.os.*
import android.provider.Settings

/** Mechanical detents, not a repeating motor while a finger remains down. */
class GameHaptics(private val context:Context) {
    private val prefs=context.getSharedPreferences("controls",0)
    private val motor=if(Build.VERSION.SDK_INT>=31)context.getSystemService(VibratorManager::class.java).defaultVibrator else context.getSystemService(Vibrator::class.java)
    private var previous=emptySet<Int>()
    private var stickSector=0
    var pulses=0;private set
    var requests=0;private set
    var enabled:Boolean
        get()=prefs.getBoolean("haptics",true)
        set(value){prefs.edit().putBoolean("haptics",value).apply();if(!value)motor.cancel()}
    fun update(keys:Set<Int>,x:Float,y:Float) {
        val sector=if(x*x+y*y<.12f)0 else 1+(((kotlin.math.atan2(y,x)+Math.PI)*4/Math.PI).toInt() and 7)
        if((keys-previous).isNotEmpty()||sector!=0&&sector!=stickSector)tick()
        previous=keys.toSet();stickSector=sector
    }
    private fun tick(){
        requests++
        if(!enabled||!motor.hasVibrator()||Settings.System.getInt(context.contentResolver,Settings.System.HAPTIC_FEEDBACK_ENABLED,1)==0)return
        val effect=if(Build.VERSION.SDK_INT>=29)VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK) else VibrationEffect.createOneShot(12,45)
        motor.vibrate(effect,android.media.AudioAttributes.Builder().setUsage(android.media.AudioAttributes.USAGE_ASSISTANCE_SONIFICATION).build());pulses++
    }
    fun reset(){previous=emptySet();stickSector=0}
    fun diagnostics()=org.json.JSONObject().put("enabled",enabled).put("motor",motor.hasVibrator()).put("requests",requests).put("pulses",pulses)
}
