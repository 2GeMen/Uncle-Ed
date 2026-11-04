// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import kotlin.math.*

/** SceneKit Euler (pi/2 + axisY*0.16, axisX*0.16, 0), in parent space. */
internal object PspStickPose {
 fun apply(rest:FloatArray,x:Float,y:Float):FloatArray {
  val a=PI.toFloat()/2+y*.16f;val b=x*.16f;val sa=sin(a);val ca=cos(a);val sb=sin(b);val cb=cos(b)
  fun scale(i:Int)=sqrt(rest[i]*rest[i]+rest[i+1]*rest[i+1]+rest[i+2]*rest[i+2])
  val sx=scale(0);val sy=scale(4);val sz=scale(8)
  return floatArrayOf(cb*sx,0f,-sb*sx,0f,sb*sa*sy,ca*sy,cb*sa*sy,0f,sb*ca*sz,-sa*sz,cb*ca*sz,0f,rest[12]+x*.18f,rest[13]-y*.18f,rest[14],1f)
 }
}
