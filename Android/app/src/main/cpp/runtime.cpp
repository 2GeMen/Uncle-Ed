// SPDX-License-Identifier: GPL-3.0-or-later
// Uncle Ed Android libretro host. No emulator implementation or game content.
#include <jni.h>
#include "libretro.h"
#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include "FrameReadback.h"
#include "AtomicSave.h"
#include "StateStore.h"
#include <android/log.h>
#include <dlfcn.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <atomic>
#include <mutex>
#include <vector>
#include <map>
#include <string>
#include <fstream>
#include <algorithm>
#include <cstdarg>
#include <cstring>
#include <chrono>
namespace {
std::mutex frameLock,audioLock,runLock;
std::vector<uint8_t> pixels(2048*2048*4),scratch(2048*2048*4);
std::vector<int16_t> audio(262144);uint64_t readIndex=0,writeIndex=0;
std::atomic<int> keys{0},ax{0},ay{0},px{0},py{0},pressed{0};
std::atomic<uint64_t> frames{0},videoSerial{0},overruns{0};
std::atomic<int64_t> nativeRunMicros{0},videoCallbackMicros{0};
struct VideoMeasure {std::chrono::steady_clock::time_point begin=std::chrono::steady_clock::now();~VideoMeasure(){videoCallbackMicros.fetch_add(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-begin).count());}};
int width=0,height=0,format=RETRO_PIXEL_FORMAT_0RGB1555,rate=48000;double fps=60;
std::string saveError;
bool stateUnsafe=false;uint64_t stateIdentity=0;char stateError[1024]={0};
size_t (*stateSize)()=nullptr;bool (*stateSave)(void*,size_t)=nullptr;bool (*stateLoad)(const void*,size_t)=nullptr;

std::string error,systemDir,saveDir,saveName;void* handle=nullptr;bool loaded=false,initialized=false;
void* mapping=MAP_FAILED;size_t mappingSize=0;std::map<std::string,std::string> options;std::map<std::string,void*> coreHandles;
GLuint outputFbo=0,outputColor=0,outputDepth=0;
FrameReadback readback;
retro_hw_render_callback hw{};EGLDisplay display=EGL_NO_DISPLAY;EGLContext context=EGL_NO_CONTEXT;EGLSurface surface=EGL_NO_SURFACE;
#define API(ret,name,args) ret (*name) args = nullptr
API(void,p_retro_init,(void));API(void,p_retro_deinit,(void));API(void,p_retro_run,(void));API(bool,p_retro_load_game,(const retro_game_info*));API(void,p_retro_unload_game,(void));API(void,p_retro_get_system_info,(retro_system_info*));API(void,p_retro_get_system_av_info,(retro_system_av_info*));API(void,p_retro_set_environment,(retro_environment_t));API(void,p_retro_set_video_refresh,(retro_video_refresh_t));API(void,p_retro_set_audio_sample,(retro_audio_sample_t));API(void,p_retro_set_audio_sample_batch,(retro_audio_sample_batch_t));API(void,p_retro_set_input_poll,(retro_input_poll_t));API(void,p_retro_set_input_state,(retro_input_state_t));API(void*,p_retro_get_memory_data,(unsigned));API(size_t,p_retro_get_memory_size,(unsigned));
std::string str(JNIEnv* e,jstring s){const char* p=e->GetStringUTFChars(s,nullptr);std::string r=p;e->ReleaseStringUTFChars(s,p);return r;}
void logMessage(retro_log_level level,const char* fmt,...){if(level<RETRO_LOG_WARN)return;char b[2048];va_list ap;va_start(ap,fmt);vsnprintf(b,sizeof(b),fmt,ap);va_end(ap);__android_log_write(ANDROID_LOG_WARN,"UncleEdCore",b);}
uintptr_t framebuffer(){return outputFbo;}
retro_proc_address_t procedure(const char* n){auto p=eglGetProcAddress(n);return reinterpret_cast<retro_proc_address_t>(p);}
void destroyGL(){if(display!=EGL_NO_DISPLAY){if(context!=EGL_NO_CONTEXT&&eglMakeCurrent(display,surface,surface,context)){readback.reset();if(outputFbo)glDeleteFramebuffers(1,&outputFbo);if(outputColor)glDeleteTextures(1,&outputColor);if(outputDepth)glDeleteRenderbuffers(1,&outputDepth);}outputFbo=outputColor=outputDepth=0;eglMakeCurrent(display,EGL_NO_SURFACE,EGL_NO_SURFACE,EGL_NO_CONTEXT);if(surface!=EGL_NO_SURFACE)eglDestroySurface(display,surface);if(context!=EGL_NO_CONTEXT)eglDestroyContext(display,context);/* The default EGLDisplay is shared with Filament: do not terminate it. */}surface=EGL_NO_SURFACE;context=EGL_NO_CONTEXT;display=EGL_NO_DISPLAY;}
bool createGL(){
 display=eglGetDisplay(EGL_DEFAULT_DISPLAY);if(!eglInitialize(display,nullptr,nullptr))return false;
 // Filament already requires GLES3; its context also hosts GLES2-compatible cores.
 int version=3;
 EGLint attributes[]={EGL_SURFACE_TYPE,EGL_PBUFFER_BIT,EGL_RENDERABLE_TYPE,version==3?EGL_OPENGL_ES3_BIT:EGL_OPENGL_ES2_BIT,EGL_RED_SIZE,8,EGL_GREEN_SIZE,8,EGL_BLUE_SIZE,8,EGL_ALPHA_SIZE,8,EGL_DEPTH_SIZE,24,EGL_STENCIL_SIZE,8,EGL_NONE};EGLConfig config;EGLint count;
 if(!eglChooseConfig(display,attributes,&config,1,&count)||!count)return false;
 EGLint ca[]={EGL_CONTEXT_CLIENT_VERSION,version,EGL_NONE},sa[]={EGL_WIDTH,2048,EGL_HEIGHT,2048,EGL_NONE};
 context=eglCreateContext(display,config,EGL_NO_CONTEXT,ca);surface=eglCreatePbufferSurface(display,config,sa);
 if(context==EGL_NO_CONTEXT||surface==EGL_NO_SURFACE||!eglMakeCurrent(display,surface,surface,context))return false;
 // A frontend-owned target has explicit dimensions and survives core FBO changes.
 retro_system_av_info av{};p_retro_get_system_av_info(&av);const int w=std::max(av.geometry.base_width,av.geometry.max_width),h=std::max(av.geometry.base_height,av.geometry.max_height);if(w<1||h<1||w>2048||h>2048)return false;
 glGenTextures(1,&outputColor);glBindTexture(GL_TEXTURE_2D,outputColor);glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA,w,h,0,GL_RGBA,GL_UNSIGNED_BYTE,nullptr);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
 glGenRenderbuffers(1,&outputDepth);glBindRenderbuffer(GL_RENDERBUFFER,outputDepth);glRenderbufferStorage(GL_RENDERBUFFER,GL_DEPTH24_STENCIL8,w,h);
 glGenFramebuffers(1,&outputFbo);glBindFramebuffer(GL_FRAMEBUFFER,outputFbo);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,outputColor,0);glFramebufferRenderbuffer(GL_FRAMEBUFFER,GL_DEPTH_STENCIL_ATTACHMENT,GL_RENDERBUFFER,outputDepth);
 return glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE;
}
bool environment(unsigned cmd,void* data){switch(cmd){
 case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:*static_cast<const char**>(data)=saveDir.c_str();return true;
 case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:case RETRO_ENVIRONMENT_GET_CORE_ASSETS_DIRECTORY:*static_cast<const char**>(data)=systemDir.c_str();return true;
 case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:format=*static_cast<int*>(data);return format>=0&&format<=2;
 case RETRO_ENVIRONMENT_GET_CAN_DUPE:*static_cast<bool*>(data)=true;return true;
 case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:return true;
 case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:static_cast<retro_log_callback*>(data)->log=logMessage;return true;
 case RETRO_ENVIRONMENT_GET_LANGUAGE:*static_cast<unsigned*>(data)=RETRO_LANGUAGE_ENGLISH;return true;
 case RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE:*static_cast<int*>(data)=3;return true;
 case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:*static_cast<unsigned*>(data)=2;return true;
 case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2:case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL:{auto o=cmd==RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2?static_cast<retro_core_options_v2*>(data):static_cast<retro_core_options_v2_intl*>(data)->us;options.clear();for(auto d=o?o->definitions:nullptr;d&&d->key;d++)options[d->key]=d->default_value?d->default_value:d->values[0].value;return true;}
 case RETRO_ENVIRONMENT_SET_VARIABLES:{auto v=static_cast<retro_variable*>(data);for(;v&&v->key;v++){std::string s=v->value?v->value:"";auto n=s.find(';');if(n!=std::string::npos){s=s.substr(n+1);while(!s.empty()&&s[0]==' ')s.erase(0,1);s=s.substr(0,s.find('|'));options[v->key]=s;}}return true;}
 case RETRO_ENVIRONMENT_GET_VARIABLE:{auto v=static_cast<retro_variable*>(data);std::string k=v->key;const char* forced=nullptr;
  if(k=="ppsspp_enable_wlan")forced="disabled";if(k=="ppsspp_backend")forced="opengl";if(k=="ppsspp_internal_resolution")forced="480x272";if(k=="ppsspp_cropto16x9")forced="disabled";
  if(k=="melonds_network_mode")forced="disabled";if(k=="melonds_sysfile_mode")forced="builtin";if(k=="melonds_render_mode")forced="software";if(k=="melonds_screen_layout1")forced="top-bottom";if(k=="melonds_screen_gap")forced="0";if(k=="melonds_console_mode")forced="ds";if(k=="melonds_boot_mode")forced="direct";
  auto i=options.find(k);v->value=forced?forced:(i!=options.end()?i->second.c_str():nullptr);return v->value!=nullptr;}
 case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:*static_cast<bool*>(data)=false;return true;
 case RETRO_ENVIRONMENT_SET_HW_RENDER:{auto requested=static_cast<retro_hw_render_callback*>(data);if(requested->context_type!=RETRO_HW_CONTEXT_OPENGLES2&&requested->context_type!=RETRO_HW_CONTEXT_OPENGLES3&&requested->context_type!=RETRO_HW_CONTEXT_OPENGLES_VERSION){error="This core requests an unsupported graphics API";return false;}requested->get_current_framebuffer=framebuffer;requested->get_proc_address=procedure;hw=*requested;return true;}
 case RETRO_ENVIRONMENT_SET_GEOMETRY:case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_DISPLAY:case RETRO_ENVIRONMENT_SET_CONTENT_INFO_OVERRIDE:return true;
 default:return false;
}}
void video(const void* data,unsigned w,unsigned h,size_t pitch){if(!data||!w||!h||w>2048||h>2048)return;
 VideoMeasure measured;
 // GPU completion and pixel conversion must never hold the UI frame lock.
 if(data==RETRO_HW_FRAME_BUFFER_VALID){
  if(!readback.read(outputFbo,w,h,hw.bottom_left_origin,scratch.data()))return;}
 else for(unsigned y=0;y<h;y++)for(unsigned x=0;x<w;x++){unsigned c;if(format==RETRO_PIXEL_FORMAT_XRGB8888)c=reinterpret_cast<const uint32_t*>(static_cast<const uint8_t*>(data)+y*pitch)[x];else{unsigned s=reinterpret_cast<const uint16_t*>(static_cast<const uint8_t*>(data)+y*pitch)[x];unsigned r,g,b;if(format==RETRO_PIXEL_FORMAT_RGB565){r=(s>>11)*255/31;g=((s>>5)&63)*255/63;b=(s&31)*255/31;}else{r=((s>>10)&31)*255/31;g=((s>>5)&31)*255/31;b=(s&31)*255/31;}c=r<<16|g<<8|b;}auto o=(y*w+x)*4;scratch[o]=c>>16;scratch[o+1]=c>>8;scratch[o+2]=c;scratch[o+3]=255;}
 {std::lock_guard<std::mutex> lock(frameLock);pixels.swap(scratch);width=w;height=h;videoSerial++;}
}
size_t batch(const int16_t* data,size_t count){std::lock_guard<std::mutex> lock(audioLock);for(size_t i=0;i<count*2;i++){if(writeIndex-readIndex>=audio.size()){readIndex++;overruns++;}audio[writeIndex++%audio.size()]=data[i];}return count;}
void sample(int16_t l,int16_t r){int16_t b[]={l,r};batch(b,1);}
void poll(){}
int16_t input(unsigned port,unsigned device,unsigned index,unsigned id){if(port)return 0;if(device==RETRO_DEVICE_JOYPAD)return id==RETRO_DEVICE_ID_JOYPAD_MASK?keys.load():(id<16?(keys.load()>>id)&1:0);if(device==RETRO_DEVICE_ANALOG&&index==0)return id==0?ax.load():ay.load();if(device==RETRO_DEVICE_POINTER){if(id==RETRO_DEVICE_ID_POINTER_X)return px;if(id==RETRO_DEVICE_ID_POINTER_Y)return py;if(id==RETRO_DEVICE_ID_POINTER_PRESSED||id==RETRO_DEVICE_ID_POINTER_COUNT)return pressed;}return 0;}
int stateOperation(bool restore,int slot){if(!loaded)return 0;if(display!=EGL_NO_DISPLAY)eglMakeCurrent(display,surface,surface,context);std::string path=saveName+(slot==1?".auto.uestate":".manual.uestate");UEStateCore c={stateSize,stateSave,stateLoad};int result=restore?ue_state_load(c,path.c_str(),stateIdentity,stateError,sizeof(stateError)):ue_state_save(c,path.c_str(),stateIdentity,stateError,sizeof(stateError));if(result == -2)stateUnsafe=true;if(restore&&result==1){keys=0;ax=ay=px=py=pressed=0;readback.reset();std::lock_guard<std::mutex> lock(audioLock);readIndex=writeIndex=0;}return result;}
bool save(){if(!loaded)return true;if(stateUnsafe)return false;bool ok=true;for(auto type:{RETRO_MEMORY_SAVE_RAM,RETRO_MEMORY_RTC}){size_t n=p_retro_get_memory_size(type);auto p=p_retro_get_memory_data(type);if(!p||!n)continue;auto name=saveName+(type==RETRO_MEMORY_RTC?".rtc":".srm");if(!uncleed::writeSaveAtomically(name,p,n))ok=false;}saveError=ok?"":"Cartridge save write failed; previous file preserved";return ok;}
void stop(){keys=0;ax=ay=px=py=pressed=0;if(initialized){if(loaded&&!stateUnsafe&&frames>8)stateOperation(false,1);save();if(loaded)p_retro_unload_game();if(context!=EGL_NO_CONTEXT&&hw.context_destroy)hw.context_destroy();p_retro_deinit();}destroyGL();loaded=initialized=false;hw={};if(mapping!=MAP_FAILED)munmap(mapping,mappingSize);mapping=MAP_FAILED;/* Keep core TLS code mapped until process exit. */handle=nullptr;std::lock_guard<std::mutex> lock(audioLock);readIndex=writeIndex=0;}
}
extern "C" JNIEXPORT jboolean JNICALL Java_org_uncleed_app_NativeCore_load(JNIEnv* e,jobject,jstring core,jstring rom,jstring dir,jstring savePath){std::lock_guard<std::mutex> lock(runLock);stop();error.clear();saveError.clear();systemDir=str(e,dir);saveName=str(e,savePath);saveDir=saveName.substr(0,saveName.find_last_of('/'));auto file=str(e,rom);auto lib="lib"+str(e,core)+".so";handle=coreHandles.count(lib)?coreHandles[lib]:dlopen(lib.c_str(),RTLD_NOW|RTLD_LOCAL);if(handle)coreHandles[lib]=handle;if(!handle){error=dlerror();return false;}
#define LOAD(name) name=reinterpret_cast<decltype(name)>(dlsym(handle, &(#name)[2]));if(!name){error="Core is missing " #name;return false;}
 LOAD(p_retro_init);LOAD(p_retro_deinit);LOAD(p_retro_run);LOAD(p_retro_load_game);LOAD(p_retro_unload_game);LOAD(p_retro_get_system_info);LOAD(p_retro_get_system_av_info);LOAD(p_retro_set_environment);LOAD(p_retro_set_video_refresh);LOAD(p_retro_set_audio_sample);LOAD(p_retro_set_audio_sample_batch);LOAD(p_retro_set_input_poll);LOAD(p_retro_set_input_state);LOAD(p_retro_get_memory_data);LOAD(p_retro_get_memory_size);
 stateSize=reinterpret_cast<decltype(stateSize)>(dlsym(handle,"retro_serialize_size"));stateSave=reinterpret_cast<decltype(stateSave)>(dlsym(handle,"retro_serialize"));stateLoad=reinterpret_cast<decltype(stateLoad)>(dlsym(handle,"retro_unserialize"));Dl_info location{};dladdr(reinterpret_cast<void*>(stateSize),&location);stateIdentity=ue_identity(file.c_str(),location.dli_fname?location.dli_fname:lib.c_str());stateError[0]=0;stateUnsafe=false;
 options.clear();format=RETRO_PIXEL_FORMAT_0RGB1555;{std::lock_guard<std::mutex> frame(frameLock);width=height=0;std::fill(pixels.begin(),pixels.end(),0);}
 p_retro_set_environment(environment);p_retro_set_video_refresh(video);p_retro_set_audio_sample(sample);p_retro_set_audio_sample_batch(batch);p_retro_set_input_poll(poll);p_retro_set_input_state(input);p_retro_init();initialized=true;retro_system_info info{};p_retro_get_system_info(&info);retro_game_info game{file.c_str(),nullptr,0,nullptr};if(!info.need_fullpath){int fd=open(file.c_str(),O_RDONLY);struct stat st{};if(fd<0||fstat(fd,&st)||st.st_size<=0){if(fd>=0)close(fd);error="Cannot read ROM";stop();return false;}mappingSize=st.st_size;mapping=mmap(nullptr,mappingSize,PROT_READ,MAP_PRIVATE,fd,0);close(fd);if(mapping==MAP_FAILED){error="Cannot map ROM";stop();return false;}game.data=mapping;game.size=mappingSize;}
 if(!p_retro_load_game(&game)){error="Core rejected the selected file";stop();return false;}loaded=true;if(hw.context_reset){if(!createGL()){error="Cannot create the core's OpenGL ES context";stop();return false;}hw.context_reset();}
 retro_system_av_info av{};p_retro_get_system_av_info(&av);fps=av.timing.fps>1?av.timing.fps:60;rate=av.timing.sample_rate>0?av.timing.sample_rate:48000;width=av.geometry.base_width;height=av.geometry.base_height;frames=videoSerial=overruns=0;
 for(auto type:{RETRO_MEMORY_SAVE_RAM,RETRO_MEMORY_RTC}){auto p=p_retro_get_memory_data(type);auto n=p_retro_get_memory_size(type);if(p&&n){std::ifstream f(saveName+(type==RETRO_MEMORY_RTC?".rtc":".srm"),std::ios::binary);if(f)f.read(static_cast<char*>(p),n);}}return true;}
extern "C" JNIEXPORT void JNICALL Java_org_uncleed_app_NativeCore_run(JNIEnv*,jobject){std::lock_guard<std::mutex> lock(runLock);if(loaded){auto begin=std::chrono::steady_clock::now();videoCallbackMicros.store(0);if(display!=EGL_NO_DISPLAY)eglMakeCurrent(display,surface,surface,context);p_retro_run();nativeRunMicros.store(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-begin).count());frames++;}}
extern "C" JNIEXPORT void JNICALL Java_org_uncleed_app_NativeCore_stop(JNIEnv*,jobject){std::lock_guard<std::mutex> lock(runLock);stop();}
extern "C" JNIEXPORT void JNICALL Java_org_uncleed_app_NativeCore_input(JNIEnv*,jobject,jint mask,jint x,jint y,jint touchX,jint touchY,jboolean down){keys=mask;ax=x;ay=y;px=touchX;py=touchY;pressed=down?1:0;}
extern "C" JNIEXPORT jintArray JNICALL Java_org_uncleed_app_NativeCore_info(JNIEnv* e,jobject){std::lock_guard<std::mutex> frame(frameLock);jint values[]={width,height,rate,static_cast<int>(fps*1000),static_cast<int>(frames.load()),static_cast<int>(overruns.load()),static_cast<int>(videoSerial.load())};auto a=e->NewIntArray(7);e->SetIntArrayRegion(a,0,7,values);return a;}
extern "C" JNIEXPORT jint JNICALL Java_org_uncleed_app_NativeCore_copyFrame(JNIEnv* e,jobject,jobject buffer,jint screen,jboolean dual){std::lock_guard<std::mutex> lock(frameLock);int h=dual?height/2:height;size_t n=width*h*4;auto p=e->GetDirectBufferAddress(buffer);if(!p||n>static_cast<size_t>(e->GetDirectBufferCapacity(buffer)))return 0;memcpy(p,pixels.data()+(dual&&screen==1?n:0),n);return n;}
extern "C" JNIEXPORT jint JNICALL Java_org_uncleed_app_NativeCore_pullAudio(JNIEnv* e,jobject,jobject buffer){auto p=static_cast<int16_t*>(e->GetDirectBufferAddress(buffer));auto capacity=e->GetDirectBufferCapacity(buffer)/2;if(!p)return 0;std::lock_guard<std::mutex> lock(audioLock);size_t n=std::min<uint64_t>(capacity,writeIndex-readIndex);for(size_t i=0;i<n;i++)p[i]=audio[readIndex++%audio.size()];return n*2;}
extern "C" JNIEXPORT jstring JNICALL Java_org_uncleed_app_NativeCore_error(JNIEnv* e,jobject){return e->NewStringUTF(error.c_str());}

extern "C" JNIEXPORT jboolean JNICALL Java_org_uncleed_app_NativeCore_flushSave(JNIEnv*,jobject){std::lock_guard<std::mutex> lock(runLock);return save();}
extern "C" JNIEXPORT jstring JNICALL Java_org_uncleed_app_NativeCore_saveError(JNIEnv* e,jobject){std::lock_guard<std::mutex> lock(runLock);return e->NewStringUTF(saveError.c_str());}

extern "C" JNIEXPORT jlongArray JNICALL Java_org_uncleed_app_NativeCore_timing(JNIEnv* e,jobject){jlong values[]={nativeRunMicros.load(),videoCallbackMicros.load()};auto a=e->NewLongArray(2);e->SetLongArrayRegion(a,0,2,values);return a;}

extern "C" JNIEXPORT jint JNICALL Java_org_uncleed_app_NativeCore_stateOperation(JNIEnv*,jobject,jboolean restore,jint slot){std::lock_guard<std::mutex> lock(runLock);return stateOperation(restore,slot);}
extern "C" JNIEXPORT jstring JNICALL Java_org_uncleed_app_NativeCore_stateError(JNIEnv* e,jobject){std::lock_guard<std::mutex> lock(runLock);return e->NewStringUTF(stateError);}

extern "C" JNIEXPORT void JNICALL Java_org_uncleed_app_NativeCore_stateIdentity(JNIEnv* e,jobject,jstring rom,jstring core){std::lock_guard<std::mutex> lock(runLock);auto key=str(e,rom)+"|"+str(e,core);stateIdentity=ue_hash(key.data(),key.size());}
