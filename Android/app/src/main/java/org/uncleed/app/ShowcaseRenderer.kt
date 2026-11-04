// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app

import android.graphics.SurfaceTexture
import android.opengl.Matrix
import android.view.Surface
import android.view.TextureView
import android.view.View as AndroidView
import com.google.android.filament.*
import com.google.android.filament.android.DisplayHelper
import com.google.android.filament.android.UiHelper
import com.google.android.filament.gltfio.*
import java.nio.Buffer
import java.nio.ByteBuffer

/** Owns the small Filament lifecycle needed by the product, with explicit presentation
 * timestamps. A CPU animation tick is never treated as proof that a frame is visible.
 */
class ShowcaseRenderer(private val surface:TextureView){
    val engine=Engine.create()
    val renderer=engine.createRenderer()
    val scene=engine.createScene()
    val camera=engine.createCamera(EntityManager.get().create())
    val view=engine.createView()
    private val lcdView=engine.createView()
    var screenPass=false
    val light=EntityManager.get().create()
    private val fillLight=EntityManager.get().create()
    private val spotLight=EntityManager.get().create()
    private var previewLighting=true
    private var spotPower=700000f
    fun setPreviewLighting(value:Boolean){if(previewLighting!=value){previewLighting=value;engine.lightManager.setIntensity(engine.lightManager.getInstance(spotLight),if(value)spotPower else 0f)}}
    /** Preserve source light/object distances after per-model centring and scale. */
    fun setModelLightGeometry(scale:Float,center:FloatArray){
        val lm=engine.lightManager;val fill=lm.getInstance(fillLight);val spot=lm.getInstance(spotLight)
        val energy=(scale/.5f)*(scale/.5f)
        lm.setPosition(fill,(4f-center[0])*scale,(-2f-center[1])*scale,-4f+(8f-center[2])*scale)
        lm.setIntensity(fill,7400000f*energy)
        lm.setPosition(spot,-scale,3f*scale,-4f+(7f-center[2])*scale)
        spotPower=700000f*energy;lm.setIntensity(spot,if(previewLighting)spotPower else 0f)
    }
    var asset:FilamentAsset?=null;private set
    private var primaryBounds:NeighbourModel.Bounds?=null
    fun bounds(a:FilamentAsset):NeighbourModel.Bounds {return (if(a===asset)primaryBounds else neighbours.values.firstOrNull{it.asset===a}?.prepared?.bounds)?:a.boundingBox.let{NeighbourModel.Bounds(it.center,it.halfExtent)}}
    private var primaryReady=false
    val progress get()=if(primaryReady)1f else resources.asyncGetLoadProgress()
    var indirectLightCubemap:Texture?=null
    var onPresented:((Long)->Unit)?=null
    var surfaceFrames=0;private set
    var submittedFrames=0;private set
    var lastSurfaceTime=0L;private set
    val renderReady get()=ui.isReadyToRender&&swapChain!=null
    private val materials=UbershaderProvider(engine)
    private val loader=AssetLoader(engine,materials,EntityManager.get())
    private var resources=ResourceLoader(engine,true)
    private var resourceEpoch=0
    private fun cancelResourceLoad(){
        // Cancellation invalidates provider queues as well as the current asset.
        // A fresh loader prevents cancelled texture jobs contaminating later progress.
        resources.asyncCancelLoad();resources.destroy();resources=ResourceLoader(engine,true);resourceEpoch++
    }
    fun resourceDiagnostics()=mapOf("progress" to resources.asyncGetLoadProgress(),"primaryReady" to primaryReady,"loadingNeighbour" to (loadingNeighbour?.asset?.root?:0),"epoch" to resourceEpoch)
    private val ui=UiHelper(UiHelper.ContextErrorPolicy.DONT_CHECK).apply{isOpaque=false}
    private val display=DisplayHelper(surface.context)
    private var swapChain:SwapChain?=null
    private data class Binding(val material:MaterialInstance,val color:FloatArray)
    private data class Neighbour(val asset:FilamentAsset,val prepared:NeighbourModel.Prepared,var state:Int=0,var tint:Float=1f,var bindings:List<Binding> = emptyList(),var visible:Boolean=true)
    private var primaryPigment:Map<String,FloatArray> = emptyMap()
    private var primaryBindings:List<Binding> = emptyList()
    private var primaryTint=1f
    private var primarySha=""
    private fun bindings(a:FilamentAsset,colors:Map<String,FloatArray>):List<Binding>{
        val found=mutableListOf<Binding>();val rm=engine.renderableManager
        a.renderableEntities.forEach{e->val instance=rm.getInstance(e);for(p in 0 until rm.getPrimitiveCount(instance)){val mi=rm.getMaterialInstanceAt(instance,p);colors[mi.name]?.let{c->if(mi.material.hasParameter("baseColorFactor"))found.add(Binding(mi,c))}}};return found.toList()
    }
    private fun tint(bindings:List<Binding>,amount:Float){bindings.forEach{b->val c=b.color;b.material.setParameter("baseColorFactor",c[0]*amount,c[1]*amount,c[2]*amount,c[3])}}
    fun focusBlend(incoming:Int,progress:Float){
        val p=progress.coerceIn(0f,1f);val target=1f-.72f*p
        if(kotlin.math.abs(primaryTint-target)>.003f){tint(primaryBindings,target);primaryTint=target}
        neighbours.forEach{(side,n)->if(n.state==2){val value=if(side==incoming).28f+.72f*p else .28f;if(kotlin.math.abs(n.tint-value)>.003f){tint(n.bindings,value);n.tint=value}}}
    }
    fun neighbourReady(side:Int)=neighbours[side]?.state==2
    fun removeNeighbour(side:Int){neighbours.remove(side)?.let{n->if(loadingNeighbour===n){cancelResourceLoad();loadingNeighbour=null};scene.removeEntities(n.asset.entities);loader.destroyAsset(n.asset)}}
    fun promoteNeighbour(side:Int):String? {
        val n=neighbours[side]?.takeIf{it.state==2}?:return null
        neighbours.remove(side);neighbours.keys.toList().forEach{removeNeighbour(it)}
        val old=asset?:return null
        val outgoing=Neighbour(old,NeighbourModel.Prepared(ByteBuffer.allocateDirect(0),primaryPigment,primarySha,primaryBounds),2,primaryTint,primaryBindings)
        neighbours[-side]=outgoing
        asset=n.asset;primaryBounds=n.prepared.bounds;primaryPigment=n.prepared.pigment;primaryBindings=n.bindings;primaryTint=n.tint;primarySha=n.prepared.sha;primaryReady=true
        focusBlend(0,0f);return primarySha
    }
    private val neighbours=mutableMapOf<Int,Neighbour>()
    private var loadingNeighbour:Neighbour?=null
    val readyNeighbours get()=neighbours.values.count{it.state==2}
    val liveAssetRoots:Set<Int> get()=neighbours.values.map{it.asset.root}.toSet()+(asset?.root?.let{setOf(it)}?:emptySet())
    fun neighbour(side:Int)=neighbours[side]?.asset
    fun clearNeighbours(){if(loadingNeighbour!=null)cancelResourceLoad();loadingNeighbour=null;neighbours.values.forEach{n->scene.removeEntities(n.asset.entities);loader.destroyAsset(n.asset)};neighbours.clear()}
    fun setNeighbourFocus(side:Int,amount:Float){neighbours[side]?.let{tint(it.bindings,amount);it.tint=amount}}
    fun revealNeighbour(side:Int){neighbours[side]?.visible=true}
    fun updatePigment(a:FilamentAsset,name:String,color:FloatArray){
        val list=if(a===asset)primaryBindings else neighbours.values.firstOrNull{it.asset===a}?.bindings?:return
        val amount=if(a===asset)primaryTint else neighbours.values.first{it.asset===a}.tint
        list.filter{it.material.name==name}.forEach{b->color.copyInto(b.color);tint(listOf(b),amount)}
    }
    fun loadNeighbour(side:Int,prepared:NeighbourModel.Prepared,visible:Boolean=true){
        neighbours.remove(side)?.let{n->if(loadingNeighbour===n){cancelResourceLoad();loadingNeighbour=null};scene.removeEntities(n.asset.entities);loader.destroyAsset(n.asset)}
        val a=loader.createAsset(prepared.buffer)?:return;neighbours[side]=Neighbour(a,prepared,visible=visible)
        val rm=engine.renderableManager
        a.renderableEntities.forEach{e->val i=rm.getInstance(e);if((0 until rm.getPrimitiveCount(i)).any{val mode=rm.getMaterialInstanceAt(i,it).material.blendingMode;mode!=Material.BlendingMode.OPAQUE&&mode!=Material.BlendingMode.MASKED})rm.setCastShadows(i,false)}
    }
    private val ready=IntArray(128)
    private var destroyed=false
    init {
        view.scene=scene;view.camera=camera
        lcdView.scene=scene;lcdView.camera=camera;lcdView.setVisibleLayers(0xff,2);lcdView.isPostProcessingEnabled=false;lcdView.blendMode=View.BlendMode.TRANSLUCENT
        camera.setExposure(16f,1f/125,100f)
        camera.lookAt(0.0,0.0,0.0,0.0,0.0,-4.0,0.0,1.0,0.0)
        LightManager.Builder(LightManager.Type.DIRECTIONAL).color(1f,1f,1f).intensity(100000f).direction(0f,-1f,0f).castShadows(false).build(engine,light)
        scene.addEntity(light)
        // Same key/fill/warm spot arrangement as SpatialSurface / SpatialPreview.
        // SceneKit intensity and Filament lux/lumens have different units.
        LightManager.Builder(LightManager.Type.POINT).color(1f,1f,1f).position(2f,-1f,0f).intensity(7400000f).falloff(12f).castShadows(false).build(engine,fillLight)
        LightManager.Builder(LightManager.Type.SPOT).color(1f,.94f,.82f).position(-.5f,1.5f,-.5f).direction(.13f,-.39f,-.91f).intensity(700000f).falloff(10f).spotLightCone(Math.toRadians(14.0).toFloat(),Math.toRadians(32.5).toFloat()).castShadows(false).build(engine,spotLight)
        scene.addEntity(fillLight);scene.addEntity(spotLight)
        ui.renderCallback=object:UiHelper.RendererCallback{
            override fun onNativeWindowChanged(window:Surface){swapChain?.let{engine.destroySwapChain(it)};swapChain=engine.createSwapChain(window,ui.swapChainFlags);display.attach(renderer,surface.display)}
            override fun onDetachedFromSurface(){display.detach();swapChain?.let{engine.destroySwapChain(it);engine.flushAndWait()};swapChain=null}
            override fun onResized(width:Int,height:Int){view.viewport=Viewport(0,0,width,height);lcdView.viewport=Viewport(0,0,width,height);val fence=engine.createFence();fence.wait(Fence.Mode.FLUSH,Fence.WAIT_FOR_EVER);engine.destroyFence(fence)}
        }
        ui.attachTo(surface)
        val delegate=checkNotNull(surface.surfaceTextureListener)
        surface.surfaceTextureListener=object:TextureView.SurfaceTextureListener{
            override fun onSurfaceTextureAvailable(texture:SurfaceTexture,w:Int,h:Int)=delegate.onSurfaceTextureAvailable(texture,w,h)
            override fun onSurfaceTextureSizeChanged(texture:SurfaceTexture,w:Int,h:Int)=delegate.onSurfaceTextureSizeChanged(texture,w,h)
            override fun onSurfaceTextureDestroyed(texture:SurfaceTexture)=delegate.onSurfaceTextureDestroyed(texture)
            override fun onSurfaceTextureUpdated(texture:SurfaceTexture){delegate.onSurfaceTextureUpdated(texture);surfaceFrames++;lastSurfaceTime=texture.timestamp;onPresented?.invoke(texture.timestamp)}
        }
        surface.addOnAttachStateChangeListener(object:AndroidView.OnAttachStateChangeListener{
            override fun onViewAttachedToWindow(view:AndroidView){}
            override fun onViewDetachedFromWindow(view:AndroidView){destroy()}
        })
    }
    fun loadModelGlb(buffer:ByteBuffer,sha:String){destroyModel();primaryReady=false;primaryBounds=NeighbourModel.bounds(buffer);primaryPigment=NeighbourModel.pigments(buffer);primarySha=sha;primaryTint=1f;asset=checkNotNull(loader.createAsset(buffer)){"Unable to create 3D asset"};asset?.let{primaryBindings=bindings(it,primaryPigment);check(resources.asyncBeginLoad(it)){"Unable to begin primary resources"};it.releaseSourceData()}}
    fun transformToUnitCube(){asset?.let{a->val box=a.boundingBox;val c=box.center;val h=box.halfExtent;val q=1f/maxOf(h[0],h[1],h[2]);val m=FloatArray(16);Matrix.setIdentityM(m,0);Matrix.translateM(m,0,0f,0f,-4f);Matrix.scaleM(m,0,q,q,q);Matrix.translateM(m,0,-c[0],-c[1],-c[2]);engine.transformManager.setTransform(engine.transformManager.getInstance(a.root),m)}}
    fun render(time:Long):Boolean {
        val target=swapChain?:return false
        if(!ui.isReadyToRender)return false
        resources.asyncUpdateLoad()
        asset?.let{a->while(true){val count=a.popRenderables(ready);if(count==0)break;scene.addEntities(ready.copyOf(count))}}
        if(resources.asyncGetLoadProgress()>=1f){
            if(loadingNeighbour!=null){loadingNeighbour?.let{n->
                n.bindings=bindings(n.asset,n.prepared.pigment);tint(n.bindings,.28f);n.tint=.28f
                n.state=2
            };loadingNeighbour=null}else primaryReady=true
        }
        // One async resource owner; publish neighbours only after their original
        // alpha textures and material bindings have completed loading.
        if(primaryReady&&loadingNeighbour==null){neighbours.values.firstOrNull{it.state==0}?.let{n->n.state=1;loadingNeighbour=n;check(resources.asyncBeginLoad(n.asset)){"Unable to begin neighbouring resources"};n.asset.releaseSourceData()}}
        neighbours.values.filter{it.state==2&&it.visible}.forEach{n->while(true){val count=n.asset.popRenderables(ready);if(count==0)break;scene.addEntities(ready.copyOf(count))}}
        if(!renderer.beginFrame(target,time))return false
        // Android SurfaceTexture reports this exact timestamp when it latches this
        // buffer, allowing masks and diagnostics to follow the displayed pose.
        renderer.setPresentationTime(time)
        view.setVisibleLayers(0xff,if(screenPass)1 else 0xff)
        renderer.render(view);if(screenPass)renderer.render(lcdView);renderer.endFrame();submittedFrames++;return true
    }
    internal fun clearModel()=destroyModel()
    private fun destroyModel(){clearNeighbours();cancelResourceLoad();asset?.let{scene.removeEntities(it.entities);loader.destroyAsset(it)};asset=null}
    private fun destroy(){
        if(destroyed)return;destroyed=true;ui.detach();destroyModel();loader.destroy();materials.destroyMaterials();materials.destroy();resources.destroy()
        indirectLightCubemap?.let{engine.destroyTexture(it)};indirectLightCubemap=null
        for(entity in listOf(light,fillLight,spotLight)){engine.destroyEntity(entity);EntityManager.get().destroy(entity)}
        engine.destroyRenderer(renderer);engine.destroyView(lcdView);engine.destroyView(view);engine.destroyScene(scene);engine.destroyCameraComponent(camera.entity);EntityManager.get().destroy(camera.entity);engine.destroy()
    }
}
