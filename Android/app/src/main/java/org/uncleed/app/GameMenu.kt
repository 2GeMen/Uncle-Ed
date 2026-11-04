// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import android.content.Context
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.widget.*

/** Upper-left drawer; controls use the same model transform as physical input projection. */
class GameMenu(context:Context,scale:Float,x:Float,y:Float,onDisplay:(Float,Float,Float)->Unit,onResume:()->Unit,onShelf:()->Unit,onMachines:()->Unit,haptics:Boolean=true,onHaptics:(Boolean)->Unit={},bookMode:Boolean?=null,onBook:()->Unit={},onState:((Boolean,Int)->Unit)?=null):FrameLayout(context){
 private lateinit var panel:ScrollView
 override fun onSizeChanged(w:Int,h:Int,oldw:Int,oldh:Int){super.onSizeChanged(w,h,oldw,oldh);if(::panel.isInitialized){val p=panel.layoutParams;p.width=minOf(dp(350),(w*.84f).toInt());panel.layoutParams=p}}
 private fun dp(v:Int)=(v*resources.displayMetrics.density).toInt()
 init{
  setBackgroundColor(0x88000000.toInt());setOnClickListener{onResume()}
  val scroll=ScrollView(context).apply{setBackgroundColor(Color.rgb(31,40,35));isFillViewport=true;setOnClickListener{}}
  panel=scroll
  val body=LinearLayout(context).apply{orientation=LinearLayout.VERTICAL;setPadding(dp(22),dp(24),dp(22),dp(20))};scroll.addView(body)
  val panelWidth=minOf(dp(350),(resources.displayMetrics.widthPixels*.84).toInt());addView(scroll,LayoutParams(panelWidth,-1,Gravity.START))
  fun label(value:String,size:Float=14f){body.addView(TextView(context).apply{text=value;textSize=size;setTextColor(0xFFEAE6D7.toInt());setPadding(0,dp(8),0,dp(6))})}
  fun action(value:String,callback:()->Unit){body.addView(Button(context).apply{text=value;isAllCaps=false;setTextColor(0xFFEAE6D7.toInt());minHeight=dp(48);background=android.graphics.drawable.GradientDrawable().apply{setColor(0xFF39453C.toInt());cornerRadius=dp(12).toFloat()};setOnClickListener{callback()}},LinearLayout.LayoutParams(-1,dp(48)).apply{bottomMargin=dp(10)})}
  label("Uncle Ed.",22f);label("经典再次上场",12f);action("继续游戏",onResume)
  if(onState!=null){label("随时存，随时接着玩");action("存下此刻"){onState(false,0)};action("恢复手动存档"){onState(true,0)};action("继续上次离开"){onState(true,1)}}
  var size=scale;var horizontal=x;var vertical=y
  fun slider(title:String,max:Int,initial:Int,update:(Int)->Unit){label(title);body.addView(SeekBar(context).apply{this.max=max;progress=initial;setOnSeekBarChangeListener(object:SeekBar.OnSeekBarChangeListener{override fun onProgressChanged(v:SeekBar?,p:Int,user:Boolean){if(user){update(p);onDisplay(size,horizontal,vertical)}};override fun onStartTrackingTouch(v:SeekBar?){};override fun onStopTrackingTouch(v:SeekBar?){} })},LinearLayout.LayoutParams(-1,dp(42)))}
  slider("机身大小",35,((scale-.7f)*100).toInt().coerceIn(0,35)){size=.7f+it/100f}
  slider("左右位置",200,((x+1)*100).toInt().coerceIn(0,200)){horizontal=it/100f-1}
  slider("上下位置",200,((y+1)*100).toInt().coerceIn(0,200)){vertical=it/100f-1}
  body.addView(Switch(context).apply{text="按键触感";setTextColor(0xFFEAE6D7.toInt());isChecked=haptics;minHeight=dp(48);setOnCheckedChangeListener{_,value->onHaptics(value)}})
  if(bookMode!=null)action(if(bookMode)"恢复双屏握法" else "切换书本握法",onBook)
  action("恢复默认显示"){size=1f;horizontal=0f;vertical=0f;onDisplay(size,horizontal,vertical);onResume()}
  action("保存并返回收藏",onShelf);action("保存并选择掌机",onMachines)
 }
}
