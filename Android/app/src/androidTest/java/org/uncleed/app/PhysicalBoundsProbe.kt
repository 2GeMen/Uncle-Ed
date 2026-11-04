// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import java.nio.ByteBuffer
import java.nio.ByteOrder
import android.app.Instrumentation
import android.os.Bundle
private fun boundsGlb(text:String):ByteBuffer{val bytes=text.toByteArray();return ByteBuffer.allocateDirect(20+bytes.size).order(ByteOrder.LITTLE_ENDIAN).apply{putInt(0x46546c67);putInt(2);putInt(capacity());putInt(bytes.size);putInt(0x4e4f534a);put(bytes);flip()}}
fun runPhysicalBoundsProbe(probe:Instrumentation){val result=Bundle();try{
 val b=NeighbourModel.bounds(boundsGlb("""{"extras":{"uncleedPhysicalBounds":{"min":[-2,-1,-0.5],"max":[2,3,0.5]}}}"""))!!
 check(b.center.contentEquals(floatArrayOf(0f,1f,0f)));check(b.halfExtent.contentEquals(floatArrayOf(2f,2f,.5f)))
 check(NeighbourModel.bounds(boundsGlb("""{"asset":{"version":"2.0"}}"""))==null)
 var rejected=false;try{NeighbourModel.bounds(boundsGlb("""{"extras":{"uncleedPhysicalBounds":{"min":[2,-1,-0.5],"max":[-2,3,0.5]}}}"""))}catch(_:IllegalStateException){rejected=true};check(rejected)
 result.putString("result","PASS: real Android JSON physical bounds, legacy fallback and invalid bounds rejection");probe.finish(-1,result)
 }catch(e:Throwable){result.putString("error",e.toString());probe.finish(0,result)}}
