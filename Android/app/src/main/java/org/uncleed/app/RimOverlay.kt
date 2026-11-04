// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app

import android.content.Context
import android.graphics.*
import android.os.Handler
import android.os.Looper
import android.view.View
import org.json.JSONObject
import java.util.concurrent.Executors
import kotlin.math.*

/** Bounded, asynchronously loaded silhouettes generated from the shared solid model.
 * No rectangles, convex-hull approximation, device photos or runtime GPU readback.
 */
class RimOverlay(context:Context):View(context){
    data class Frame(val phase:Double,val scale:Float,val halfHeight:Double,val opacity:Float)
    private data class Pack(val frames:List<Bitmap>,val bounds:FloatArray,val scale:Float)
    private val worker=Executors.newSingleThreadExecutor()
    private val main=Handler(Looper.getMainLooper())
    private val paint=Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply{color=Color.rgb(255,214,133);xfermode=PorterDuffXfermode(PorterDuff.Mode.ADD)}
    @Volatile private var generation=0
    private var pack:Pack?=null
    private var frame=Frame(0.0,1f,1.0,0f)
    var effectEnabled=false
        set(value){field=value;invalidate()}
    init {isClickable=false;isFocusable=false;importantForAccessibility=IMPORTANT_FOR_ACCESSIBILITY_NO}
    fun load(key:String,sourceSha:String){
        val token=++generation;pack=null;invalidate()
        worker.execute{
            if(token!=generation)return@execute
            val result=runCatching{
                val metadata=context.assets.open("rims/$key/rim.json").bufferedReader().use{JSONObject(it.readText())}
                check(metadata.getString("sourceGLBSha256")==sourceSha){"Rim and model revisions differ"}
                val names=metadata.getJSONArray("frames");check(names.length() in 2..16)
                val bounds=metadata.getJSONArray("bounds");val points=FloatArray(4){bounds.getDouble(it).toFloat()}
                val decoded=ArrayList<Bitmap>();var bytes=0L
                for(index in 0 until names.length()){
                    check(token==generation){"Superseded rim request"}
                    val bitmap=context.assets.open("rims/$key/${names.getString(index)}").use{BitmapFactory.decodeStream(it)}?:error("Invalid rim image")
                    val alpha=bitmap.extractAlpha();bitmap.recycle();bytes+=alpha.allocationByteCount
                    val mask=java.nio.ByteBuffer.allocate(alpha.byteCount);alpha.copyPixelsToBuffer(mask)
                    val nonzero=mask.array().count{(it.toInt() and 255)>2}
                    check(nonzero>0&&nonzero<alpha.width*alpha.height*.3){"Rim must contain only a narrow edge"}
                    check(Color.alpha(alpha.getPixel(alpha.width/2,alpha.height/2))<3){"Rim interior must remain transparent"}
                    check(bytes<=32L*1024*1024){"Rim pack exceeds the bounded cache"};decoded+=alpha
                }
                Pack(decoded,points,metadata.getDouble("normalizationScale").toFloat())
            }
            if(token!=generation)return@execute
            main.post{if(token==generation){pack=result.getOrNull();result.exceptionOrNull()?.let{android.util.Log.i("UncleEdRim",it.message?:"Rim unavailable")};invalidate()}}
        }
    }
    fun update(value:Frame){frame=value;if(effectEnabled)invalidate()}
    fun diagnostics():Map<String,Any> = mapOf("loaded" to (pack!=null),"frameCount" to (pack?.frames?.size?:0),"alphaBytes" to (pack?.frames?.sumOf{it.allocationByteCount}?:0),"opacity" to frame.opacity,"enabled" to effectEnabled)
    override fun onDraw(canvas:Canvas){
        val p=pack?:return;val f=frame
        if(!effectEnabled||f.opacity<=.001f||f.halfHeight<=0)return
        if(abs(p.scale-f.scale)>p.scale*.005f)return // Fail closed rather than detach a stale halo.
        val units=height/(2*f.halfHeight).toFloat();val b=p.bounds
        val rect=RectF(width/2+b[0]*f.scale*units,height/2-b[3]*f.scale*units,width/2+b[2]*f.scale*units,height/2-b[1]*f.scale*units)
        val phase=((f.phase%1+1)%1)*p.frames.size;val first=floor(phase).toInt()%p.frames.size;val blend=(phase-floor(phase)).toFloat()
        paint.alpha=(255*f.opacity*(1-blend)).roundToInt().coerceIn(0,255);canvas.drawBitmap(p.frames[first],null,rect,paint)
        paint.alpha=(255*f.opacity*blend).roundToInt().coerceIn(0,255);canvas.drawBitmap(p.frames[(first+1)%p.frames.size],null,rect,paint)
    }
    override fun onDetachedFromWindow(){++generation;worker.shutdown();pack=null;super.onDetachedFromWindow()}
}
