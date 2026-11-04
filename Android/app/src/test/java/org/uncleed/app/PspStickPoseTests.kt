// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import org.junit.Assert.*
import org.junit.Test
class PspStickPoseTests {
 private fun rest()=floatArrayOf(1f,0f,0f,0f,0f,0f,1f,0f,0f,-1f,0f,0f,2f,3f,4f,1f)
 @Test fun matchesSceneKitOracle(){val m=PspStickPose.apply(rest(),1f,1f);val expected=floatArrayOf(.98722726f,0f,-.15931821f,0f,.15728329f,-.1593181f,.9746177f,0f,-.025382275f,-.9872273f,-.15728317f,0f,2.18f,2.82f,4f,1f);assertArrayEquals(expected,m,.000001f)}
 @Test fun releaseRestoresRestAndPreservesScale(){val r=rest();for(i in 0..2)r[i]*=2;for(i in 4..6)r[i]*=3;for(i in 8..10)r[i]*=4;assertArrayEquals(r,PspStickPose.apply(r,0f,0f),.000001f)}
}
