// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app

import android.content.Context
import android.graphics.*
import android.os.Bundle
import android.view.MotionEvent
import android.view.View
import android.view.accessibility.AccessibilityNodeInfo
import kotlin.math.*

/** Window-sized scenery; it never rotates or clips with an individual machine. */
class ShowcaseBackdrop(context:Context):View(context) {
    private val paint=Paint(Paint.ANTI_ALIAS_FLAG)
    private val beamShader:RuntimeShader?=if(android.os.Build.VERSION.SDK_INT>=33)RuntimeShader("""
        uniform float2 size;
        half4 main(float2 point) {
            float2 uv=point/size;
            float t=clamp(uv.y,0.0,1.0);
            float u=(uv.x-0.5)/(0.026+0.42*t);
            float glow=0.55*exp(-u*u*4.0)*pow(max(0.0,1.0-t),0.8);
            float3 base=float3(24.0,31.0,29.0)/255.0;
            return half4(base+float3(1.0,0.855,0.525)*glow,1.0);
        }
    """)else null
    var active=true
        set(value){field=value;invalidate()}
    override fun onDraw(canvas:Canvas){
        canvas.drawColor(Color.rgb(24,31,29))
        if(!active)return
        val w=width.toFloat();val h=height.toFloat();val cx=w*.5f
        if(android.os.Build.VERSION.SDK_INT>=33){
            val shader=beamShader
            if(shader!=null){shader.setFloatUniform("size",w,h);paint.shader=shader;canvas.drawRect(0f,0f,w,h,paint)}
        }else{
            // Compatibility path for older devices. Current Android 13+ uses the
            // same floating-point beam equation as iOS, avoiding bitmap banding.
            paint.shader=RadialGradient(cx,0f,max(w*.43f,h*.6f),intArrayOf(0xA0FFE0A0.toInt(),0x004F513B),null,Shader.TileMode.CLAMP)
            canvas.drawPath(Path().apply{moveTo(cx-w*.02f,0f);lineTo(cx+w*.02f,0f);lineTo(w*.94f,h);lineTo(w*.06f,h);close()},paint)
        }
        paint.shader=null
        val t=android.os.SystemClock.uptimeMillis()/1000.0
        for(i in 0 until 68){val y=((i*.61803398875+t*.009)%1).toFloat();val offset=sin(i*6.13).toFloat();val x=cx+offset*w*(.025f+y*.31f)
            val alpha=(40+45*(sin(t*.6+i)+1)).toInt();paint.color=Color.argb(alpha,239,215,137)
            canvas.drawCircle(x,y*h,(.5f+(i%3)*.32f)*resources.displayMetrics.density,paint)}
        if(isShown&&windowVisibility==VISIBLE)postInvalidateDelayed(33)
    }
}

/** Same icon language as the existing thin-line folder and sidebar controls. */
class ShowcaseIcon(context:Context,var folder:Boolean=false):View(context){
    private val paint=Paint(Paint.ANTI_ALIAS_FLAG)
    var backArrow=false
        set(value){field=value;invalidate()}
    init{isClickable=true;isFocusable=true;contentDescription=if(folder)"导入游戏" else "菜单"}
    override fun onDraw(c:Canvas){val d=resources.displayMetrics.density;val cx=width/2f;val cy=height/2f
        paint.style=Paint.Style.FILL;paint.color=if(isPressed)0x66505D50 else 0xB32D3731.toInt();c.drawRoundRect(cx-19*d,cy-19*d,cx+19*d,cy+19*d,10*d,10*d,paint)
        paint.color=0xFFD1D8C8.toInt();paint.style=Paint.Style.STROKE;paint.strokeWidth=1.5f*d;paint.strokeCap=Paint.Cap.ROUND;paint.strokeJoin=Paint.Join.ROUND
        if(folder){val p=Path().apply{moveTo(cx-10*d,cy+9*d);lineTo(cx-10*d,cy-9*d);lineTo(cx-2*d,cy-9*d);lineTo(cx+2*d,cy-5*d);lineTo(cx+10*d,cy-5*d);lineTo(cx+10*d,cy+9*d);close()};c.drawPath(p,paint);c.drawLine(cx-10*d,cy-5*d,cx+2*d,cy-5*d,paint);c.drawLine(cx,cy-1*d,cx,cy+6*d,paint);c.drawLine(cx-3.5f*d,cy+2.5f*d,cx+3.5f*d,cy+2.5f*d,paint)}
        else if(backArrow){c.drawPath(Path().apply{moveTo(cx+3*d,cy-8*d);lineTo(cx-5*d,cy);lineTo(cx+3*d,cy+8*d)},paint)}
        else{c.drawRoundRect(cx-9*d,cy-8*d,cx+8*d,cy+8*d,2*d,2*d,paint);c.drawLine(cx-3*d,cy-8*d,cx-3*d,cy+8*d,paint);c.drawLine(cx-7*d,cy-3*d,cx-5*d,cy-3*d,paint)}
    }
}

class ShowcasePages(context:Context):View(context){
    private val paint=Paint(Paint.ANTI_ALIAS_FLAG)
    var count=0
    var selected=0
    var onSelect:((Int)->Unit)?=null
    private val d get()=resources.displayMetrics.density
    init{isClickable=true;isFocusable=true;importantForAccessibility=IMPORTANT_FOR_ACCESSIBILITY_YES}
    private var dragFirst:Int?=null
    private var dragRequested:Int?=null
    private fun first()=(selected-4).coerceIn(0,max(0,count-9))
    private fun visibleCount()=min(9,count)
    override fun onDraw(c:Canvas){val n=visibleCount();val step=18*d;val left=(width-(n-1)*step)/2
        for(i in 0 until n){paint.color=if(first()+i==selected)0xFFE1C681.toInt() else 0xFF59635B.toInt();c.drawCircle(left+i*step,height/2f,3*d,paint)}}
    override fun onTouchEvent(e:MotionEvent):Boolean{if(count<2)return false
        when(e.actionMasked){
            MotionEvent.ACTION_DOWN->{dragFirst=first();dragRequested=null;parent?.requestDisallowInterceptTouchEvent(true)}
            MotionEvent.ACTION_MOVE->if(dragFirst==null)return false
            MotionEvent.ACTION_UP->{dragFirst=null;dragRequested=null;parent?.requestDisallowInterceptTouchEvent(false);performClick();return true}
            MotionEvent.ACTION_CANCEL->{dragFirst=null;dragRequested=null;parent?.requestDisallowInterceptTouchEvent(false);return true}
            else->return false
        }
        // Keep the dot-to-page mapping fixed until the finger lifts. Recentring
        // the nine-dot window after each selection otherwise jumps through pages.
        val n=visibleCount();val left=(width-(n-1)*18*d)/2
        val index=(round((e.x-left)/(18*d)).toInt().coerceIn(0,n-1)+dragFirst!!).coerceIn(0,count-1)
        if(index!=dragRequested){dragRequested=index;if(index!=selected)onSelect?.invoke(index)}
        return true
    }
    override fun performClick():Boolean{super.performClick();return true}
    fun update(total:Int,index:Int){count=total;selected=index;visibility=if(total>1)VISIBLE else GONE;contentDescription="第 ${index+1} 页，共 $total 页";invalidate()}
    override fun onInitializeAccessibilityNodeInfo(info:AccessibilityNodeInfo){super.onInitializeAccessibilityNodeInfo(info);info.className="android.widget.SeekBar";info.rangeInfo=AccessibilityNodeInfo.RangeInfo.obtain(AccessibilityNodeInfo.RangeInfo.RANGE_TYPE_INT,0f,max(0,count-1).toFloat(),selected.toFloat());info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_FORWARD);info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_BACKWARD)}
    override fun performAccessibilityAction(action:Int,arguments:Bundle?):Boolean{val delta=when(action){AccessibilityNodeInfo.ACTION_SCROLL_FORWARD->1;AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD->-1;else->return super.performAccessibilityAction(action,arguments)};onSelect?.invoke((selected+delta).coerceIn(0,max(0,count-1)));return true}
}
