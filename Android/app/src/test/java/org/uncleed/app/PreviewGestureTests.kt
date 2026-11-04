// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import org.junit.Assert.*
import org.junit.Test
class PreviewGestureTests {
 private fun gesture()=PreviewGesture(8f,40f)
 @Test fun slowSwipeNeverTurnsIntoRotation(){val g=gesture();g.down(0f,0f,0);g.move(20f,1f,80);g.hold(210);g.move(100f,1f,500);assertEquals(PreviewGesture.Intent.SWIPE,g.intent);assertEquals(2,g.up(100f,1f,600))}
 @Test fun stationaryHoldCannotConfirm(){val g=gesture();g.down(0f,0f,0);assertTrue(g.hold(200));assertEquals(0,g.up(0f,0f,400))}
 @Test fun holdThenDragRotates(){val g=gesture();g.down(10f,10f,0);g.hold(210);assertEquals(Pair(40f,20f),g.move(50f,30f,250));assertEquals(0,g.up(50f,30f,300))}
 @Test fun tapConfirmsOnlyOnce(){val g=gesture();g.down(10f,10f,0);assertEquals(1,g.up(11f,10f,90));assertEquals(0,g.up(11f,10f,100))}
 @Test fun verticalDragDoesNotConfirmOrRotate(){val g=gesture();g.down(0f,0f,0);g.move(2f,30f,60);g.hold(300);assertEquals(PreviewGesture.Intent.CANCELLED,g.intent);assertEquals(0,g.up(2f,40f,500))}
 @Test fun secondPointerAndRebaseAvoidJump(){val g=gesture();g.down(10f,10f,0);g.twoFingers();g.rebase(100f,100f);assertEquals(Pair(2f,3f),g.move(102f,103f,70));g.cancel();assertEquals(0,g.up(102f,103f,100))}
}
