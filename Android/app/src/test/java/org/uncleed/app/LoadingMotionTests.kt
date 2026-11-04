// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import org.junit.Assert.*
import org.junit.Test
class LoadingMotionTests {
 @Test fun doorClosesBeforeRead(){assertEquals(0f,LoadingMotion.door(0.0),.0001f);assertEquals(1.18f,LoadingMotion.door(.5),.0001f);assertEquals(0f,LoadingMotion.door(.84),.0001f);assertEquals(0f,LoadingMotion.spin(.86),.0001f);assertTrue(LoadingMotion.spin(.9)>0)}
 @Test fun delayedFrameIncludesAllEventsInOrder(){assertEquals(listOf("psp-door-open","psp-disc-seat","psp-door-close","psp-disc-read"),LoadingMotion.events(Machine.PSP,1.0))}
 @Test fun gbcIsFlush(){assertEquals(-1.5f,LoadingMotion.seat(Machine.GBC,3f),0f);assertEquals(-1.47f,LoadingMotion.seat(Machine.GBA,3f),.0001f)}
 @Test fun halfTurnRemainsRigid(){val a=floatArrayOf(0f,0f,0f,1f);val b=floatArrayOf(0f,1f,0f,0f);val q=LoadingMotion.slerp(a,b,.5f);val m=LoadingMotion.matrix(q,1f,0f,0f,0f);assertEquals(1f,(m[0]*m[0]+m[1]*m[1]+m[2]*m[2]),.0001f);assertEquals(1f,kotlin.math.abs(m[2]),.0001f)}
}
