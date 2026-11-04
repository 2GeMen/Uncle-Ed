package org.uncleed.app
import org.junit.Assert.*
import org.junit.Test
class InputTests {
 @Test fun multiTouchReleasePreservesOtherFinger(){val s=InputState();s.replace(1,setOf(4,7));s.replace(2,setOf(0));s.release(1);assertEquals(setOf(0),s.held());s.clear();assertEquals(0,s.mask())}
 @Test fun traversalRejected(){listOf("../x.gba","/x.gba","a/../../x.gba","C:x.gba","a\\x.gba").forEach{assertFalse(Motion.validZipPath(it))};assertTrue(Motion.validZipPath("games/test.gba"))}
 @Test fun swipeCannotSkip(){assertEquals(2,Motion.clampPage(1,20,5));assertEquals(0,Motion.clampPage(0,-1,5))}
 @Test fun fixedAxesAndDiagonal(){assertEquals(setOf(4,7),Motion.dpad(1f,-1f));assertEquals("portrait",Motion.originalForm(Machine.GBC));assertEquals("landscape",Motion.originalForm(Machine.PSP))}
 @Test fun titleRemovesRegionWithoutTruncating(){assertEquals("Example Game",Motion.gameTitle("Example Game (USA) [Rev 1].gba"))}
 @Test fun decodedBudgetIncludesUnknownEntrySizes(){val budget=DecodeBudget(10);budget.add(6);try{budget.add(5);fail("Must reject inflated data above limit")}catch(_:IllegalStateException){};assertEquals(6L,budget.used)}
 @Test fun stickRoundGatePreservesDirectionOutsideCapture(){val axis=Motion.stick(3f,4f);assertEquals(.6f,axis.first,.0001f);assertEquals(.8f,axis.second,.0001f);assertEquals(.25f,Motion.stick(.25f,0f).first,0f);assertEquals(0f,Motion.stick(0f,0f).second,0f)}
 @Test fun phoneHasOnlyThree(){assertEquals(listOf(Machine.GBA,Machine.GBC,Machine.PSP),Machine.available(false))}
}
