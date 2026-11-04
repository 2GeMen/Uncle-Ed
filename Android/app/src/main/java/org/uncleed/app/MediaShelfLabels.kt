// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app

import android.content.Context
import android.graphics.Canvas
import android.graphics.Typeface
import android.graphics.RectF
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.view.View
import android.view.MotionEvent

data class MediaPlacement(val id:String,val x:Float,val bottom:Float,val width:Float,val focus:Float)
data class MediaCaption(val title:String,val facts:String)

/** Captions follow the exact presented card, including during neighbour promotion. */
class MediaShelfLabels(context:Context):View(context){
    private val tablet=DeviceProfile.isTablet(context)
    private val d=resources.displayMetrics.density
    private val titlePaint=TextPaint(3).apply{color=0xFFE4E4D8.toInt();textSize=(if(tablet)13 else 11)*resources.displayMetrics.scaledDensity;typeface=Typeface.create(Typeface.DEFAULT,600,false)}
    private val factsPaint=TextPaint(3).apply{color=0xFFADB6A9.toInt();textSize=(if(tablet)11 else 9)*resources.displayMetrics.scaledDensity}
    private var captions=emptyMap<String,MediaCaption>()
    private var placements=emptyList<MediaPlacement>()
    private var yOffset=0f
    private val cache=mutableMapOf<String,Pair<StaticLayout,StaticLayout>>()
    private val hitRects=linkedMapOf<String,RectF>()
    private var tracking=false
    var onPreviewTouch:((MotionEvent)->Boolean)?=null
    var onActivate:((String)->Unit)?=null
    init{isClickable=true;isFocusable=true}
    fun captionAt(x:Float,y:Float)=hitRects.entries.firstOrNull{it.value.contains(x,y)}?.key
    override fun onTouchEvent(event:MotionEvent):Boolean{
        if(event.actionMasked==MotionEvent.ACTION_DOWN)tracking=captionAt(event.x,event.y)!=null
        if(!tracking)return false
        if(event.actionMasked==MotionEvent.ACTION_UP||event.actionMasked==MotionEvent.ACTION_CANCEL)tracking=false
        return onPreviewTouch?.invoke(event)?:false
    }
    override fun performClick():Boolean{super.performClick();placements.maxByOrNull{it.focus}?.id?.let{onActivate?.invoke(it)};return true}
    fun setCaptions(values:Map<String,MediaCaption>){if(values==captions)return;captions=values;cache.clear();invalidate()}
    fun present(values:List<MediaPlacement>,offset:Float){placements=values;yOffset=offset;contentDescription=values.maxByOrNull{it.focus}?.id?.let{captions[it]?.let{c->c.title+"，"+c.facts}};invalidate()}
    private fun layout(text:String,paint:TextPaint,width:Int)=StaticLayout.Builder.obtain(text,0,text.length,paint,width).setAlignment(Layout.Alignment.ALIGN_CENTER).setIncludePad(false).setLineSpacing(0f,1.12f).build()
    override fun onDraw(canvas:Canvas){
        hitRects.clear()
        for(p in placements){val c=captions[p.id]?:continue;val width=(p.width+12*d).toInt().coerceAtLeast((90*d).toInt());val key="${p.id}:$width"
            val pair=cache.getOrPut(key){layout(c.title,titlePaint,width) to layout(c.facts,factsPaint,width)}
            val top=p.bottom+yOffset+8*d
            hitRects[p.id]=RectF(p.x-width/2f,top,p.x+width/2f,top+pair.first.height+6*d+pair.second.height)
            titlePaint.alpha=(140+115*p.focus).toInt().coerceIn(0,255);factsPaint.alpha=(115+140*p.focus).toInt().coerceIn(0,255)
            canvas.save();canvas.translate(p.x-width/2f,p.bottom+yOffset+8*d);pair.first.draw(canvas);canvas.translate(0f,pair.first.height+6*d);pair.second.draw(canvas);canvas.restore()
        }
        if(cache.size>12){val active=placements.map{it.id}.toSet();cache.keys.toList().filter{it.substringBefore(':') !in active}.forEach{cache.remove(it)};while(cache.size>12)cache.remove(cache.keys.first())}
    }
}
