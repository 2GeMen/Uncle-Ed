// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app

import android.app.Instrumentation
import android.os.Bundle
import android.view.MotionEvent

/** Exercises the actual view while selections immediately update its dot window. */
fun runPaginationProbe(probe:Instrumentation){
 val result=Bundle()
 try{
  probe.runOnMainSync{
   val view=ShowcasePages(probe.targetContext);val d=probe.targetContext.resources.displayMetrics.density
   view.layout(0,0,(300*d).toInt(),(48*d).toInt());view.update(20,10)
   val selected=mutableListOf<Int>();view.onSelect={selected.add(it);view.update(20,it)}
   val center=view.width/2f;val y=view.height/2f
   fun event(action:Int,x:Float){val e=MotionEvent.obtain(100,110,action,x,y,0);check(view.onTouchEvent(e));e.recycle()}
   event(MotionEvent.ACTION_DOWN,center)
   repeat(8){event(MotionEvent.ACTION_MOVE,center+18*d)}
   check(selected==listOf(11)){"Holding one dot drifted: $selected"}
   event(MotionEvent.ACTION_MOVE,view.width*2f)
   check(selected==listOf(11,14)){"Drag escaped the original nine-dot window: $selected"}
   event(MotionEvent.ACTION_UP,view.width*2f)
   event(MotionEvent.ACTION_DOWN,center);event(MotionEvent.ACTION_CANCEL,center)
   val before=selected.toList();val e=MotionEvent.obtain(100,110,MotionEvent.ACTION_MOVE,0f,y,0)
   check(!view.onTouchEvent(e));e.recycle();check(selected==before)
  }
  result.putString("result","PASS: fixed drag mapping, duplicate suppression, bounds and cancel")
  probe.finish(-1,result)
 }catch(e:Throwable){result.putString("error",e.toString());probe.finish(0,result)}
}
