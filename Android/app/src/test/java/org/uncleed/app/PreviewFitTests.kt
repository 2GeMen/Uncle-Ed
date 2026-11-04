// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import org.junit.Assert.*
import org.junit.Test
class PreviewFitTests {
 @Test fun fitsOwnModelInsteadOfTallNeighbour(){val gba=PreviewFit.scale(3.3f,1.8f,3f,false);val gbc=PreviewFit.scale(1.9f,3.2f,3f,false);assertEquals(.84f,1.8f*gba,.0001f);assertEquals(.84f,3.2f*gbc,.0001f);assertTrue(gba>gbc)}
 @Test fun narrowAndTabletKeepAspectAndBounds(){for(aspect in listOf(.6f,1f,3f))for(tablet in listOf(false,true)){val q=PreviewFit.scale(3.3f,1.8f,aspect,tablet);assertTrue(q>0);assertTrue(q*3.3f<=aspect*(if(tablet).9f else .76f)+.0001f);assertTrue(q*1.8f<=(if(tablet).8f else .84f)+.0001f)}}
}
