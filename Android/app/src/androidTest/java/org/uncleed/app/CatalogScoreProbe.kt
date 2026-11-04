// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import android.app.Instrumentation
import android.os.Bundle
import org.json.JSONArray
import org.json.JSONObject

/** No activity, ROM, network service or HTTP client. Only generated colour fixtures use the app cache. */
fun runCatalogScoreProbe(probe:Instrumentation){val result=Bundle()
 try{
  fun fixture(platform:String,max:Int=100,count:Int=12):String{
   val pool=JSONArray().put(JSONObject().put("title",1).put("platforms",2)).put("Fixture Game").put(JSONArray().put(3))
    .put(JSONObject().put("name",4).put("criticScoreSummary",5)).put(platform)
    .put(JSONObject().put("max",6).put("score",7).put("reviewCount",8)).put(max).put(88).put(count)
   return "<script id=\"__NUXT_DATA__\">$pool</script>"
  }
  check(CatalogScore.parse(fixture("Game Boy Advance"),Machine.GBA,"Fixture Game")?.getInt("metacritic")==88)
  check(CatalogScore.parse(fixture("PSP"),Machine.GBA,"Fixture Game")==null)
  check(CatalogScore.parse(fixture("Game Boy Advance",10),Machine.GBA,"Fixture Game")==null)
  check(CatalogScore.parse(fixture("Game Boy Advance",100,0),Machine.GBA,"Fixture Game")==null)
  check(CatalogScore.parse(fixture("Game Boy Advance"),Machine.GBA,"Another Game")==null)
  check(CatalogScore.parse(fixture("Game Boy Advance"),Machine.GBA,"Fixture Game (Demo)")==null)
  val bitmap=android.graphics.Bitmap.createBitmap(400,600,android.graphics.Bitmap.Config.ARGB_8888)
  val canvas=android.graphics.Canvas(bitmap);val paint=android.graphics.Paint()
  for((rect,color) in listOf(android.graphics.Rect(0,0,200,300) to android.graphics.Color.RED,android.graphics.Rect(200,0,400,300) to android.graphics.Color.GREEN,android.graphics.Rect(0,300,200,600) to android.graphics.Color.BLUE,android.graphics.Rect(200,300,400,600) to android.graphics.Color.YELLOW)){paint.color=color;canvas.drawRect(rect,paint)}
  val file=java.io.File.createTempFile("catalog-colors-",".png",probe.targetContext.cacheDir);file.outputStream().use{bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};bitmap.recycle()
  try{val pixels=CoverArt.prepare(Game("fixture",Machine.GBA,"Fixture","fixture.gba"),file);check(pixels.matched&&pixels.width==600&&pixels.height in 279..281)
   fun rgb(x:Int,y:Int)=((pixels.rgba.get((y*pixels.width+x)*4).toInt() and 255) shl 16) or ((pixels.rgba.get((y*pixels.width+x)*4+1).toInt() and 255) shl 8) or (pixels.rgba.get((y*pixels.width+x)*4+2).toInt() and 255)
   check(rgb(5,5)==0xFF0000&&rgb(595,5)==0x00FF00&&rgb(5,pixels.height-5)==0x0000FF){"Artwork crop, channel or orientation mismatch"}
   val disc=CoverArt.prepare(Game("disc",Machine.PSP,"Fixture","fixture.iso"),file)
   fun alpha(x:Int,y:Int)=disc.rgba.get((y*disc.width+x)*4+3).toInt() and 255
   check(alpha(0,0)==0&&alpha(disc.width-1,0)==0&&alpha(disc.width/2,disc.height/2)==255){"UMD print must stay inside its circular label"}
  }finally{file.delete()}
  result.putString("result","PASS: offline critic-score fixtures reject wrong platform, user-scale, missing reviews, wrong title and demo; RGBA crop and circular UMD print mask");probe.finish(-1,result)
 }catch(e:Throwable){result.putString("error",e.toString());probe.finish(0,result)}
}
