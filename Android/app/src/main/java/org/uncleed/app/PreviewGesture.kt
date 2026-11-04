// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app

import kotlin.math.abs
import kotlin.math.hypot

/** One pointer sequence owns one intent. A committed swipe never becomes a hold. */
class PreviewGesture(private val slop:Float,private val pageDistance:Float) {
 enum class Intent { NONE, PRESS, SWIPE, ROTATE, CANCELLED }
 var intent=Intent.NONE;private set
 private var startX=0f;private var startY=0f;private var lastX=0f;private var lastY=0f;private var began=0L
 fun down(x:Float,y:Float,time:Long){startX=x;startY=y;lastX=x;lastY=y;began=time;intent=Intent.PRESS}
 fun hold(time:Long):Boolean {if(intent==Intent.PRESS&&time-began>=200){intent=Intent.ROTATE;return true};return false}
 fun twoFingers(){if(intent!=Intent.NONE)intent=Intent.ROTATE}
 fun rebase(x:Float,y:Float){lastX=x;lastY=y}
 fun move(x:Float,y:Float,time:Long):Pair<Float,Float>{
  if(intent==Intent.PRESS){
   if(time-began>=200)hold(time)
   else if(hypot(x-startX,y-startY)>slop)intent=if(abs(x-startX)>abs(y-startY))Intent.SWIPE else Intent.CANCELLED
  }
  val delta=if(intent==Intent.ROTATE)Pair(x-lastX,y-lastY) else Pair(0f,0f);lastX=x;lastY=y;return delta
 }
 /** 0: none, 1: confirm, 2: previous page, 3: next page. */
 fun up(x:Float,y:Float,time:Long):Int {
  val action=when {
   intent==Intent.PRESS&&time-began<200&&hypot(x-startX,y-startY)<=slop->1
   intent==Intent.SWIPE&&abs(x-startX)>=pageDistance->if(x>startX)2 else 3
   else->0
  };cancel();return action
 }
 fun cancel(){intent=Intent.NONE}
}
