// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app

import android.content.Context
import android.opengl.Matrix
import android.view.Choreographer
import android.view.TextureView
import com.google.android.filament.*
import com.google.android.filament.utils.*
import java.nio.ByteBuffer
import kotlin.math.*

/** Converted shared geometry; visual parity is verified scene by scene. */
class MachineSurface(context:Context):TextureView(context),Choreographer.FrameCallback {
    companion object {init {Utils.init()}}
    private val tabletDevice=DeviceProfile.isTablet(context)
    val viewer=ShowcaseRenderer(this)
    private val tm get()=viewer.engine.transformManager
    private val appliedTransforms=mutableMapOf<Int,FloatArray>()
    private var appliedProjection:DoubleArray?=null
    private fun setPose(entity:Int,m:FloatArray){val previous=appliedTransforms[entity];if(previous!=null&&previous.contentEquals(m))return;tm.setTransform(tm.getInstance(entity),m);appliedTransforms[entity]=m.copyOf()}
    private fun project(half:Double,aspect:Double){val values=doubleArrayOf(half,aspect);if(appliedProjection?.contentEquals(values)==true)return;viewer.camera.setProjection(Camera.Projection.ORTHO,-half*aspect,half*aspect,-half,half,.05,100.0);appliedProjection=values}
    private var rootBase=FloatArray(16)
    private val poses=mutableMapOf<Int,FloatArray>()
    private val pressAmounts=mutableMapOf<Int,Float>()
    private var padX=0f;private var padY=0f
    private val screenTextures=mutableMapOf<Int,Texture>()
    private val screenBuffers=mutableMapOf<Int,ByteBuffer>()
    private val uploadsInFlight=mutableSetOf<Int>()
    private var screenGeneration=0
    private val handler=android.os.Handler(android.os.Looper.getMainLooper())
    private val lastScreenSerial=mutableMapOf<Int,Int>()
    private val screenDimensions=mutableMapOf<Int,Pair<Int,Int>>()
    private var running=false
    var carouselOffset=0f
        set(value){field=value;if(abs(value)>.5f)presented?.let{onRimFrame?.invoke(it.rim.copy(opacity=0f))}}
    var carouselEnabled=false
    var physicalComparison=false
    private val neighbourKinds=mutableMapOf<Int,Machine>()
    private val neighbourNames=mutableMapOf<Int,String>()
    private val slotPixels=mutableMapOf<Int,Float>()
    private var comparisonUnitsPerMM=0f
    private var comparisonMinimum=0.0
    var settleSide=0
    var settleDistance=0f
    private var promotions=0
    fun travelPixels(side:Int)=slotPixels[side]?:carouselStepPixels
    fun neighbourReady(side:Int)=viewer.neighbourReady(side)&&(!mediaMode||viewer.neighbour(side)?.root?.let{mediaCovers[it]?.id?.isNotEmpty()}==true)
    fun hasNeighbour(side:Int,name:String)=neighbourNames[side]==name
    fun retainNeighbours(names:Map<Int,String>){neighbourNames.keys.toList().filter{neighbourNames[it]!=names[it]}.forEach{viewer.removeNeighbour(it);neighbourNames.remove(it);neighbourKinds.remove(it)}}
    fun promote(side:Int,kind:Machine,oldName:String,newName:String):String? {
        val sha=viewer.promoteNeighbour(side)?:return null
        val oldKind=machine;neighbourKinds.clear();neighbourNames.clear();neighbourKinds[-side]=oldKind;neighbourNames[-side]=oldName
        val previousFit=fittedHalfHeight;comparisonMinimum=max(comparisonMinimum,previousFit)
        machine=kind;yaw=0f;pitch=0f;carouselOffset=0f;settleSide=0;settleDistance=0f;promotions++
        bindCurrent(false);fittedHalfHeight=previousFit;return sha
    }
    val carouselStepPixels get()=width*.84f
    fun clearNeighbours(){neighbourKinds.clear();neighbourNames.clear();slotPixels.clear();if(assemblyStage>0){viewer.removeNeighbour(-1);viewer.removeNeighbour(1)}else viewer.clearNeighbours()}
    fun showNeighbour(side:Int,buffer:NeighbourModel.Prepared,kind:Machine,name:String){viewer.loadNeighbour(side,buffer,!mediaMode);neighbourKinds[side]=kind;neighbourNames[side]=name}
    private fun physicalWidth(m:Machine)=when(m){Machine.GBA->144.5f;Machine.GBC->78f;Machine.PSP->169.4f;Machine.NDS->133f;Machine.N3DS->160f}
    internal var previewProbeTime:Double?=null
    var themeMode=false
    private val mediaLifts=mutableMapOf<Int,Float>()
    private fun mediaLift(root:Int,target:Float,dt:Double):Float {val value=(target+((mediaLifts[root]?:0f)-target)*exp(-dt*18)).toFloat();mediaLifts[root]=value;return value}
    var mediaMode=false
    private class CoverState(var expected:String="",var pending:CoverArt.Pixels?=null,var texture:Texture?=null,var uploading:Boolean=false,var id:String="",var matched:Boolean=false)
    private val mediaCovers=mutableMapOf<Int,CoverState>()
    private val coverBoundId get()=viewer.asset?.root?.let{mediaCovers[it]?.id}?:""
    private val coverMatched get()=viewer.asset?.root?.let{mediaCovers[it]?.matched}?:false
    fun beginMediaSelection(id:String){
        val asset=viewer.asset?:return;val state=mediaCovers.getOrPut(asset.root){CoverState()}
        if(id==state.expected)return
        state.expected=id;state.id="";state.matched=false;state.pending=null
        viewer.updatePigment(asset,"cover",floatArrayOf(0f,0f,0f,1f))
    }
    fun queueCover(pixels:CoverArt.Pixels){val a=viewer.asset?:return;val state=mediaCovers.getOrPut(a.root){CoverState()};if(pixels.id==state.expected)state.pending=pixels}
    fun queueNeighbourCover(side:Int,name:String,pixels:CoverArt.Pixels){
        if(neighbourNames[side]!=name)return
        val a=viewer.neighbour(side)?:return
        val state=mediaCovers.getOrPut(a.root){CoverState()};state.expected=pixels.id;state.pending=pixels
    }
    private fun disposeCovers(){mediaCovers.values.forEach{it.texture?.let{texture->viewer.engine.destroyTexture(texture)}};mediaCovers.clear()}
    private fun applyCovers(){
        // The assembly carrier (-2) remains a real texture user during return
        // transitions, even after the UI has already entered MEDIA.
        val active=viewer.liveAssetRoots
        mediaCovers.keys.toList().filter{it !in active}.forEach{mediaCovers.remove(it)?.texture?.let{texture->viewer.engine.destroyTexture(texture)}}
        for(side in listOf(0,-1,1)){
            val a=(if(side==0)viewer.asset else viewer.neighbour(side))?:continue
            if(if(side==0)viewer.progress<1f else !viewer.neighbourReady(side))continue
            val state=mediaCovers[a.root]?:continue;val art=state.pending?:continue;if(state.uploading)continue
            val rm=viewer.engine.renderableManager
            val labels=a.renderableEntities.flatMap{e->val i=rm.getInstance(e);(0 until rm.getPrimitiveCount(i)).map{rm.getMaterialInstanceAt(i,it)}}.filter{it.name=="cover"}
            if(labels.isEmpty())continue
            val texture=state.texture?:Texture.Builder().width(art.width).height(art.height).levels(1).sampler(Texture.Sampler.SAMPLER_2D).format(Texture.InternalFormat.SRGB8_A8).build(viewer.engine).also{state.texture=it}
            if(machine!=Machine.PSP)viewer.updatePigment(a,"media-shell",floatArrayOf(art.shellColor[0],art.shellColor[1],art.shellColor[2],1f))
            viewer.updatePigment(a,"cover",floatArrayOf(1f,1f,1f,1f))
            labels.forEach{it.setParameter("baseColorMap",texture,TextureSampler(TextureSampler.MinFilter.LINEAR,TextureSampler.MagFilter.LINEAR,TextureSampler.WrapMode.CLAMP_TO_EDGE))}
            state.pending=null;state.uploading=true
            val descriptor=Texture.PixelBufferDescriptor(art.rgba,Texture.Format.RGBA,Texture.Type.UBYTE)
            descriptor.setCallback(handler,Runnable{art.rgba.clear();state.uploading=false})
            texture.setImage(viewer.engine,0,descriptor);state.id=art.id;state.matched=art.matched
            if(side!=0)viewer.revealNeighbour(side)
        }
    }
    internal var assemblyProbeElapsed:Double?=null
    private var presentedLoadingProgress= -1.0
    private val pendingAssemblyFrames=mutableMapOf<Long,Double>()
    private var assemblyStage=0
    private var assemblyStart=0L
    private var sourceMedia=FloatArray(16)
    private var sourceHalfHeight=1.0
    private var assemblyComplete:(()->Unit)?=null
    private var loadingSlot=0
    private var loadingHatch=0
    private var loadingLid=0
    private var lidRest=FloatArray(16)
    private var loadingRotor=0
    private var hatchRest=FloatArray(16)
    private var rotorRest=FloatArray(16)
    var loadingProgress=0.0;private set
    var onLoadingProgress:((Double)->Unit)?=null
    private var loadingPoint=floatArrayOf(0f,0f,0f)
    private val mediaSpecs=runCatching{context.assets.open("media-slots.json").bufferedReader().use{org.json.JSONObject(it.readText())}}.getOrDefault(org.json.JSONObject())
    fun prepareAssembly(body:NeighbourModel.Prepared,complete:()->Unit){
        clearNeighbours();assemblyStage=1;assemblyComplete=complete;loadingProgress=0.0
        inspecting=false;viewer.loadNeighbour(2,body,false)
    }
    fun cancelAssembly(){assemblyStage=0;assemblyComplete=null;onLoadingProgress=null;viewer.removeNeighbour(2);viewer.removeNeighbour(-2)}
    private fun world(entity:Int):FloatArray=FloatArray(16).also{tm.getWorldTransform(tm.getInstance(entity),it)}
    private fun local(entity:Int):FloatArray=FloatArray(16).also{tm.getTransform(tm.getInstance(entity),it)}
    private fun point(m:FloatArray,x:Float,y:Float,z:Float):FloatArray=FloatArray(4).also{Matrix.multiplyMV(it,0,m,0,floatArrayOf(x,y,z,1f),0)}
    private fun scaleOf(m:FloatArray)=sqrt(m[0]*m[0]+m[1]*m[1]+m[2]*m[2])
    private fun advanceAssembly(time:Long){
        if(assemblyStage==0)return
        if(assemblyStage==1){
            if(!viewer.neighbourReady(2))return
            sourceMedia=world(viewer.asset!!.root);sourceHalfHeight=fittedHalfHeight
            viewer.promoteNeighbour(2);viewer.setNeighbourFocus(-2,1f)
            mediaMode=false;physicalComparison=false;bindCurrent(false)
            val a=viewer.asset!!
            loadingSlot=a.entities.firstOrNull{a.getName(it)=="slot"}?:0
            loadingLid=a.entities.firstOrNull{a.getName(it)=="lid"}?:0;if(loadingLid!=0)lidRest=local(loadingLid)
            loadingHatch=a.entities.firstOrNull{a.getName(it)=="hatch"}?:0
            if(loadingHatch!=0)hatchRest=local(loadingHatch)
            viewer.neighbour(-2)?.let{media->loadingRotor=media.entities.firstOrNull{media.getName(it)=="umd-rotor"}?:0;if(loadingRotor!=0)rotorRest=local(loadingRotor)}
            assemblyStart=time;assemblyStage=2
        }
        val elapsed=assemblyProbeElapsed?:((time-assemblyStart)/1e9);val duration=LoadingMotion.duration(machine);val t=(elapsed/duration).coerceIn(0.0,1.0);loadingProgress=t
        val flip=if(machine==Machine.PSP)LoadingMotion.ease((elapsed-duration)/.65) else LoadingMotion.ease((t-.84)/.16)
        val travel=LoadingMotion.ease((t-.14)/.30);val pickup=LoadingMotion.ease(t/.14);val depth=LoadingMotion.ease((t-.44)/.14);val push=LoadingMotion.ease((t-.58)/.26)
        val spec=mediaSpecs.optJSONObject(machine.key);val cardHeight=((spec?.optDouble("cardWidth",252.0)?:252.0)*(spec?.optDouble("ratio",1.0)?:1.0)/100).toFloat()
        val aspect=width.toDouble()/max(1,height)
        val loadingFit=max((halfExtent[1]+if(machine==Machine.PSP).3f else cardHeight*normalizationScale+.15f)/.90,halfExtent[0]/(aspect*.9))
        val radians=bookAngle*PI/180;val extentX=abs(cos(radians))*halfExtent[0]+abs(sin(radians))*halfExtent[1];val extentY=abs(sin(radians))*halfExtent[0]+abs(cos(radians))*halfExtent[1]
        val gameFit=max(extentY/.92,extentX/(aspect*.92))/(if(playing)displayScale.coerceIn(.7f,1.05f)else 1f)
        val target=loadingFit+(gameFit-loadingFit)*flip
        val fit=sourceHalfHeight+(target-sourceHalfHeight)*LoadingMotion.ease(t/.44)
        fittedHalfHeight=fit;project(fit,aspect)
        val body=FloatArray(16);Matrix.setIdentityM(body,0);Matrix.translateM(body,0,0f,(-2.7*fit*(1-LoadingMotion.ease(t/.28))).toFloat(),-4f)
        Matrix.rotateM(body,0,bookAngle,0f,0f,1f);Matrix.rotateM(body,0,if(machine==Machine.PSP)180f*(1-flip) else -10f*(1-flip),0f,1f,0f);Matrix.rotateM(body,0,if(machine==Machine.PSP)12.6f*(1-flip) else -10f*(1-flip),1f,0f,0f);Matrix.translateM(body,0,0f,0f,4f)
        val bodyWorld=FloatArray(16);Matrix.multiplyMM(bodyWorld,0,body,0,rootBase,0);if(playing){bodyWorld[12]+=displayOffsetX.coerceIn(-1f,1f)*max(0f,(fit*aspect-extentX).toFloat());bodyWorld[13]+=displayOffsetY.coerceIn(-1f,1f)*max(0f,(fit-extentY).toFloat())};setPose(viewer.asset!!.root,bodyWorld)
        if(loadingLid!=0){val pose=lidRest.copyOf();Matrix.rotateM(pose,0,(180f-5.73f)*(1-flip),1f,0f,0f);setPose(loadingLid,pose)}
        if(loadingHatch!=0){val pose=hatchRest.copyOf();Matrix.rotateM(pose,0,-LoadingMotion.door(t)*180f/PI.toFloat(),1f,0f,0f);setPose(loadingHatch,pose)}
        val media=viewer.neighbour(-2)
        if(media!=null){
            val anchor=if(machine==Machine.PSP)loadingHatch else loadingSlot
            if(anchor!=0){
                val parent=world(anchor);val end=parent.copyOf()
                val align=parent.copyOf();if(machine!=Machine.PSP)Matrix.rotateM(align,0,180f,0f,1f,0f)
                val above=if(machine==Machine.PSP)point(parent,0f,1.39f,-1.10f)else point(parent,0f,cardHeight/2+.12f,0f)
                val p=if(machine==Machine.PSP){val move=LoadingMotion.ease((t-.18)/.32);val seat=LoadingMotion.ease((t-.50)/.15)
                    if(t<=.50)floatArrayOf(sourceMedia[12]+(above[0]-sourceMedia[12])*move,sourceMedia[13]+(above[1]-sourceMedia[13])*move,sourceMedia[14]+(above[2]-sourceMedia[14])*move)
                    else point(parent,0f,1.39f,-1.10f+.98f*seat)
                }else if(t<=.58)floatArrayOf(sourceMedia[12]+(above[0]-sourceMedia[12])*travel,sourceMedia[13]+.25f*normalizationScale*pickup+(above[1]-sourceMedia[13]-.25f*normalizationScale*pickup)*travel,sourceMedia[14]+(above[2]-sourceMedia[14])*depth)
                else point(parent,0f,(cardHeight/2+.12f)*(1-push)+LoadingMotion.seat(machine,cardHeight)*push,0f)
                val mix=if(machine==Machine.PSP)LoadingMotion.ease((t-.18)/.32)else travel
                val q=LoadingMotion.slerp(LoadingMotion.quaternion(sourceMedia),LoadingMotion.quaternion(align),mix)
                val initial=scaleOf(sourceMedia);val destination=scaleOf(parent)*(if(machine==Machine.PSP).90f else 1f)
                val matrix=LoadingMotion.matrix(q,initial+(destination-initial)*mix,p[0],p[1],p[2]);setPose(media.root,matrix);loadingPoint=p
                if(loadingRotor!=0){val pose=rotorRest.copyOf();val spin=LoadingMotion.spin(t)+max(0.0,elapsed-duration).toFloat()*10f*PI.toFloat();Matrix.rotateM(pose,0,spin*180f/PI.toFloat(),0f,0f,1f);setPose(loadingRotor,pose)}
            }
        }
        if(assemblyStage==2){onLoadingProgress?.invoke(t)
            if(elapsed>=duration+(if(machine==Machine.PSP).65 else 0.0)){assemblyStage=3;assemblyComplete?.let{assemblyComplete=null;handler.post(it)}}
        }
    }
    var bookMode=false
    private var bookAngle=0f
    private var bookTarget=0f
    private var bookFrom=0f
    private var bookStart=0L
    val bookTransitioning get()=playing&&machine==Machine.NDS&&(abs(bookAngle-(if(bookMode)90f else 0f))>.01f||abs((presented?.bookAngle?:0f)-(if(bookMode)90f else 0f))>.01f)
    var displayScale=1f
    var displayOffsetX=0f
    var displayOffsetY=0f
    var playing=false
        set(value){field=value;viewer.screenPass=value}
    var machine=Machine.GBA
    var inspecting=false
        set(value){field=value;if(value)presented?.let{onRimFrame?.invoke(it.rim.copy(opacity=0f))}}
    var onRimFrame:((RimOverlay.Frame)->Unit)?=null
    var onMediaLayout:((List<MediaPlacement>)->Unit)?=null
    private var normalizationScale=1f
    private var rimOpacity=0f
    private data class Presented(val rim:RimOverlay.Frame,val yaw:Float,val pitch:Float,val held:Boolean,val contained:Boolean,val ready:Boolean,val width:Int,val height:Int,val offset:Float,val modelKey:String,val root:Int,val rightTravel:Float,val leftTravel:Float,val pixelsPerMM:Float,val media:List<MediaPlacement>,val bookAngle:Float,val rootScale:Float,val rightScale:Float)
    private val pendingFrames=java.util.LinkedHashMap<Long,Presented>()
    private var presented:Presented?=null
    private var presentationCount=0
    private var lastPresentedTime=0L
    private var presentationIntervalMs=16.7
    val presentationWaitMs get()=(presentationIntervalMs*6+1000).toLong().coerceIn(3000,60000)
    private var candidate:Presented?=null
    private var lastTick=0L
    private var halfExtent=floatArrayOf(1f,1f,1f)
    private var fittedHalfHeight=0.0
    private var envelopeContained=false
    var yaw=0f
    var pitch=0f
    var utilitiesHeld:Set<Int> = emptySet()
    var screenBrightness=1f
    var held:Set<Int> = emptySet()
    var axisX=0f
    var axisY=0f
    private var start=0L
    init {
        isOpaque=false
        viewer.onPresented={timestamp->
            val frame=pendingFrames[timestamp]
            if(frame!=null&&frame.width==width&&frame.height==height){
                if(lastPresentedTime>0){val interval=(timestamp-lastPresentedTime)/1e6;if(interval>0)presentationIntervalMs=presentationIntervalMs*.65+interval*.35};lastPresentedTime=timestamp
                presented=frame;presentationCount++;onMediaLayout?.invoke(frame.media)
                pendingAssemblyFrames[timestamp]?.let{presentedLoadingProgress=it};pendingAssemblyFrames.keys.filter{it<=timestamp}.forEach{pendingAssemblyFrames.remove(it)}
                onRimFrame?.invoke(frame.rim.copy(opacity=if(inspecting||abs(carouselOffset)>.5f||!frame.ready)0f else frame.rim.opacity))
                pendingFrames.keys.filter{it<=timestamp}.forEach{pendingFrames.remove(it)}
            }
        }
        viewer.scene.skybox=null
        viewer.view.blendMode=View.BlendMode.TRANSLUCENT
        viewer.renderer.clearOptions=Renderer.ClearOptions().apply{clear=true;clearColor=floatArrayOf(0f,0f,0f,0f)}
        val lighting=runCatching{context.assets.open("lighting/lighting_ibl.ktx").use{stream->val bytes=stream.readBytes();val buffer=ByteBuffer.allocateDirect(bytes.size).apply{put(bytes);flip()};KTX1Loader.createIndirectLight(viewer.engine,buffer)}}.getOrNull()
        viewer.scene.indirectLight=lighting?.indirectLight?.apply{intensity=25000f}?:IndirectLight.Builder().irradiance(1,floatArrayOf(.8f,.8f,.8f)).intensity(25000f).build(viewer.engine)
        viewer.indirectLightCubemap=lighting?.cubemap
        val key=viewer.engine.lightManager.getInstance(viewer.light)
        viewer.engine.lightManager.setDirection(key,.350f,-.435f,-.829f)
        viewer.engine.lightManager.setIntensity(key,110000f)
        viewer.view.isPostProcessingEnabled=true
        viewer.view.antiAliasing=View.AntiAliasing.FXAA
        viewer.view.sampleCount=4
        viewer.view.renderQuality=View.RenderQuality().apply{hdrColorBuffer=View.QualityLevel.MEDIUM}
    }
    fun show(buffer:ByteBuffer,m:Machine,sha:String) {
        assemblyStage=0;assemblyComplete=null;onLoadingProgress=null
        neighbourKinds.clear();neighbourNames.clear();slotPixels.clear();carouselOffset=0f;settleSide=0
        playing=false;bookMode=false;bookAngle=0f;bookTarget=0f;bookFrom=0f;bookStart=0;machine=m;yaw=0f;pitch=0f;held=emptySet()
        // Remove renderables/material bindings before retiring their dynamic textures.
        viewer.loadModelGlb(buffer,sha)
        screenTextures.values.forEach{viewer.engine.destroyTexture(it)}
        screenGeneration++;uploadsInFlight.clear();screenTextures.clear();screenBuffers.clear();screenDimensions.clear();lastScreenSerial.clear();poses.clear()
        disposeCovers()
        bindCurrent()
    }
    private fun bindCurrent(resetPresented:Boolean=true){
        poses.clear();pressAmounts.clear();padX=0f;padY=0f;appliedTransforms.clear();appliedProjection=null
        val asset=viewer.asset?:error("Invalid 3D model")
        // Printed transparent quads are decals, not opaque shadow blockers.
        // Otherwise a whole label rectangle shadows the yellow shell beneath it.
        val rm=viewer.engine.renderableManager
        asset.renderableEntities.forEach{entity->val instance=rm.getInstance(entity)
            val translucent=(0 until rm.getPrimitiveCount(instance)).any{index->
                val mode=rm.getMaterialInstanceAt(instance,index).material.blendingMode
                mode!=Material.BlendingMode.OPAQUE&&mode!=Material.BlendingMode.MASKED
            }
            if(translucent)rm.setCastShadows(instance,false)
        }
        val box=viewer.bounds(asset);val bounds=box.halfExtent;val center=box.center
        var q=1f/max(bounds[0],max(bounds[1],bounds[2]))
        if(physicalComparison){q=PreviewFit.scale(bounds[0],bounds[1],max(1,width).toFloat()/max(1,height),tabletDevice);comparisonUnitsPerMM=2*bounds[0]*q/physicalWidth(machine)}
        Matrix.setIdentityM(rootBase,0);Matrix.translateM(rootBase,0,0f,0f,-4f);Matrix.scaleM(rootBase,0,q,q,q);Matrix.translateM(rootBase,0,-center[0],-center[1],-center[2]);setPose(asset.root,rootBase)
        normalizationScale=q;viewer.setModelLightGeometry(q,center);rimOpacity=0f;if(resetPresented){pendingFrames.clear();presented=null};candidate=null
        halfExtent=FloatArray(3){bounds[it]*q};fittedHalfHeight=0.0
        asset.entities.forEach{e->val instance=tm.getInstance(e);if(instance!=0){val pose=FloatArray(16);tm.getTransform(instance,pose);val name=asset.getName(e)?:"";if(e!=asset.root&&(name.startsWith("key:")||name.startsWith("physical-shoulder:")||name=="dpad"||name=="stick"||name.startsWith("utility:")||name=="psp-power-switch"))poses[e]=pose}}
    }
    override fun onDetachedFromWindow(){
        pause()
        viewer.clearModel()
        disposeCovers()
        screenTextures.values.forEach{viewer.engine.destroyTexture(it)};screenTextures.clear()
        viewer.scene.indirectLight?.let{viewer.scene.indirectLight=null;viewer.engine.destroyIndirectLight(it)}
        viewer.scene.skybox?.let{viewer.scene.skybox=null;viewer.engine.destroySkybox(it)}
        super.onDetachedFromWindow()
    }
    override fun onSizeChanged(w:Int,h:Int,oldw:Int,oldh:Int){super.onSizeChanged(w,h,oldw,oldh);if(physicalComparison&&viewer.asset!=null&&w>0&&h>0)bindCurrent(false)}
    fun resume(){if(!running){running=true;Choreographer.getInstance().postFrameCallback(this)}}
    fun pause(){running=false;Choreographer.getInstance().removeFrameCallback(this);held=emptySet()}
    override fun doFrame(time:Long){
        if(!running)return
        viewer.setPreviewLighting(!playing&&assemblyStage==0)
        if(start==0L)start=time
        val t=previewProbeTime?:((time-start)/1e9)
        val dt=if(lastTick==0L)0.0 else (time-lastTick)/1e9;lastTick=time
        if(!inspecting){val decay=exp(-dt*1.6).toFloat();yaw*=decay;pitch*=decay}
        val targetBook=if(playing&&machine==Machine.NDS&&bookMode)90f else 0f
        if(targetBook!=bookTarget){bookFrom=bookAngle;bookTarget=targetBook;bookStart=time}
        bookAngle=bookFrom+(bookTarget-bookFrom)*LoadingMotion.ease((time-bookStart)/450_000_000.0)
        viewer.asset?.let{asset->
            val rotation=FloatArray(16);Matrix.setIdentityM(rotation,0)
            val incoming=if(carouselOffset<0)1 else -1
            val blend=if(carouselEnabled&&viewer.neighbourReady(incoming))(abs(carouselOffset)/max(1f,if(settleSide==incoming)settleDistance else travelPixels(incoming))).coerceIn(0f,1f)else 0f
            val idleYaw=(if(mediaMode)-6.875f else -9.17f)+sin(t*2*PI/8.5).toFloat()*10.31f
            val idlePitch=(if(mediaMode)-4.584f else 3.44f)+sin(t*2*PI/8.5).toFloat()*3.15f
            val outgoingYaw=(if(-incoming<0)12f else -12f)+sin(t*2*PI/8.5-incoming).toFloat()*5f
            val outgoingPitch=2f+sin(t*2*PI/8.5).toFloat()*2f
            val y=if(playing)0f else if(mediaMode||themeMode)yaw+idleYaw else (yaw+idleYaw)*(1-blend)+outgoingYaw*blend
            val x=if(playing)0f else if(mediaMode||themeMode)pitch+idlePitch else (pitch+idlePitch)*(1-blend)+outgoingPitch*blend
            if(assemblyStage==0)viewer.focusBlend(incoming,blend)
            Matrix.rotateM(rotation,0,bookAngle,0f,0f,1f);Matrix.rotateM(rotation,0,y,0f,1f,0f);Matrix.rotateM(rotation,0,x,1f,0f,0f)
            // Rotate about the object, never about the camera/world origin.
            val orbit=FloatArray(16);Matrix.setIdentityM(orbit,0);Matrix.translateM(orbit,0,0f,0f,-4f)
            Matrix.multiplyMM(orbit,0,orbit.copyOf(),0,rotation,0);Matrix.translateM(orbit,0,0f,0f,4f)
            val result=FloatArray(16);Matrix.multiplyMM(result,0,orbit,0,rootBase,0);if(assemblyStage==0)setPose(asset.root,result)
            if(mediaMode){val travel=max(1f,travelPixels(incoming));val target=(1-abs(carouselOffset)/travel).coerceIn(0f,1f);result[13]+=mediaLift(asset.root,target,dt)*.11f*normalizationScale;setPose(asset.root,result);mediaLifts.keys.retainAll(viewer.liveAssetRoots)}
            val aspect=width.toDouble()/max(1,height)
            val mediaHeight=minOf(height*.88,resources.displayMetrics.density.toDouble()*(if(tabletDevice)280 else 160))
            val mediaWidth=minOf(width*.88,resources.displayMetrics.density.toDouble()*(if(tabletDevice)360 else 290))
            val normalBase=if(physicalComparison)1.0 else max(halfExtent[1].toDouble()/.92,halfExtent[0].toDouble()/(aspect*.92))
            val base=if(mediaMode)max(halfExtent[1]*height/mediaHeight,halfExtent[0]*height/mediaWidth) else normalBase
            val projectedX=(0..2).sumOf{abs(rotation[it*4]).toDouble()*halfExtent[it]}
            val projectedY=(0..2).sumOf{abs(rotation[it*4+1]).toDouble()*halfExtent[it]}
            val needed=max(base,max(projectedY,projectedX/aspect)*1.06)
            fittedHalfHeight=if(fittedHalfHeight==0.0||needed>fittedHalfHeight)needed else needed+(fittedHalfHeight-needed)*exp(-dt*6)
            envelopeContained=projectedX<=fittedHalfHeight*aspect+.0001&&projectedY<=fittedHalfHeight+.0001
            if(assemblyStage==0)project(fittedHalfHeight,aspect)
            val halfWidth=fittedHalfHeight*aspect
            val offset=if(carouselEnabled)carouselOffset/ max(1,width)*2*halfWidth else 0.0
            if(offset!=0.0){result[12]+=offset.toFloat();if(assemblyStage==0)setPose(asset.root,result)}
            neighbourKinds.forEach{(side,kind)->viewer.neighbour(side)?.let{n->
                val box=viewer.bounds(n);val c=box.center;val h=box.halfExtent
                val scale=if(physicalComparison)PreviewFit.scale(h[0],h[1],aspect.toFloat(),tabletDevice) else halfExtent[0]*physicalWidth(kind)/physicalWidth(machine)/h[0]
                val spacing=if(settleSide==side)settleDistance/max(1,width)*2*halfWidth else if(themeMode)2*halfWidth*(if(tabletDevice).90 else .76)+(if(!tabletDevice&&machine==Machine.GBC)-140 else 24)*resources.displayMetrics.density/(width/(2*halfWidth)) else if(mediaMode)halfExtent[0]+h[0]*scale+22*resources.displayMetrics.density/(width/(2*halfWidth)) else max(halfWidth*.94,halfExtent[0]+h[0]*scale+.12)
                if(settleSide!=side)slotPixels[side]=(spacing/(2*halfWidth)*width).toFloat()
                val transform=FloatArray(16);Matrix.setIdentityM(transform,0)
                Matrix.translateM(transform,0,(side*spacing+offset).toFloat(),0f,-4f)
                val amount=if(side==incoming)blend else 0f
                val neighborYaw=(if(side<0)12f else -12f)+sin(t*2*PI/8.5+side).toFloat()*5f
                Matrix.rotateM(transform,0,if(mediaMode||themeMode)idleYaw else neighborYaw*(1-amount)+idleYaw*amount,0f,1f,0f)
                Matrix.rotateM(transform,0,if(mediaMode||themeMode)idlePitch else outgoingPitch*(1-amount)+idlePitch*amount,1f,0f,0f)
                Matrix.scaleM(transform,0,scale,scale,scale);Matrix.translateM(transform,0,-c[0],-c[1],-c[2])
                if(mediaMode)transform[13]+=mediaLift(n.root,(1-abs((side*spacing+offset)/max(.001f,2*h[0]*scale))).toFloat().coerceIn(0f,1f),dt)*.11f*scale
                setPose(n.root,transform)
            }}

            val wanted=if(playing||inspecting||abs(carouselOffset)>.5f||abs(yaw)>.5f||abs(pitch)>.5f)0f else 1f
            rimOpacity=if(inspecting||abs(carouselOffset)>.5f)0f else (wanted+(rimOpacity-wanted)*exp(-dt*10)).toFloat()
            val placements=if(mediaMode){val points=mutableListOf<MediaPlacement>();val cardWidth=(2*halfExtent[0]*width/(2*halfWidth)).toFloat();val bottom=(height*.5+halfExtent[1]*height/(2*fittedHalfHeight)).toFloat()
                for(side in listOf(0,-1,1)){val a=if(side==0)asset else viewer.neighbour(side)?:continue;val id=mediaCovers[a.root]?.id?.takeIf{it.isNotBlank()}?:continue;val cx=width*.5f+carouselOffset+(if(side==0)0f else side*travelPixels(side));points+=MediaPlacement(id,cx,bottom,cardWidth,if(side==0)1-blend else if(side==incoming)blend else 0f)};points.toList()}else emptyList()
            candidate=Presented(RimOverlay.Frame(t/8.5,normalizationScale,fittedHalfHeight,rimOpacity),yaw,pitch,inspecting,envelopeContained,viewer.progress>=1f,width,height,carouselOffset,machine.key,asset.root,if(settleSide==1)settleDistance else travelPixels(1),if(settleSide== -1)settleDistance else travelPixels(-1),(comparisonUnitsPerMM*width/(2*halfWidth)).toFloat(),placements,bookAngle,rootScale(asset.root),rootScale(viewer.neighbour(1)?.root?:0))
            poses.forEach{(entity,base)->
                val name=asset.getName(entity)?:return@forEach
                var pose=base.copyOf()
                val key=if(name.startsWith("key:"))name.substringAfter(':').toIntOrNull() else if(name.startsWith("physical-shoulder:"))name.substringAfter(':').toIntOrNull() else null
                if(key!=null){val target=if(key in held)1f else 0f;val amount=(target+((pressAmounts[entity]?:0f)-target)*exp(-dt*40)).toFloat();pressAmounts[entity]=amount
                    if(name.startsWith("physical-shoulder:"))Matrix.rotateM(pose,0,(if(machine==Machine.PSP)-10.3f else 9.17f)*amount,1f,0f,0f) else pose[14]-=(if(machine==Machine.GBC).060f else 4.2f)*amount}
                if(name.startsWith("utility:")||name=="psp-power-switch"){
                    val utility=if(name=="psp-power-switch")5 else name.substringAfter(':').toInt();val target=if(utility in utilitiesHeld)1f else 0f;val amount=(target+((pressAmounts[entity]?:0f)-target)*exp(-dt*40)).toFloat();pressAmounts[entity]=amount
                    if(utility==5)pose[13]+=.045f*amount else pose[14]-=.025f*amount
                }
                if(name=="dpad"){
                    val dx=(if(7 in held)1 else 0)-(if(6 in held)1 else 0);val dy=(if(5 in held)1 else 0)-(if(4 in held)1 else 0)
                    val length=max(1f,hypot(dx.toFloat(),dy.toFloat()));padX=(dx/length+(padX-dx/length)*exp(-dt*40)).toFloat();padY=(dy/length+(padY-dy/length)*exp(-dt*40)).toFloat();Matrix.rotateM(pose,0,padY*13.2f,1f,0f,0f);Matrix.rotateM(pose,0,padX*13.2f,0f,1f,0f)
                }
                if(name=="stick"){pose=PspStickPose.apply(base,axisX,axisY)}
                setPose(entity,pose)
            }
            if(mediaMode)applyCovers()
            if(playing&&viewer.progress>=1f)updateScreens()
        }
        advanceAssembly(time)
        if(viewer.render(time))candidate?.let{pendingAssemblyFrames[time]=loadingProgress;pendingFrames[time]=it;while(pendingFrames.size>64)pendingFrames.remove(pendingFrames.keys.first())}
        Choreographer.getInstance().postFrameCallback(this)
    }
    private fun rootScale(root:Int):Float{if(root==0)return 0f;val matrix=FloatArray(16);tm.getWorldTransform(tm.getInstance(root),matrix);return sqrt(matrix[0]*matrix[0]+matrix[1]*matrix[1]+matrix[2]*matrix[2])}
    internal fun diagnostics():Map<String,Any> = mapOf("submittedFrames" to viewer.submittedFrames,"surfaceFrames" to viewer.surfaceFrames,"surfaceTime" to viewer.lastSurfaceTime,"renderReady" to viewer.renderReady,"pendingPoses" to pendingFrames.size,"rendererRunning" to running,"resourceLoad" to viewer.resourceDiagnostics(),"surfaceAvailable" to isAvailable,"assetReady" to (presented?.ready==true),"contained" to (presented?.contained?:false),"halfHeight" to (presented?.rim?.halfHeight?:0.0),"yaw" to (presented?.yaw?:0f),"pitch" to (presented?.pitch?:0f),"inspecting" to inspecting,"presentedInspecting" to (presented?.held?:false),"presentedFrames" to presentationCount,"model" to (presented?.modelKey?:machine.key),"primaryRoot" to (presented?.root?:0),"primaryRootScale" to (presented?.rootScale?:0f),"rightRootScale" to (presented?.rightScale?:0f),"rightRoot" to (viewer.neighbour(1)?.root?:0),"rightModel" to (neighbourNames[1]?:""),"leftModel" to (neighbourNames[-1]?:""),"leftRoot" to (viewer.neighbour(-1)?.root?:0),"focusCenterX" to (width*.5f+(presented?.offset?:0f)),"rightCenterX" to (width*.5f+(presented?.offset?:0f)+(presented?.rightTravel?:0f)),"pixelsPerMM" to (presented?.pixelsPerMM?:0f),"neighbours" to neighbourKinds.size,"readyNeighbours" to viewer.readyNeighbours,"carouselOffset" to carouselOffset,"presentedOffset" to (presented?.offset?:0f),"promotions" to promotions,"settleSide" to settleSide,"coverGame" to coverBoundId,"coverMatched" to coverMatched,"mediaMode" to mediaMode,"assemblyStage" to assemblyStage,"mediaLabels" to (presented?.media?.map{mapOf("id" to it.id,"x" to it.x,"bottom" to it.bottom,"width" to it.width)}?:emptyList<Any>()),"presentedBookAngle" to (presented?.bookAngle?:0f),"bookMode" to bookMode,"bookAngle" to bookAngle,"bookTransitioning" to bookTransitioning,"screenBrightness" to screenBrightness,"screenTextureColorSpace" to "display-encoded RGB; isolated ungraded LCD pass","presentedLoadingProgress" to presentedLoadingProgress,"slotEntity" to loadingSlot,"hatchEntity" to loadingHatch,"loadingProgress" to loadingProgress,"doorAngle" to LoadingMotion.door(loadingProgress),"discSpin" to LoadingMotion.spin(loadingProgress),"flightX" to loadingPoint[0],"flightY" to loadingPoint[1],"flightZ" to loadingPoint[2],"coverTextures" to mediaCovers.values.count{it.texture!=null},"leftCover" to (viewer.neighbour(-1)?.root?.let{mediaCovers[it]?.id}?:""),"rightCover" to (viewer.neighbour(1)?.root?.let{mediaCovers[it]?.id}?:""))
    internal var diagnosticScreenRgb:Int?=null
    private fun updateScreens(){
        val probe=diagnosticScreenRgb
        val info=if(probe!=null)intArrayOf(8,8,0,0,0,0,probe+100000) else NativeCore.info();val w=info[0];val dual=machine==Machine.NDS||machine==Machine.N3DS;val h=if(dual)info[1]/2 else info[1]
        if(w<=0||h<=0)return
        val asset=viewer.asset?:return
        asset.renderableEntities.forEach{entity->
            val name=asset.getName(entity)?:"";if(!name.startsWith("screen:"))return@forEach
            val index=name.substringAfter(':').toIntOrNull()?:0
            if(screenDimensions[index]!=Pair(w,h)){
                val retired=screenTextures.remove(index)
                screenTextures[index]=Texture.Builder().width(w).height(h).levels(1).sampler(Texture.Sampler.SAMPLER_2D).format(Texture.InternalFormat.RGBA8).build(viewer.engine)
                screenBuffers[index]=ByteBuffer.allocateDirect(w*h*4);screenDimensions[index]=Pair(w,h)
                val rm=viewer.engine.renderableManager;val instance=rm.getInstance(entity);rm.setLayerMask(instance,0xff,2)
                for(p in 0 until rm.getPrimitiveCount(instance))rm.getMaterialInstanceAt(instance,p).setParameter("baseColorMap",screenTextures.getValue(index),TextureSampler(TextureSampler.MinFilter.NEAREST,TextureSampler.MagFilter.NEAREST,TextureSampler.WrapMode.CLAMP_TO_EDGE))
                retired?.let{viewer.engine.destroyTexture(it)}
            }
            val rm=viewer.engine.renderableManager;val ri=rm.getInstance(entity)
            for(p in 0 until rm.getPrimitiveCount(ri)){val mi=rm.getMaterialInstanceAt(ri,p);if(mi.material.hasParameter("baseColorFactor"))mi.setParameter("baseColorFactor",screenBrightness,screenBrightness,screenBrightness,1f)}
            val serial=info.getOrElse(6){-1}
            if(index in uploadsInFlight||serial>=0&&lastScreenSerial[index]==serial)return@forEach
            val buffer=screenBuffers.getValue(index);buffer.clear()
            val copied=if(probe!=null){repeat(w*h){buffer.put((probe shr 16).toByte());buffer.put((probe shr 8).toByte());buffer.put(probe.toByte());buffer.put(255.toByte())};buffer.flip();w*h*4}else NativeCore.copyFrame(buffer,index,dual)
            if(index !in uploadsInFlight&&copied>0){
                lastScreenSerial[index]=serial;uploadsInFlight.add(index)
                val descriptor=Texture.PixelBufferDescriptor(buffer,Texture.Format.RGBA,Texture.Type.UBYTE)
                val generation=screenGeneration
                descriptor.setCallback(handler,Runnable{if(generation==screenGeneration)uploadsInFlight.remove(index)})
                screenTextures.getValue(index).setImage(viewer.engine,0,descriptor)
            }
        }
    }
    /** Entity-bound hit testing, so side previews do not confirm the focused machine. */
    fun previewPageAt(x:Float,y:Float):Int? {
        val projection=viewer.camera.getProjectionMatrix(DoubleArray(16)).map{it.toFloat()}.toFloatArray()
        val pv=FloatArray(16);Matrix.multiplyMM(pv,0,projection,0,viewer.camera.getViewMatrix(FloatArray(16)),0)
        for(side in listOf(0,-1,1)){
            val a=if(side==0)viewer.asset else viewer.neighbour(side);if(a==null)continue
            val box=viewer.bounds(a);val c=box.center;val h=box.halfExtent;val world=FloatArray(16);tm.getWorldTransform(tm.getInstance(a.root),world)
            val m=FloatArray(16);Matrix.multiplyMM(m,0,pv,0,world,0)
            var left=Float.MAX_VALUE;var top=Float.MAX_VALUE;var right=-Float.MAX_VALUE;var bottom=-Float.MAX_VALUE
            for(i in 0..7){val p=floatArrayOf(c[0]+h[0]*(if(i and 1==0)-1 else 1),c[1]+h[1]*(if(i and 2==0)-1 else 1),c[2]+h[2]*(if(i and 4==0)-1 else 1),1f);val q=FloatArray(4);Matrix.multiplyMV(q,0,m,0,p,0);val sx=(q[0]/q[3]+1)*width/2;val sy=(1-q[1]/q[3])*height/2;left=min(left,sx);right=max(right,sx);top=min(top,sy);bottom=max(bottom,sy)}
            if(x in left..right&&y in top..bottom)return side
        };return null
    }
    /** Ray-plane hit on the actual lower LCD, mapped into the complete dual-screen frame. */
    fun touchAt(x:Float,y:Float):Pair<Float,Float>? {
        if(machine!=Machine.NDS&&machine!=Machine.N3DS)return null
        val a=viewer.asset?:return null;val e=a.entities.firstOrNull{a.getName(it)=="screen:1"}?:return null
        val rm=viewer.engine.renderableManager;val ri=rm.getInstance(e);if(ri==0)return null
        val box=rm.getAxisAlignedBoundingBox(ri,Box());val c=box.center;val h=box.halfExtent
        val p=viewer.camera.getProjectionMatrix(DoubleArray(16)).map{it.toFloat()}.toFloatArray();val pv=FloatArray(16);Matrix.multiplyMM(pv,0,p,0,viewer.camera.getViewMatrix(FloatArray(16)),0)
        val m=FloatArray(16);Matrix.multiplyMM(m,0,pv,0,world(e),0);val inverse=FloatArray(16);if(!Matrix.invertM(inverse,0,m,0))return null
        fun localPoint(z:Float):FloatArray{val out=FloatArray(4);Matrix.multiplyMV(out,0,inverse,0,floatArrayOf(x/width*2-1,1-y/height*2,z,1f),0);return FloatArray(3){out[it]/out[3]}}
        val near=localPoint(-1f);val far=localPoint(1f);val dz=far[2]-near[2];if(abs(dz)<.000001f||h[0]<=0||h[1]<=0)return null
        val t=(c[2]-near[2])/dz;val u=(near[0]+(far[0]-near[0])*t-c[0])/h[0];val v= -(near[1]+(far[1]-near[1])*t-c[1])/h[1]
        if(abs(u)>1||abs(v)>1)return null
        return Pair(u*(if(machine==Machine.N3DS).8f else 1f),(v+1)/2)
    }
    /** Keep a captured stick finger active outside the acquisition circle; clamp to its round gate. */
    fun stickAt(x:Float,y:Float):Pair<Float,Float>? {
        val asset=viewer.asset?:return null
        val entity=asset.entities.firstOrNull{asset.getName(it)=="stick"}?:return null
        val base=poses[entity]?:return null
        val parent=tm.getParent(tm.getInstance(entity));val parentWorld=FloatArray(16)
        if(parent!=0)tm.getWorldTransform(tm.getInstance(parent),parentWorld)else Matrix.setIdentityM(parentWorld,0)
        val neutral=FloatArray(16);Matrix.multiplyMM(neutral,0,parentWorld,0,base,0)
        val ri=viewer.engine.renderableManager.getInstance(entity)
        val c=if(ri!=0)viewer.engine.renderableManager.getAxisAlignedBoundingBox(ri,Box()).center else floatArrayOf(0f,0f,0f)
        val pv=FloatArray(16);Matrix.multiplyMM(pv,0,viewer.camera.getProjectionMatrix(DoubleArray(16)).map{it.toFloat()}.toFloatArray(),0,viewer.camera.getViewMatrix(FloatArray(16)),0)
        val global=point(neutral,c[0],c[1],c[2]);val clip=FloatArray(4);Matrix.multiplyMV(clip,0,pv,0,global,0)
        if(clip[3]<=0)return null
        val radius=60*resources.displayMetrics.density
        return Motion.stick((x-(clip[0]/clip[3]+1)*width/2)/radius,(y-(1-clip[1]/clip[3])*height/2)/radius)
    }
    /** Map a touch to the projected physical controls, using the same model/view matrices. */
    fun controlAt(x:Float,y:Float):Pair<String,Pair<Float,Float>>? {
        val asset=viewer.asset?:return null
        val projection=viewer.camera.getProjectionMatrix(DoubleArray(16)).map{it.toFloat()}.toFloatArray()
        val view=viewer.camera.getViewMatrix(FloatArray(16));val pv=FloatArray(16);Matrix.multiplyMM(pv,0,projection,0,view,0)
        var best:Pair<String,Pair<Float,Float>>?=null;var distance=Float.MAX_VALUE
        asset.entities.forEach{entity->val name=asset.getName(entity)?:return@forEach
            if(!(name.startsWith("key:")||name.startsWith("physical-shoulder:")||name=="dpad"||name=="stick"||name.startsWith("utility:")||name=="psp-power-switch"))return@forEach
            val inst=tm.getInstance(entity);if(inst==0)return@forEach
            val world=FloatArray(16);tm.getWorldTransform(inst,world)
            val rm=viewer.engine.renderableManager;val ri=rm.getInstance(entity);val center=if(ri!=0)rm.getAxisAlignedBoundingBox(ri,Box()).center else floatArrayOf(0f,0f,0f)
            val point=floatArrayOf(center[0],center[1],center[2],1f);val clip=FloatArray(4);val global=FloatArray(4);Matrix.multiplyMV(global,0,world,0,point,0);Matrix.multiplyMV(clip,0,pv,0,global,0)
            if(clip[3]<=0)return@forEach
            val sx=(clip[0]/clip[3]+1)*width/2;val sy=(1-clip[1]/clip[3])*height/2
            val radius=if(name=="dpad"||name=="stick"||name.startsWith("utility:")||name=="psp-power-switch")60*resources.displayMetrics.density else 30*resources.displayMetrics.density
            val d=hypot(x-sx,y-sy)/radius
            if(d<=1&&d<distance){distance=d;val dx=(x-sx)/radius;val dy=(y-sy)/radius;val angle=if(name=="dpad"&&playing&&machine==Machine.NDS)bookAngle*PI.toFloat()/180f else 0f;best=Pair(name,Pair(dx*cos(angle)-dy*sin(angle),dx*sin(angle)+dy*cos(angle)))}
        };return best
    }
}
