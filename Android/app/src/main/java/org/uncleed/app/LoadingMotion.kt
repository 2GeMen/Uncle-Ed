// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import kotlin.math.*

/** Port of the shared PickerMotion.swift phase timings. Time is never frame-count based. */
object LoadingMotion {
 fun duration(machine:Machine)=if(machine==Machine.PSP)2.95 else 1.65
 fun ease(x:Double):Float{val t=x.coerceIn(0.0,1.0);return (t*t*t*(t*(t*6-15)+10)).toFloat()}
 fun door(t:Double)=1.18f*ease(t/.18)*(1-ease((t-.68)/.16))
 fun spin(t:Double):Float{val p=((t-.86)/.14).coerceIn(0.0,1.0);return (12*PI*p*p).toFloat()}
 fun events(machine:Machine,t:Double):List<String> = (if(machine==Machine.PSP)listOf(0.0 to "psp-door-open",.65 to "psp-disc-seat",.84 to "psp-door-close",.88 to "psp-disc-read")else listOf(0.0 to "media-slide",.85 to "media-latch")).filter{t>=it.first}.map{it.second}
 fun seat(machine:Machine,height:Float)= -height*(if(machine==Machine.GBC).5f else .49f)
 /** Unit quaternion in xyzw order, extracted from a uniformly scaled world matrix. */
 fun quaternion(m:FloatArray):FloatArray {
  val q=sqrt(m[0]*m[0]+m[1]*m[1]+m[2]*m[2]);val a=FloatArray(16){m[it]/q};val trace=a[0]+a[5]+a[10]
  val r=when {
   trace>0->{val s=sqrt(trace+1)*2;floatArrayOf((a[6]-a[9])/s,(a[8]-a[2])/s,(a[1]-a[4])/s,s/4)}
   a[0]>a[5]&&a[0]>a[10]->{val s=sqrt(1+a[0]-a[5]-a[10])*2;floatArrayOf(s/4,(a[4]+a[1])/s,(a[8]+a[2])/s,(a[6]-a[9])/s)}
   a[5]>a[10]->{val s=sqrt(1+a[5]-a[0]-a[10])*2;floatArrayOf((a[4]+a[1])/s,s/4,(a[9]+a[6])/s,(a[8]-a[2])/s)}
   else->{val s=sqrt(1+a[10]-a[0]-a[5])*2;floatArrayOf((a[8]+a[2])/s,(a[9]+a[6])/s,s/4,(a[1]-a[4])/s)}
  };return r
 }
 fun slerp(a:FloatArray,b:FloatArray,t:Float):FloatArray{var dot=a.indices.sumOf{(a[it]*b[it]).toDouble()}.toFloat();val end=if(dot<0){dot= -dot;FloatArray(4){-b[it]}}else b
  val r=if(dot>.9995f)FloatArray(4){a[it]+(end[it]-a[it])*t}else{val angle=acos(dot.coerceIn(-1f,1f));val s=sin(angle);FloatArray(4){(a[it]*sin((1-t)*angle)+end[it]*sin(t*angle))/s}}
  val n=sqrt(r.sumOf{(it*it).toDouble()}).toFloat();return FloatArray(4){r[it]/n}
 }
 fun matrix(q:FloatArray,scale:Float,x:Float,y:Float,z:Float):FloatArray{val (a,b,c,d)=q;return floatArrayOf((1-2*b*b-2*c*c)*scale,(2*a*b+2*c*d)*scale,(2*a*c-2*b*d)*scale,0f,(2*a*b-2*c*d)*scale,(1-2*a*a-2*c*c)*scale,(2*b*c+2*a*d)*scale,0f,(2*a*c+2*b*d)*scale,(2*b*c-2*a*d)*scale,(1-2*a*a-2*b*b)*scale,0f,x,y,z,1f)}
}
