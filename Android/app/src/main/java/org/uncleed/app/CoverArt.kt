// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import android.graphics.*
import java.io.File
import java.nio.ByteBuffer

object CoverArt {
 data class Pixels(val id:String,val width:Int,val height:Int,val rgba:ByteBuffer,val matched:Boolean,val shellColor:FloatArray)
 private fun dominant(source:Bitmap):Int {
  val small=Bitmap.createScaledBitmap(source,48,48,true);val pixels=IntArray(48*48);small.getPixels(pixels,0,48,0,0,48,48);if(small!==source)small.recycle()
  val all=Array(512){IntArray(4)};val color=Array(512){IntArray(4)};var count=0
  for(pixel in pixels){if((pixel ushr 24)<=127)continue;val r=(pixel shr 16) and 255;val g=(pixel shr 8) and 255;val b=pixel and 255;val index=(r shr 5)*64+(g shr 5)*8+(b shr 5)
   fun add(bin:IntArray){bin[0]++;bin[1]+=r;bin[2]+=g;bin[3]+=b};add(all[index]);val hi=maxOf(r,g,b);val lo=minOf(r,g,b);if(hi>45&&(hi-lo).toFloat()/hi>.25f){add(color[index]);count++}}
  val best=(if(count>48*48/8)color else all).maxBy{it[0]};if(best[0]==0)return 0x67766B
  return (best[1]/best[0] shl 16) or (best[2]/best[0] shl 8) or (best[3]/best[0])
 }
 /** Existing box-art fallback: at most 12% lower-edge crop, preserving the title, then fill the sticker. */
 fun prepare(game:Game,file:File?):Pixels {
  val aspect=when(game.machine){Machine.GBA->2.142857f;Machine.GBC->1.0895238f;Machine.NDS,Machine.N3DS->1.1459f;Machine.PSP->1f}
  val w=600;val h=(w/aspect).toInt();val bitmap=Bitmap.createBitmap(w,h,Bitmap.Config.ARGB_8888);val canvas=Canvas(bitmap)
  canvas.drawColor(Color.rgb(37,49,43));var matched=false;var tint=0x67766B
  if(file!=null){
   val bounds=BitmapFactory.Options().apply{inJustDecodeBounds=true};BitmapFactory.decodeFile(file.path,bounds)
   var sample=1;while(maxOf(bounds.outWidth,bounds.outHeight)/sample>1600)sample*=2
   BitmapFactory.decodeFile(file.path,BitmapFactory.Options().apply{inSampleSize=sample;inPreferredConfig=Bitmap.Config.ARGB_8888})?.let{art->
    val spine=if(game.machine==Machine.GBA&&art.width.toFloat()/art.height in .9f..1.35f).18f else 0f
    val fraction=if(game.machine==Machine.GBA)minOf(.12f,maxOf(0f,(1-(art.width*(1-spine)/art.height)/aspect)/2))else 0f
    tint=dominant(art)
    val src=Rect((art.width*spine).toInt(),0,art.width,(art.height*(1-fraction)).toInt())
    canvas.drawBitmap(art,src,Rect(0,0,w,h),Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG));art.recycle();matched=true
   }
  }
  if(!matched){val p=Paint(Paint.ANTI_ALIAS_FLAG).apply{color=0xFFD8D7C4.toInt();textAlign=Paint.Align.CENTER;textSize=28f};canvas.drawText("暂无封面",w/2f,h/2f,p);p.textSize=16f;canvas.drawText(game.machine.label,w/2f,h/2f+32,p)}
  val colors=IntArray(w*h);bitmap.getPixels(colors,0,w,0,0,w,h);bitmap.recycle();val buffer=ByteBuffer.allocateDirect(w*h*4)
  for((index,c) in colors.withIndex()){
   val dx=(index%w+.5f)/w-.5f;val dy=(index/w+.5f)/h-.5f
   val alpha=if(game.machine==Machine.PSP&&dx*dx+dy*dy>.25f)0 else 255
   buffer.put((c shr 16).toByte());buffer.put((c shr 8).toByte());buffer.put(c.toByte());buffer.put(alpha.toByte())
  };buffer.flip()
  val peak=maxOf((tint shr 16) and 255,(tint shr 8) and 255,tint and 255)/255f;val energy=minOf(1f,.78f/maxOf(.001f,peak))
  val shell=FloatArray(3){i->val v=((tint shr ((2-i)*8)) and 255)/255f*energy;if(v<=.04045f)v/12.92f else Math.pow(((v+.055f)/1.055f).toDouble(),2.4).toFloat()}
  return Pixels(game.id,w,h,buffer,matched,shell)
 }
}
