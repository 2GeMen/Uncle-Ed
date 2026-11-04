// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app

import android.app.*
import android.content.*
import android.content.pm.ActivityInfo
import android.graphics.Color
import android.os.*
import android.provider.OpenableColumns
import android.view.*
import android.widget.*
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.Executors
import kotlin.math.*

class MainActivity:Activity() {
    private enum class Stage { MACHINE,THEME,MEDIA,INSERTING,PLAYING }
    private var stage=Stage.MACHINE
    private lateinit var scene:MachineSurface
    private lateinit var rim:RimOverlay
    private lateinit var root:FrameLayout
    private lateinit var title:TextView
    private lateinit var detail:TextView
    private lateinit var dots:ShowcasePages
    private lateinit var backdrop:ShowcaseBackdrop
    private lateinit var logo:ImageView
    private lateinit var importButton:ShowcaseIcon
    private lateinit var header:LinearLayout
    private lateinit var primary:Button
    private lateinit var back:ShowcaseIcon
    private lateinit var library:GameLibrary
    private lateinit var gameResources:GameResources
    private lateinit var loadingAudio:LoadingAudio
    private var assemblyLayout:android.animation.ValueAnimator?=null
    private lateinit var shelfLabels:MediaShelfLabels
    private lateinit var mediaInfo:LinearLayout
    private lateinit var mediaTitle:TextView
    private lateinit var mediaCredits:TextView
    private var coverRequest=0
    private var lastCoverSignature=""
    private val io=Executors.newSingleThreadExecutor()
    private val main=Handler(Looper.getMainLooper())
    private val input=InputState()
    private val haptics by lazy{GameHaptics(this)}
    private var session:CoreSession?=null
    private var validationSaveDirectory:File?=null
    /** Instrumentation-only override; never exposed through intents or the product UI. */
    internal fun useValidationSaves(directory:File){
        check(applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0)
        check(session?.isAlive()!=true&&!launchingGame)
        validationSaveDirectory=ValidationSaves.resolve(cacheDir,directory)
    }
    private var gameMenu:GameMenu?=null
    private var menuSwipeX=0f
    private var menuSwipeOpened=false
    private var machineIndex=0
    private var mediaIndex=0
    private var theme=0
    @Volatile private var generation=0
    private var shownModel:String?=null
    private var modelLoads=0
    private var modelError=""
    private var carouselAnimation:android.animation.ValueAnimator?=null
    private var swipeStartX=0f
    private var swipeBaseOffset=0f
    private var desiredPageIndex=0
    private val carouselStage get()=stage==Stage.MACHINE||stage==Stage.THEME||stage==Stage.MEDIA
    private val carouselPage get()=when(stage){Stage.MEDIA->mediaIndex;Stage.THEME->theme;else->machineIndex}
    private val carouselLast get()=when(stage){Stage.MEDIA->games.lastIndex.coerceAtLeast(0);Stage.THEME->machine.themes.lastIndex;else->machines.lastIndex}
    private var refreshedStage:Stage?=null
    private var entryFade=false
    private val neighbourCoverSignatures=mutableMapOf<Int,String>()
    private var carouselSettling=false
    private val navigationTrace=ArrayDeque<String>()
    private fun traceNavigation(event:String){navigationTrace.addLast("${SystemClock.uptimeMillis()}:$event");while(navigationTrace.size>12)navigationTrace.removeFirst()}
    private var carouselTransaction=0
    private var carouselWaitStarted=0L
    private val carouselPump=Runnable{advanceCarousel()}
    private var busy=false
    private var launchingGame=false
    private val previewGesture by lazy{PreviewGesture(dp(8).toFloat(),dp(40).toFloat())}
    private var activePointer=-1
    private val holdPreview=Runnable{if(previewGesture.hold(SystemClock.uptimeMillis())){scene.inspecting=true;scene.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)}}
    private val touchPointers=mutableMapOf<Int,Pair<Float,Float>>()
    private val utilityPointers=mutableMapOf<Int,Int>()
    private var gameVolume=1f
    private var unmutedVolume=1f
    private val analogPointers=mutableSetOf<Int>()
    private val tablet by lazy{DeviceProfile.isTablet(this)}
    private val machines get()=Machine.available(tablet)
    private val machine get()=machines[machineIndex.coerceAtMost(machines.lastIndex)]
    private val games get()=library.snapshot().filter{it.machine==machine}
    override fun onCreate(state:Bundle?) {
        super.onCreate(state)
        library=GameLibrary(filesDir)
        theme=getPreferences(0).getInt("theme-${machine.key}",0).coerceIn(0,3)
        requestedOrientation=if(tablet)ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED else ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        window.decorView.systemUiVisibility=View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
        root=FrameLayout(this);root.isMotionEventSplittingEnabled=false;root.setBackgroundColor(Color.rgb(24,31,29));setContentView(root)
        root.setOnApplyWindowInsetsListener{view,insets->val cut=insets.displayCutout;view.setPadding(max(insets.systemWindowInsetLeft,cut?.safeInsetLeft?:0),max(insets.systemWindowInsetTop,cut?.safeInsetTop?:0),max(insets.systemWindowInsetRight,cut?.safeInsetRight?:0),insets.systemWindowInsetBottom);insets}
        backdrop=ShowcaseBackdrop(this);root.addView(backdrop,FrameLayout.LayoutParams(-1,-1))
        rim=RimOverlay(this);root.addView(rim,FrameLayout.LayoutParams(-1,-1).apply{topMargin=dp(66);bottomMargin=dp(38)})
        scene=MachineSurface(this).apply{onRimFrame={rim.update(it)}};root.addView(scene,FrameLayout.LayoutParams(-1,-1).apply{topMargin=dp(66);bottomMargin=dp(38)})
        header=LinearLayout(this).apply{orientation=LinearLayout.VERTICAL;gravity=Gravity.CENTER;setPadding(dp(54),dp(8),dp(54),0)}
        title=text(17.5f);detail=text(13.5f).apply{setTextColor(0xFFCEBC8D.toInt())};logo=ImageView(this).apply{scaleType=ImageView.ScaleType.FIT_CENTER;contentDescription="经典机型标识"}
        header.addView(title);header.addView(logo,LinearLayout.LayoutParams(dp(180),dp(36)));header.addView(detail)
        root.addView(header,FrameLayout.LayoutParams(-1,-2,Gravity.TOP))
        mediaInfo=LinearLayout(this).apply{orientation=LinearLayout.VERTICAL;gravity=Gravity.CENTER;setPadding(dp(38),0,dp(38),0)}
        mediaTitle=text(14f).apply{setTextColor(0xFFEAE6D7.toInt());maxLines=2}
        mediaCredits=text(10.5f).apply{setTextColor(0xFFAAB4A7.toInt());maxLines=3}
        mediaInfo.addView(mediaTitle);mediaInfo.addView(mediaCredits)
        mediaInfo.addOnLayoutChangeListener{_,_,_,_,_,_,_,_,_->scene.translationY=0f}
        root.addView(mediaInfo,FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM).apply{bottomMargin=dp(52)})
        shelfLabels=MediaShelfLabels(this);root.addView(shelfLabels,FrameLayout.LayoutParams(-1,-1));scene.onMediaLayout={shelfLabels.present(it,scene.top-shelfLabels.top+scene.translationY)}
        shelfLabels.onPreviewTouch={event->val forwarded=MotionEvent.obtain(event);forwarded.offsetLocation((shelfLabels.left-scene.left).toFloat(),shelfLabels.top-scene.top-scene.translationY);val used=handleTouch(forwarded);forwarded.recycle();used}
        shelfLabels.onActivate={id->val index=games.indexOfFirst{it.id==id};if(stage==Stage.MEDIA&&index>=0){if(index==mediaIndex)confirm()else selectPage(index)}}
        val footer=LinearLayout(this).apply{orientation=LinearLayout.VERTICAL;gravity=Gravity.CENTER;setPadding(dp(12),0,dp(12),0)}
        primary=button("导入游戏"){importFiles()};primary.background=android.graphics.drawable.GradientDrawable().apply{setColor(0x242E3933);cornerRadius=dp(24).toFloat();setStroke(dp(1),0x487D856F)};primary.setTextColor(0xFFEAE6D7.toInt());footer.addView(primary,LinearLayout.LayoutParams(dp(220),dp(48)))
        dots=ShowcasePages(this).apply{onSelect={selectPage(it)}};footer.addView(dots,LinearLayout.LayoutParams(dp(300),dp(48)))
        root.addView(footer,FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM))
        back=ShowcaseIcon(this).apply{setOnClickListener{if(stage==Stage.MACHINE){PopupMenu(this@MainActivity,this).apply{menu.add("导入游戏").setOnMenuItemClickListener{importFiles();true};menu.add("整理游戏库").setOnMenuItemClickListener{repairLibrary(true);true};menu.add("自动匹配封面与资料").setOnMenuItemClickListener{getSharedPreferences("resource-network-consent",0).edit().remove("approved-v1").apply();requestResourceConsent();true};show()}}else goBack()}};root.addView(back,FrameLayout.LayoutParams(dp(48),dp(48),Gravity.TOP or Gravity.START).apply{leftMargin=dp(8)})
        back.setOnTouchListener{_,e->if(stage!=Stage.PLAYING)false else when(e.actionMasked){MotionEvent.ACTION_DOWN->{menuSwipeX=e.x;menuSwipeOpened=false;false};MotionEvent.ACTION_MOVE->{if(e.x-menuSwipeX>dp(18)&&!menuSwipeOpened){menuSwipeOpened=true;showGameMenu()};menuSwipeOpened};MotionEvent.ACTION_UP->menuSwipeOpened;else->false}}
        importButton=ShowcaseIcon(this,true).apply{setOnClickListener{importFiles()}};root.addView(importButton,FrameLayout.LayoutParams(dp(48),dp(48),Gravity.TOP or Gravity.END).apply{rightMargin=dp(8)})
        scene.setOnTouchListener{_,event->handleTouch(event)}
        loadingAudio=LoadingAudio(this)
        gameResources=GameResources(this){id->if(!isFinishing&&!isDestroyed&&stage==Stage.MEDIA){refreshMediaResources();prepareNeighbours(generation)}}
        refresh()
        library.snapshot().sortedBy{if(it.machine==machine)0 else 1}.forEach{gameResources.request(it)}
        if(library.snapshot().isNotEmpty())main.post{requestResourceConsent()}
        repairLibrary(false)
    }
    internal fun showcaseDiagnostics():org.json.JSONObject {
        val location=IntArray(2);scene.getLocationOnScreen(location)
        return org.json.JSONObject(scene.diagnostics()).put("haptics",haptics.diagnostics()).put("loadingSounds",org.json.JSONArray(loadingAudio.events())).put("core",session?.diagnostics()?:org.json.JSONObject()).put("coreWorkerAlive",session?.isAlive()==true).put("validationSavesActive",validationSaveDirectory!=null).put("navigationTrace",org.json.JSONArray(navigationTrace.toList())).put("desiredPage",desiredPageIndex).put("carouselSettling",carouselSettling).put("shownModel",shownModel?:"").put("theme",theme).put("busy",busy).put("sceneAlpha",scene.alpha).put("modelLoads",modelLoads).put("modelError",modelError).put("tabletDevice",tablet).put("availableMachines",machines.size).put("axisX",scene.axisX).put("axisY",scene.axisY).put("held",org.json.JSONArray(scene.held.toList())).put("stage",stage.name).put("title",title.text.toString()).put("detail",detail.text.toString()).put("mediaTitle",mediaTitle.text.toString()).put("mediaCredits",mediaCredits.text.toString()).put("rim",org.json.JSONObject(rim.diagnostics())).put("surfaceX",location[0]).put("surfaceY",location[1]).put("surfaceWidth",scene.width).put("surfaceHeight",scene.height)
    }
    private fun dp(v:Int)=(v*resources.displayMetrics.density).roundToInt()
    private fun text(size:Float)=TextView(this).apply{setTextColor(Color.rgb(238,237,218));textSize=size;gravity=Gravity.CENTER}
    private fun button(label:String,action:()->Unit)=Button(this).apply{text=label;isAllCaps=false;minHeight=dp(48);setOnClickListener{performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);action()}}
    private fun refresh(){
        entryFade=refreshedStage!=stage
        if(entryFade){carouselTransaction++;main.removeCallbacks(carouselPump);carouselSettling=false;desiredPageIndex=carouselPage;scene.settleSide=0}
        refreshedStage=stage
        carouselAnimation?.cancel();scene.carouselOffset=0f
        main.removeCallbacks(holdPreview);previewGesture.cancel();activePointer=-1;scene.inspecting=false
        if(!carouselStage){carouselTransaction++;main.removeCallbacks(carouselPump);desiredPageIndex=carouselPage;carouselSettling=false;scene.settleSide=0}
        clearInput();busy=false
        val playing=stage==Stage.PLAYING
        header.visibility=if(playing)View.GONE else View.VISIBLE
        (primary.parent as View).visibility=if(playing)View.GONE else View.VISIBLE
        primary.visibility=if(stage==Stage.MEDIA&&games.isEmpty())View.VISIBLE else View.GONE
        importButton.visibility=if(playing)View.GONE else View.VISIBLE
        backdrop.active=stage==Stage.MACHINE||stage==Stage.THEME
        rim.effectEnabled=backdrop.active
        scene.translationY=0f
        scene.mediaMode=stage==Stage.MEDIA;scene.themeMode=stage==Stage.THEME
        mediaInfo.visibility=View.GONE;shelfLabels.visibility=if(stage==Stage.MEDIA&&games.isNotEmpty())View.VISIBLE else View.GONE
        scene.carouselEnabled=carouselStage
        scene.physicalComparison=stage==Stage.MACHINE||stage==Stage.THEME
        if(!carouselStage)scene.clearNeighbours()
        back.backArrow= !playing&&stage!=Stage.MACHINE
        back.contentDescription=if(playing||stage==Stage.MACHINE)"菜单，向右滑动展开" else "返回上一页"
        logo.visibility=if(stage==Stage.MACHINE)View.VISIBLE else View.GONE
        detail.visibility=if(stage==Stage.THEME)View.VISIBLE else View.GONE
        title.textSize=if(stage==Stage.MACHINE)9f else 17.5f
        title.text=when(stage){Stage.MACHINE->if(machine==Machine.PSP)"SONY" else "NINTENDO";Stage.MEDIA->"选择游戏";else->machine.label}
        detail.text=if(stage==Stage.THEME)machine.themes[theme] else games.getOrNull(mediaIndex)?.title?:"从文件添加游戏，开始你的收藏。"
        if(stage==Stage.MACHINE){val key=machine.key;io.execute{val bitmap=runCatching{assets.open("logos/$key-home.png").use{android.graphics.BitmapFactory.decodeStream(it)}}.getOrNull();main.post{if(stage==Stage.MACHINE&&machine.key==key)logo.setImageBitmap(bitmap)}}}
        val layout=scene.layoutParams as FrameLayout.LayoutParams
        layout.topMargin=if(playing)0 else dp(if(stage==Stage.MEDIA)52 else 64);layout.bottomMargin=if(playing)0 else dp(if(stage==Stage.MEDIA&&games.isNotEmpty())(136+max(0,((resources.configuration.fontScale-1)*60).toInt())) else 48);scene.layoutParams=layout;rim.layoutParams=FrameLayout.LayoutParams(layout)
        val count=when(stage){Stage.MACHINE->machines.size;Stage.THEME->machine.themes.size;Stage.MEDIA->games.size;else->0}
        val selected=when(stage){Stage.MACHINE->machineIndex;Stage.THEME->theme;else->mediaIndex}
        dots.update(count,selected)
        if(!playing)loadModel(if(stage==Stage.MEDIA)"media-${machine.key}" else "${machine.key}-$theme"){if(stage==Stage.MEDIA)refreshMediaResources()}
        if(stage==Stage.MEDIA)refreshMediaResources()
    }
    private fun refreshMediaResources(){
        shelfLabels.setCaptions(games.associate{g->val r=gameResources.cached(g)
            fun value(k:String)=r?.optString(k)?.takeIf{it.isNotBlank()&&it!="null"}?:"/"
            val score=r?.optInt("metacritic",-1)?.takeIf{it in 0..100}?.let{"$it/100"}?:"/"
            g.id to MediaCaption(Motion.displayTitle(g.title),"开发 · ${value("developer")}\n出品 · ${value("publisher")}\n发售 · ${value("releaseDate")} · ${value("releaseRegion").removePrefix("Metacritic · ")}\nMetacritic · $score")})
        val game=games.getOrNull(mediaIndex)?:return
        scene.beginMediaSelection(game.id)
        val record=gameResources.cached(game)
        fun value(key:String)=record?.optString(key)?.takeIf{it.isNotBlank()&&it!="null"}?:"/"
        mediaTitle.text=game.title
        val score=record?.optInt("metacritic",-1)?.takeIf{it in 0..100}?.let{"$it/100"}?:"/"
        mediaCredits.text="开发 · ${value("developer")}   出品 · ${value("publisher")}\n发售 · ${value("releaseDate")} · ${value("releaseRegion").removePrefix("Metacritic · ")}   Metacritic · $score"
        gameResources.request(game)
        val file=gameResources.coverFile(game)
        val signature="${game.id}:${file?.lastModified()?:0}:${scene.viewer.asset?.root?:0}"
        if(signature==lastCoverSignature)return;lastCoverSignature=signature
        val token=++coverRequest
        io.execute{if(token!=coverRequest)return@execute;val pixels=CoverArt.prepare(game,file);main.post{if(token==coverRequest&&stage==Stage.MEDIA&&games.getOrNull(mediaIndex)?.id==game.id&&!isDestroyed)scene.queueCover(pixels)}}
    }
    private fun loadModel(name:String,onLoaded:(()->Unit)?=null){
        modelError=""
        val token=++generation
        if(shownModel==name&&scene.viewer.asset!=null){
            busy=false;primary.isEnabled=true
            if(entryFade&&stage==Stage.THEME&&scene.diagnostics()["assetReady"]==true)fadePreview()
            prepareNeighbours(token);onLoaded?.invoke();return
        }
        busy=true;primary.isEnabled=false
        io.execute{
            if(token!=generation)return@execute
            val result=runCatching{assets.open("models/$name.glb").use{val bytes=it.readBytes();val sha=java.security.MessageDigest.getInstance("SHA-256").digest(bytes).joinToString(""){b->"%02x".format(b)};Pair(ByteBuffer.allocateDirect(bytes.size).apply{put(bytes);flip()},sha)}}
            main.post{if(token!=generation||isFinishing)return@post
                busy=false;primary.isEnabled=true
                result.fold({buffer->try{scene.show(buffer.first,machine,buffer.second);shownModel=name;modelLoads++;rim.load(name,buffer.second);fadePreview();prepareNeighbours(token);onLoaded?.invoke()}catch(e:Exception){modelError=e.message?:e.javaClass.simpleName;problem("模型载入失败",modelError)}}, {detail.text="本地模型资源包尚未配置";problem("需要本地素材包","此开发构建从独立私用素材目录读取模型。公开素材方案仍待确定。")})
            }
        }
    }
    private fun prepareNeighbours(token:Int){
        if(!carouselStage)return
        val media=stage==Stage.MEDIA;val themes=stage==Stage.THEME;val pageStage=stage;val focusedPage=carouselPage;val focusedMachine=machine
        val list=games
        val desired=mutableMapOf<Int,String>()
        for(side in listOf(-1,1)){
            if(media){list.getOrNull(mediaIndex+side)?.let{desired[side]="media:${it.id}"}}
            else if(themes){val next=theme+side;if(next in machine.themes.indices)desired[side]="${machine.key}-$next"}
            else {val kind=machines.getOrNull(machineIndex+side)?:continue;val saved=getPreferences(0).getInt("theme-${kind.key}",0).coerceIn(0,3);desired[side]="${kind.key}-$saved"}
        }
        scene.retainNeighbours(desired)
        fun current()=token==generation&&carouselStage&&stage==pageStage&&carouselPage==focusedPage&&machine==focusedMachine
        for((side,name) in desired){
            val kind=if(media||themes)machine else machines[machineIndex+side]
            val game=if(media)list[mediaIndex+side]else null
            val file=game?.let{gameResources.coverFile(it)}
            val rootId=scene.viewer.neighbour(side)?.root?:0
            val signature="$token:$name:$rootId:${file?.lastModified()?:0}"
            if((media&&neighbourCoverSignatures[side]==signature)||(!media&&scene.hasNeighbour(side,name)))continue
            neighbourCoverSignatures[side]=signature
            val existing=scene.hasNeighbour(side,name)
            io.execute{if(token!=generation)return@execute
                val prepared=if(existing)null else runCatching{assets.open("models/${if(media)"media-${kind.key}" else name}.glb").use{NeighbourModel.buffer(it.readBytes())}}.getOrNull()
                val art=game?.let{CoverArt.prepare(it,file)}
                main.post{if(current()){
                    if(prepared!=null)scene.showNeighbour(side,prepared,kind,name)
                    if(art!=null){scene.queueNeighbourCover(side,name,art);neighbourCoverSignatures[side]="$token:$name:${scene.viewer.neighbour(side)?.root?:0}:${file?.lastModified()?:0}"}
                }}
            }
        }
    }
    private fun cancelCarouselNavigation(){
        carouselTransaction++;main.removeCallbacks(carouselPump);carouselSettling=false;desiredPageIndex=carouselPage
        carouselAnimation?.cancel();scene.carouselOffset=0f;scene.settleSide=0
    }
    private fun requestMachine(index:Int){
        traceNavigation("request $index from $carouselPage $stage")
        desiredPageIndex=index.coerceIn(0,carouselLast);carouselWaitStarted=SystemClock.uptimeMillis()
        main.removeCallbacks(carouselPump);advanceCarousel()
    }
    private fun advanceCarousel(){
        if(!carouselStage||isFinishing||carouselSettling)return
        if(desiredPageIndex==carouselPage){settleCarousel();return}
        val side=if(desiredPageIndex>carouselPage)1 else -1
        if(!scene.neighbourReady(side)){
            if(SystemClock.uptimeMillis()-carouselWaitStarted>maxOf(10000L,scene.presentationWaitMs)){desiredPageIndex=carouselPage;settleCarousel();problem("展示资源准备未完成","请稍后重新滑动。");return}
            main.postDelayed(carouselPump,30);return
        }
        val transaction=++carouselTransaction
        carouselSettling=true;main.removeCallbacks(holdPreview);previewGesture.cancel();scene.inspecting=false
        carouselAnimation?.cancel();scene.settleSide=side;scene.settleDistance=scene.travelPixels(side)
        val destination= -side*scene.settleDistance
        val oldName=if(stage==Stage.MEDIA)"media:${games[mediaIndex].id}" else shownModel?:"${machine.key}-$theme"
        var cancelled=false
        carouselAnimation=android.animation.ValueAnimator.ofFloat(scene.carouselOffset,destination).apply{
            duration=(280*(abs(destination-scene.carouselOffset)/max(1f,scene.settleDistance))).toLong().coerceIn(140,320)
            interpolator=android.view.animation.DecelerateInterpolator(1.4f)
            addUpdateListener{scene.carouselOffset=it.animatedValue as Float}
            addListener(object:android.animation.AnimatorListenerAdapter(){
                override fun onAnimationCancel(animation:android.animation.Animator){cancelled=true}
                override fun onAnimationEnd(animation:android.animation.Animator){if(!cancelled&&transaction==carouselTransaction){
                    val waitingSince=SystemClock.uptimeMillis()
                    val commit=object:Runnable{override fun run(){
                        if(!carouselStage||!carouselSettling||transaction!=carouselTransaction)return
                        val presented=(scene.diagnostics()["presentedOffset"] as? Float)?:0f
                        if(abs(presented-destination)>1f){
                            if(SystemClock.uptimeMillis()-waitingSince<maxOf(10000L,scene.presentationWaitMs)){main.postDelayed(this,16);return}
                            traceNavigation("presentation timeout destination=$destination shown=$presented");carouselSettling=false;desiredPageIndex=carouselPage;scene.settleSide=0;settleCarousel();return
                        }
                        val media=stage==Stage.MEDIA;val themes=stage==Stage.THEME
                        val next=carouselPage+side
                        val kind=if(media||themes)machine else machines[next]
                        val saved=if(media)theme else if(themes)next else getPreferences(0).getInt("theme-${kind.key}",0).coerceIn(0,3)
                        val name=if(media)"media:${games[next].id}" else "${kind.key}-$saved"
                        traceNavigation("promote $side");val sha=scene.promote(side,kind,oldName,name)
                        carouselSettling=false
                        if(sha==null){desiredPageIndex=carouselPage;scene.settleSide=0;settleCarousel();return}
                        if(media){mediaIndex=next;shownModel="media-${kind.key}"}else{if(!themes)machineIndex=next;theme=saved;getPreferences(0).edit().putInt("theme-${kind.key}",theme).apply();shownModel=name;rim.load(name,sha)}
                        carouselWaitStarted=SystemClock.uptimeMillis();refresh();main.post(carouselPump)
                    }}
                    main.post(commit)
                }}
            });start()
        }
    }
    private fun settleCarousel(){
        carouselAnimation?.cancel();val from=scene.carouselOffset
        carouselAnimation=android.animation.ValueAnimator.ofFloat(from,0f).apply{duration=220;interpolator=android.view.animation.DecelerateInterpolator();addUpdateListener{scene.carouselOffset=it.animatedValue as Float};start()}
    }
    private fun fadePreview(){for(view in listOf(scene,rim)){view.animate().cancel();view.alpha=0f;view.animate().alpha(1f).setDuration(280).start()}}
    private fun page(delta:Int){val current=when(stage){Stage.MACHINE->machineIndex;Stage.THEME->theme;else->mediaIndex};selectPage(current+delta.coerceIn(-1,1))}
    private fun selectPage(index:Int){
        if(stage==Stage.PLAYING||stage==Stage.INSERTING||launchingGame)return
        when(stage){
            Stage.MACHINE->{requestMachine(index);return}
            Stage.THEME->{requestMachine(index);return}
            Stage.MEDIA->{if(games.isEmpty())return;requestMachine(index);return}
            else->return
        };refresh()
    }
    private fun confirm(){if(busy||carouselSettling||abs(scene.carouselOffset)>.5f)return
        cancelCarouselNavigation()
        when(stage){Stage.MACHINE->{stage=Stage.THEME;refresh()};Stage.THEME->{stage=Stage.MEDIA;mediaIndex=0;desiredPageIndex=0;refresh()};Stage.MEDIA->{if(games.isEmpty())importFiles() else startGame(games[mediaIndex])};else->{}}
    }
    private fun startGame(game:Game){
        if(machine==Machine.N3DS){problem("3DS 后端尚未就绪","模型可预览；尚未通过 Android 核心与下屏输入验证，不标记为可游玩。");return}
        if(session?.isAlive()==true){problem("正在保存游戏","请稍后再启动。");return}
        cancelCarouselNavigation();if(!tablet)requestedOrientation=if(machine==Machine.GBC)ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT else ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        val prefs=getPreferences(0);scene.displayScale=prefs.getFloat("display-scale-${machine.key}",1f);scene.displayOffsetX=prefs.getFloat("display-x-${machine.key}",0f);scene.displayOffsetY=prefs.getFloat("display-y-${machine.key}",0f)
        launchingGame=true;busy=true;stage=Stage.INSERTING
        header.visibility=View.GONE;mediaInfo.visibility=View.GONE;shelfLabels.visibility=View.GONE;importButton.visibility=View.GONE;(primary.parent as View).visibility=View.GONE;back.backArrow=true
        backdrop.active=false;rim.effectEnabled=false;loadingAudio.begin()
        val token=++generation;val name=if(machine==Machine.NDS||machine==Machine.N3DS)"${machine.key}-open-$theme" else "${machine.key}-$theme";shownModel=null
        val lp=scene.layoutParams as FrameLayout.LayoutParams;val fromTop=lp.topMargin;val fromBottom=lp.bottomMargin;val fromY=scene.translationY
        assemblyLayout?.cancel();assemblyLayout=android.animation.ValueAnimator.ofFloat(0f,1f).apply{duration=420;addUpdateListener{val p=it.animatedValue as Float;lp.topMargin=(fromTop*(1-p)).roundToInt();lp.bottomMargin=(fromBottom*(1-p)).roundToInt();scene.layoutParams=lp;scene.translationY=fromY*(1-p)};start()}
        io.execute{
            val body=runCatching{SystemResources.install(this,File(filesDir,"system").also{it.mkdirs()});assets.open("models/$name.glb").use{NeighbourModel.buffer(it.readBytes())}}
            main.post{if(token!=generation||stage!=Stage.INSERTING||isFinishing)return@post
                body.fold({prepared->
                    scene.onLoadingProgress={progress->loadingAudio.advance(machine,progress)}
                    scene.prepareAssembly(prepared){
                        if(token!=generation||stage!=Stage.INSERTING)return@prepareAssembly
                        shownModel=name;modelLoads++
                        session=CoreSession(filesDir,this,validationSaveDirectory?:File(filesDir,"saves"),onSaveFailure={main.post{if(!isFinishing&&!isDestroyed)problem("卡带存档未能写入","本次写入失败的文件未替换旧存档。请检查设备可用空间；返回游戏后可稍后重试保存。")}}){ok,message->main.post{
                            if(isFinishing||!launchingGame||token!=generation)return@post
                            launchingGame=false;busy=false;primary.isEnabled=true
                            if(ok){stage=Stage.PLAYING;refresh();scene.playing=true;window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)}
                            else{loadingAudio.stop();problem("游戏未启动",message);stage=Stage.MEDIA;shownModel=null;refresh()}
                        }}.also{it.volume=gameVolume;it.start(game,library.file(game))}
                    }
                },{launchingGame=false;busy=false;loadingAudio.stop();scene.cancelAssembly();stage=Stage.MEDIA;shownModel=null;refresh();problem("装载资源未就绪",it.message?:"模型读取失败")})
            }
        }
    }
    private fun problem(title:String,detail:String){if(!isFinishing)AlertDialog.Builder(this).setTitle(title).setMessage(detail).setPositiveButton("好",null).show()}
    private fun hideGameMenu(resume:Boolean){gameMenu?.let{root.removeView(it)};gameMenu=null;if(resume)session?.pause(false)}
    private fun leaveGame(toMachines:Boolean){
        hideGameMenu(false);clearInput();session?.close();scene.playing=false
        stage=if(toMachines)Stage.MACHINE else Stage.MEDIA;shownModel=null
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if(!tablet)requestedOrientation=ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        refresh()
    }
    private var stateBusy=false
    private fun quickState(restore:Boolean,slot:Int){
        if(stateBusy)return
        val core=session?:return;clearInput();core.pause(true)
        fun execute(){stateBusy=true;hideGameMenu(false);core.state(restore,slot){result,message->main.post{stateBusy=false;if(result == -2)leaveGame(true);if(result==1){Toast.makeText(this,if(restore)"已恢复进度" else "此刻已保存",Toast.LENGTH_SHORT).show();hideGameMenu(true)}else {if(result != -2)showGameMenu();problem("即时存档未完成",message)}}}}
        if(restore)AlertDialog.Builder(this).setTitle("恢复这份即时存档？").setMessage("当前画面会回到保存时的位置。游戏内存档仍单独保留。").setPositiveButton("恢复"){_,_->execute()}.setNegativeButton("取消",null).show() else execute()
    }
    private fun showGameMenu(){
        if(stage!=Stage.PLAYING||gameMenu!=null||stateBusy)return
        clearInput();session?.pause(true)
        gameMenu=GameMenu(this,scene.displayScale,scene.displayOffsetX,scene.displayOffsetY,{scale,x,y->
            scene.displayScale=scale;scene.displayOffsetX=x;scene.displayOffsetY=y
            getPreferences(0).edit().putFloat("display-scale-${machine.key}",scale).putFloat("display-x-${machine.key}",x).putFloat("display-y-${machine.key}",y).apply()
        },{hideGameMenu(true)},{leaveGame(false)},{leaveGame(true)},haptics.enabled,{haptics.enabled=it},if(machine==Machine.NDS)scene.bookMode else null,{clearInput();scene.bookMode= !scene.bookMode;hideGameMenu(true)},onState={restore,slot->quickState(restore,slot)}).also{root.addView(it,FrameLayout.LayoutParams(-1,-1))}
    }
    private fun goBack(){if(gameMenu!=null){hideGameMenu(true);return};cancelCarouselNavigation();if(launchingGame){assemblyLayout?.cancel();loadingAudio.stop();scene.cancelAssembly();launchingGame=false;session?.close();session=null;if(!tablet)requestedOrientation=ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE;++generation;shownModel=null;stage=Stage.MEDIA;refresh();return};if(stage==Stage.PLAYING){showGameMenu();return}
        stage=when(stage){Stage.MEDIA->Stage.THEME;Stage.THEME->Stage.MACHINE;else->{finish();return}};refresh()
    }
    @Deprecated("Compatibility with Android API 28") override fun onBackPressed(){goBack()}
    private fun requestResourceConsent(){
        val prefs=getSharedPreferences("resource-network-consent",0)
        if(prefs.contains("approved-v1")||isFinishing||isDestroyed)return
        AlertDialog.Builder(this).setTitle("自动整理你的游戏收藏")
            .setMessage("联网匹配封面、开发商、发售日期与媒体评分。只会向 Libretro thumbnails / GitHub、Wikidata、Metacritic 查询游戏名称、机型和地区，不上传 ROM、存档或账户信息。选择离线也可正常导入和游玩。")
            .setPositiveButton("自动匹配"){_,_->prefs.edit().putBoolean("approved-v1",true).apply();gameResources.retryAfterConsent(library.snapshot())}
            .setNegativeButton("先离线使用"){_,_->prefs.edit().putBoolean("approved-v1",false).apply()}.show()
    }
    private fun repairLibrary(includeDevelopment:Boolean){
        io.execute{val outcome=runCatching{library.archiveInvalidEntries(includeDevelopment)};main.post{outcome.onSuccess{if(it.optInt("archived")>0){mediaIndex=mediaIndex.coerceAtMost((games.size-1).coerceAtLeast(0));if(stage!=Stage.PLAYING&&!launchingGame)refresh();Toast.makeText(this,"已归档 ${it.optInt("archived")} 条失效记录，存档已保留",Toast.LENGTH_LONG).show()}else if(includeDevelopment)Toast.makeText(this,"游戏库已检查，没有失效条目",Toast.LENGTH_SHORT).show()}.onFailure{problem("整理未完成",it.message?:"请稍后重试")}}}
    }
    private fun importFiles(){if(stage==Stage.PLAYING)return;startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply{type="*/*";addCategory(Intent.CATEGORY_OPENABLE);putExtra(Intent.EXTRA_ALLOW_MULTIPLE,true)},7)}
    @Deprecated("Platform document picker") override fun onActivityResult(request:Int,result:Int,data:Intent?){super.onActivityResult(request,result,data);if(request!=7||result!=RESULT_OK)return
        val uris=data?.clipData?.let{c->(0 until c.itemCount).map{c.getItemAt(it).uri}}?:listOfNotNull(data?.data)
        busy=true;primary.isEnabled=false;detail.text="正在导入…"
        io.execute{
            val before=library.snapshot().map{it.id}.toSet();val failures=mutableListOf<String>()
            for(uri in uris){var name="所选文件";runCatching{
                contentResolver.query(uri,arrayOf(OpenableColumns.DISPLAY_NAME),null,null,null)?.use{if(it.moveToFirst())name=it.getString(0)}
                val stream=contentResolver.openInputStream(uri)?:error("无法读取文件");library.import(stream,name)
            }.onFailure{failures+="$name：${it.message?:"文件读取失败"}"}}
            val added=library.snapshot().filter{it.id !in before}
            main.post{cancelCarouselNavigation();busy=false;library.snapshot().forEach{gameResources.request(it)}
                added.firstOrNull{it.machine in machines}?.let{g->machineIndex=machines.indexOf(g.machine);theme=getPreferences(0).getInt("theme-${machine.key}",0).coerceIn(0,3);stage=Stage.MEDIA;mediaIndex=games.indexOfFirst{it.id==g.id}.coerceAtLeast(0)}
                refresh()
                if(failures.isNotEmpty()){
                    if(!isFinishing&&!isDestroyed)AlertDialog.Builder(this).setTitle(if(added.isEmpty())"导入未完成" else "已导入 ${added.size} 个游戏，部分文件未完成").setMessage(failures.joinToString("\n")).setPositiveButton("好",null).create().apply{setOnDismissListener{requestResourceConsent()};show()}
                }else{
                    if(added.isEmpty())Toast.makeText(this,"游戏已在库中，无需重复导入",Toast.LENGTH_LONG).show()
                    requestResourceConsent()
                }
            }
        }
    }
    private fun handleTouch(e:android.view.MotionEvent):Boolean {
        if(stateBusy)return true
        if(stage==Stage.PLAYING){
            if(scene.bookTransitioning){clearInput();return true}
            if(e.actionMasked==android.view.MotionEvent.ACTION_CANCEL){clearInput();return true}
            val releasedUtilities=mutableListOf<Int>()
            val up=e.actionMasked==android.view.MotionEvent.ACTION_UP||e.actionMasked==android.view.MotionEvent.ACTION_POINTER_UP
            for(i in 0 until e.pointerCount){val id=e.getPointerId(i);if(up&&i==e.actionIndex){utilityPointers.remove(id)?.let{u->val expected=if(u==5)"psp-power-switch" else "utility:$u";if(scene.controlAt(e.getX(i),e.getY(i))?.first==expected)releasedUtilities+=u};input.release(id);analogPointers.remove(id);touchPointers.remove(id);continue}
                val touch=if(id in analogPointers)null else scene.touchAt(e.getX(i),e.getY(i));if(touch!=null){utilityPointers.remove(id);touchPointers[id]=touch;input.replace(id,emptySet());continue}else touchPointers.remove(id)
                val target=scene.controlAt(e.getX(i),e.getY(i))
                if(target?.first=="stick"||id in analogPointers){analogPointers.add(id);utilityPointers.remove(id);val axis=scene.stickAt(e.getX(i),e.getY(i));scene.axisX=axis?.first?:0f;scene.axisY=axis?.second?:0f;input.replace(id,emptySet())}
                else if(target?.first?.startsWith("utility:")==true||target?.first=="psp-power-switch"){utilityPointers[id]=if(target.first=="psp-power-switch")5 else target.first.substringAfter(':').toInt();input.replace(id,emptySet())}
                else {utilityPointers.remove(id);input.replace(id,when{target==null->emptySet();target.first=="dpad"->Motion.dpad(target.second.first,target.second.second);else->target.first.substringAfter(':').toIntOrNull()?.let{setOf(it)}?:emptySet()})}
            }
            if(analogPointers.isEmpty()){scene.axisX=0f;scene.axisY=0f}
            scene.held=input.held();scene.utilitiesHeld=utilityPointers.values.toSet();haptics.update(scene.held+scene.utilitiesHeld.map{32+it},scene.axisX,scene.axisY);val touch=touchPointers.toSortedMap().values.firstOrNull();NativeCore.input(input.mask(),(scene.axisX*32767).toInt(),(scene.axisY*32767).toInt(),((touch?.first?:0f)*32767).toInt(),((touch?.second?:0f)*32767).toInt(),touch!=null);releasedUtilities.forEach{performUtility(it)};return true
        }
        if(launchingGame||carouselStage&&carouselSettling)return true
        when(e.actionMasked){
            MotionEvent.ACTION_DOWN->{carouselAnimation?.cancel();swipeBaseOffset=scene.carouselOffset;swipeStartX=e.x;if(carouselStage){desiredPageIndex=carouselPage;main.removeCallbacks(carouselPump)};main.removeCallbacks(holdPreview);activePointer=e.getPointerId(0);previewGesture.down(e.x,e.y,e.eventTime);scene.inspecting=false;main.postDelayed(holdPreview,200)}
            MotionEvent.ACTION_POINTER_DOWN->{main.removeCallbacks(holdPreview);previewGesture.twoFingers();scene.inspecting=true}
            MotionEvent.ACTION_MOVE->{
                val index=e.findPointerIndex(activePointer)
                if(index>=0){val delta=previewGesture.move(e.getX(index),e.getY(index),e.eventTime)
                    if(previewGesture.intent!=PreviewGesture.Intent.PRESS)main.removeCallbacks(holdPreview)
                    if(carouselStage&&previewGesture.intent==PreviewGesture.Intent.SWIPE){
                        val dx=e.getX(index)-swipeStartX;val bounded=(swipeBaseOffset+dx).coerceIn(-scene.carouselStepPixels,scene.carouselStepPixels)
                        scene.carouselOffset=if((carouselPage==0&&dx>0)||(carouselPage==carouselLast&&dx<0))bounded*.2f else bounded
                    }
                    scene.inspecting=previewGesture.intent==PreviewGesture.Intent.ROTATE
                    if(scene.inspecting){val points=resources.displayMetrics.density;scene.yaw=(scene.yaw+delta.first/points*.012f*(180f/PI.toFloat())).coerceIn(-180f,180f);val limit=.65f*(180f/PI.toFloat());scene.pitch=(scene.pitch+delta.second/points*.008f*(180f/PI.toFloat())).coerceIn(-limit,limit)}
                }
            }
            MotionEvent.ACTION_POINTER_UP->{if(e.getPointerId(e.actionIndex)==activePointer){val index=if(e.actionIndex==0)1 else 0;activePointer=e.getPointerId(index);previewGesture.rebase(e.getX(index),e.getY(index))}}
            MotionEvent.ACTION_UP->{main.removeCallbacks(holdPreview);scene.inspecting=false;val action=previewGesture.up(e.x,e.y,e.eventTime);activePointer=-1;when(action){1->{if(carouselStage){(scene.previewPageAt(e.x,e.y)?:shelfLabels.captionAt(e.x+scene.left-shelfLabels.left,e.y+scene.top+scene.translationY-shelfLabels.top)?.let{id->games.indexOfFirst{it.id==id}.takeIf{it>=0}?.minus(mediaIndex)})?.let{side->if(side==0)confirm()else page(side)}}else confirm()};2->page(-1);3->page(1)};if(!carouselSettling&&desiredPageIndex==carouselPage)settleCarousel()}
            MotionEvent.ACTION_CANCEL->{settleCarousel();main.removeCallbacks(holdPreview);previewGesture.cancel();activePointer=-1;scene.inspecting=false}
        }
        return true
    }
    private fun performUtility(id:Int){when(id){
        0,5->leaveGame(false)
        1->{gameVolume=(gameVolume-.1f).coerceAtLeast(0f);session?.volume=gameVolume}
        2->{gameVolume=(gameVolume+.1f).coerceAtMost(1f);session?.volume=gameVolume}
        3->{if(gameVolume>0){unmutedVolume=gameVolume;gameVolume=0f}else gameVolume=unmutedVolume.coerceAtLeast(.1f);session?.volume=gameVolume}
        4->{scene.screenBrightness=if(scene.screenBrightness>.7f).55f else 1f}
    }}
    override fun onConfigurationChanged(configuration:android.content.res.Configuration){
        super.onConfigurationChanged(configuration)
        clearInput();main.removeCallbacks(holdPreview);previewGesture.cancel();activePointer=-1;scene.inspecting=false
        if(carouselStage)cancelCarouselNavigation()
        root.requestApplyInsets()
    }
    private fun clearInput(){haptics.reset();utilityPointers.clear();input.clear();analogPointers.clear();touchPointers.clear();if(::scene.isInitialized){scene.held=emptySet();scene.utilitiesHeld=emptySet();scene.axisX=0f;scene.axisY=0f};NativeCore.input(0,0,0,0,0,false)}
    override fun onPause(){traceNavigation("pause $stage");super.onPause();loadingAudio.stop();if(stage==Stage.INSERTING){assemblyLayout?.cancel();scene.cancelAssembly();launchingGame=false;session?.close();session=null;if(!tablet)requestedOrientation=ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE;++generation;stage=Stage.MEDIA;shownModel=null;refresh()};carouselTransaction++;main.removeCallbacks(carouselPump);carouselSettling=false;desiredPageIndex=carouselPage;scene.settleSide=0;carouselAnimation?.cancel();scene.carouselOffset=0f;main.removeCallbacks(holdPreview);previewGesture.cancel();activePointer=-1;scene.inspecting=false;clearInput();scene.pause();session?.pause(true)}
    override fun onWindowFocusChanged(hasFocus:Boolean){super.onWindowFocusChanged(hasFocus);if(!hasFocus&&::scene.isInitialized){clearInput();main.removeCallbacks(holdPreview);previewGesture.cancel();activePointer=-1;scene.inspecting=false;session?.pause(true)}else if(hasFocus&&gameMenu==null)session?.pause(false)}
    override fun onResume(){traceNavigation("resume $stage");super.onResume();if(::scene.isInitialized)scene.resume();if(gameMenu==null)session?.pause(false)}
    override fun onDestroy(){++generation;session?.close();loadingAudio.close();gameResources.close();io.shutdown();super.onDestroy()}
}
