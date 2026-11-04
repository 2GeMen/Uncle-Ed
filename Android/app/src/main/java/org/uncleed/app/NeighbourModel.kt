// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.json.JSONObject

/** Keep the binary and alpha textures byte-identical; tint material instances only. */
object NeighbourModel {
 data class Bounds(val center:FloatArray,val halfExtent:FloatArray)
 data class Prepared(val buffer:ByteBuffer,val pigment:Map<String,FloatArray>,val sha:String,val bounds:Bounds?=null)
 fun bounds(buffer:ByteBuffer):Bounds? {
  val data=buffer.duplicate().order(ByteOrder.LITTLE_ENDIAN);val text=ByteArray(data.getInt(12));data.position(20);data.get(text)
  val b=JSONObject(String(text,Charsets.UTF_8)).optJSONObject("extras")?.optJSONObject("uncleedPhysicalBounds")?:return null
  val lo=b.getJSONArray("min");val hi=b.getJSONArray("max")
  val center=FloatArray(3){((lo.getDouble(it)+hi.getDouble(it))/2).toFloat()};val half=FloatArray(3){((hi.getDouble(it)-lo.getDouble(it))/2).toFloat()}
  check(center.all{it.isFinite()}&&half.all{it.isFinite()&&it>0}){"Invalid physical model bounds"}
  return Bounds(center,half)
 }
 fun pigments(buffer:ByteBuffer):Map<String,FloatArray> {
  val original=buffer.duplicate().order(ByteOrder.LITTLE_ENDIAN)
  check(original.getInt(0)==0x46546C67&&original.getInt(4)==2)
  val text=ByteArray(original.getInt(12));original.position(20);original.get(text)
  val json=JSONObject(String(text,Charsets.UTF_8));val colors=mutableMapOf<String,FloatArray>()
  json.optJSONArray("materials")?.let{materials->for(i in 0 until materials.length()){
   val m=materials.getJSONObject(i);val c=m.optJSONObject("pbrMetallicRoughness")?.optJSONArray("baseColorFactor")
   colors[m.optString("name")]=FloatArray(4){index->(c?.optDouble(index,1.0)?:1.0).toFloat()}
  }}
  return colors
 }
 fun buffer(bytes:ByteArray):Prepared {
  val buffer=ByteBuffer.allocateDirect(bytes.size).apply{put(bytes);flip()}
  val sha=java.security.MessageDigest.getInstance("SHA-256").digest(bytes).joinToString(""){"%02x".format(it)}
  return Prepared(buffer,pigments(buffer),sha,bounds(buffer))
 }
}
