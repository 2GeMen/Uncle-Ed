#include "Bridge.h"
#include "StateStore.h"
#include "libretro.h"
#include "Hardware.h"
#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/stat.h>
#include <AudioToolbox/AudioToolbox.h>
static void *lib;static int initialized;static int16_t axes[2][2];
#define FN(ret,name,args) static ret (*name) args
FN(void,p_retro_get_system_info,(struct retro_system_info*));
FN(void,p_retro_init,(void)); FN(void,p_retro_deinit,(void));
FN(void,p_retro_set_environment,(retro_environment_t));FN(void,p_retro_set_video_refresh,(retro_video_refresh_t));
FN(void,p_retro_set_audio_sample,(retro_audio_sample_t));FN(void,p_retro_set_audio_sample_batch,(retro_audio_sample_batch_t));
FN(void,p_retro_set_input_poll,(retro_input_poll_t));FN(void,p_retro_set_input_state,(retro_input_state_t));
FN(bool,p_retro_load_game,(const struct retro_game_info*));FN(void,p_retro_unload_game,(void));FN(void,p_retro_run,(void));
FN(size_t,p_retro_serialize_size,(void));FN(bool,p_retro_serialize,(void*,size_t));FN(bool,p_retro_unserialize,(const void*,size_t));
static int stateUnsafe;static uint64_t stateIdentity;static char statePath[4400],stateError[1024];
FN(void,p_retro_get_system_av_info,(struct retro_system_av_info*));FN(void*,p_retro_get_memory_data,(unsigned));FN(size_t,p_retro_get_memory_size,(unsigned));
static uint32_t pixels[2048*2048];static int width=256,height=384,format=RETRO_PIXEL_FORMAT_0RGB1555;static uint16_t buttons;static int tx,ty,td,loaded;
static double coreFps=59.8261;static int gbMode;
static char directory[4096],savepath[4096],err[1024];static unsigned long frames,audioSamples;
static unsigned long videoSerial;
static char keys[512][128],values[512][512];static int variableCount;
static int diagnosticLegacyCPU,diagnosticLegacyTarget;
static char pspIRValue[128]="IR JIT",coreName[256],coreVersion[256];
static float outputVolume=1.0f;static AudioQueueRef aq;static int16_t ring[262144];static unsigned ri,wi;static AudioQueueBufferRef audioBuffers[3];static int audioStarted;static unsigned audioPriming=3072;static unsigned long audioUnderruns;static unsigned audioMinimum=~0u;
static void audio_cb(void *ctx,AudioQueueRef q,AudioQueueBufferRef b);static pthread_mutex_t lock=PTHREAD_MUTEX_INITIALIZER;
static void log_cb(enum retro_log_level level,const char *fmt,...){if(level<RETRO_LOG_WARN && !getenv("UNCLEED_CORE_DEBUG"))return;va_list a;va_start(a,fmt);vfprintf(stderr,fmt,a);va_end(a);}
static void option(const char *k,const char *v){if(!k||!v||variableCount>=512)return;snprintf(keys[variableCount],128,"%s",k);snprintf(values[variableCount++],512,"%s",v);}
static bool environment(unsigned cmd,void *data){switch(cmd){
case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:case RETRO_ENVIRONMENT_GET_CORE_ASSETS_DIRECTORY:*(const char**)data=directory;return true;
case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:format=*(int*)data;return format<=2;
case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:((struct retro_log_callback*)data)->log=log_cb;return true;
case RETRO_ENVIRONMENT_GET_CAN_DUPE:*(bool*)data=true;return true;
case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:return true;
case RETRO_ENVIRONMENT_GET_LANGUAGE:*(unsigned*)data=RETRO_LANGUAGE_ENGLISH;return true;
case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:*(unsigned*)data=2;return true;
case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2:case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL:{struct retro_core_options_v2 *o= cmd==RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2 ? data:((struct retro_core_options_v2_intl*)data)->us;variableCount=0;if(o&&o->definitions)for(struct retro_core_option_v2_definition *d=o->definitions;d->key;d++){
 option(d->key,d->default_value?d->default_value:d->values[0].value);
 if(!strcmp(d->key,"ppsspp_cpu_core"))for(int i=0;d->values[i].value;i++){
  if((d->values[i].label && !strcmp(d->values[i].label,"IR Interpreter")) || !strcmp(d->values[i].value,"IR JIT")){
   snprintf(pspIRValue,sizeof(pspIRValue),"%s",d->values[i].value);break;
  }
 }
}return true;}
case RETRO_ENVIRONMENT_SET_VARIABLES:{struct retro_variable *v=data;variableCount=0;for(;v&&v->key;v++){const char *p=strchr(v->value,';');if(p){char buf[512];snprintf(buf,512,"%s",p+2);char *s=strchr(buf,'|');if(s)*s=0;option(v->key,buf);}}return true;}
case RETRO_ENVIRONMENT_GET_VARIABLE:{struct retro_variable *v=data;v->value=NULL;
if(!strcmp(v->key,"melonds_jit_enable"))v->value="disabled";
else if(!strcmp(v->key,"meloemu_jit_enable"))v->value="disabled";
else if(!strcmp(v->key,"meloemu_jit_enabled"))v->value="disabled";
else if(!strcmp(v->key,"ppsspp_cpu_core"))v->value=diagnosticLegacyCPU ? "IR Interpreter":pspIRValue;
else if(!strcmp(v->key,"ppsspp_backend"))v->value="opengl";
else if(!strcmp(v->key,"ppsspp_cropto16x9"))v->value="disabled";
else if(!strcmp(v->key,"ppsspp_internal_resolution"))v->value="480x272";
else if(!strcmp(v->key,"citra_graphics_api"))v->value="Vulkan";
else if(!strcmp(v->key,"citra_resolution_factor"))v->value="1";
else if(!strcmp(v->key,"citra_layout_option"))v->value="default";
else if(!strcmp(v->key,"citra_render_3d"))v->value="Off";
else if(!strcmp(v->key,"melonds_console_mode"))v->value="auto";
else if(!strcmp(v->key,"melonds_render_mode"))v->value="software";
else if(!strcmp(v->key,"melonds_screen_layout1"))v->value="top-bottom";
else if(!strcmp(v->key,"melonds_number_of_screen_layouts"))v->value="1";
else if(!strcmp(v->key,"melonds_screen_gap"))v->value="0";
else if(!strcmp(v->key,"melonds_touch_mode"))v->value="touch";
else if(!strcmp(v->key,"melonds_boot_mode"))v->value="direct";
else if(!strcmp(v->key,"meloemu_console_mode"))v->value="DS";
else if(!strcmp(v->key,"meloemu_render_mode"))v->value="software";
else if(!strcmp(v->key,"meloemu_screen_layout1"))v->value="top-bottom";
else if(!strcmp(v->key,"meloemu_number_of_screen_layouts"))v->value="1";
else if(!strcmp(v->key,"meloemu_screen_gap"))v->value="0";
else if(!strcmp(v->key,"meloemu_touch_mode"))v->value="touch";
else if(!strcmp(v->key,"meloemu_boot_mode"))v->value="direct";
else for(int i=0;i<variableCount;i++)if(!strcmp(keys[i],v->key)){v->value=values[i];break;}return v->value!=NULL;}
case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:*(bool*)data=false;return true;
case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_DISPLAY:case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_UPDATE_DISPLAY_CALLBACK:case RETRO_ENVIRONMENT_SET_CONTENT_INFO_OVERRIDE:return true;
case RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE:*(int*)data=3;return true;
case RETRO_ENVIRONMENT_GET_FASTFORWARDING:*(bool*)data=false;return true;
case RETRO_ENVIRONMENT_SET_GEOMETRY:return true;
default:return hardware_environment(cmd,data);}}
static void video(const void *data,unsigned w,unsigned h,size_t pitch){if(!data||w>2048||h>2048||!w||!h)return;if(data==RETRO_HW_FRAME_BUFFER_VALID){if(hardware_read(pixels,w,h)){width=w;height=h;videoSerial++;}return;}width=w;height=h;videoSerial++;for(unsigned y=0;y<h;y++)for(unsigned x=0;x<w;x++){uint32_t c;if(format==RETRO_PIXEL_FORMAT_XRGB8888)c=((const uint32_t*)((const char*)data+y*pitch))[x];else {unsigned s=((const uint16_t*)((const char*)data+y*pitch))[x];unsigned r,g,b;if(format==RETRO_PIXEL_FORMAT_RGB565){r=(s>>11)*255/31;g=((s>>5)&63)*255/63;b=(s&31)*255/31;}else{r=((s>>10)&31)*255/31;g=((s>>5)&31)*255/31;b=(s&31)*255/31;}c=(r<<16)|(g<<8)|b;}pixels[y*w+x]=0xff000000|c;}}
static size_t batch(const int16_t *data,size_t n){pthread_mutex_lock(&lock);for(size_t i=0;i<n*2;i++){if(wi-ri>=262144)ri++;ring[(wi++)%262144]=data[i];}int ready=aq && !audioStarted && wi-ri>=audioPriming;if(ready)audioStarted=1;pthread_mutex_unlock(&lock);audioSamples+=n;
 if(ready){for(int i=0;i<3;i++)audio_cb(NULL,aq,audioBuffers[i]);AudioQueueSetParameter(aq,kAudioQueueParam_Volume,outputVolume);AudioQueueStart(aq,NULL);}
 return n;}
static void sample(int16_t l,int16_t r){int16_t a[2]={l,r};batch(a,1);}
static void audio_cb(void *ctx,AudioQueueRef q,AudioQueueBufferRef b){pthread_mutex_lock(&lock);int16_t *p=b->mAudioData;unsigned available=wi-ri;if(available<audioMinimum)audioMinimum=available;if(available<1024)audioUnderruns+=1024-available;for(unsigned i=0;i<1024;i++)p[i]=ri<wi?ring[(ri++)%262144]:0;pthread_mutex_unlock(&lock);b->mAudioDataByteSize=2048;AudioQueueEnqueueBuffer(q,b,0,NULL);}
static uint64_t inputReads[16],axisReads[2],pointerReads;
static void poll(void){}
static int16_t input(unsigned port,unsigned device,unsigned index,unsigned id){
 if(port)return 0;device &= RETRO_DEVICE_MASK;
 if(device==RETRO_DEVICE_JOYPAD){
  if(id==RETRO_DEVICE_ID_JOYPAD_MASK){for(unsigned i=0;i<16;i++)if(buttons&(1u<<i))inputReads[i]++;return buttons;}
  if(id<16){if(buttons&(1u<<id))inputReads[id]++;return (buttons>>id)&1;}return 0;
 }
 if(device==RETRO_DEVICE_ANALOG && index<2 && id<2){if(index==0 && axes[index][id])axisReads[id]++;return axes[index][id];}
 if(device==RETRO_DEVICE_POINTER){if(id==RETRO_DEVICE_ID_POINTER_X)return tx;if(id==RETRO_DEVICE_ID_POINTER_Y)return ty;if(id==RETRO_DEVICE_ID_POINTER_PRESSED){if(td)pointerReads++;return td;}if(id==RETRO_DEVICE_ID_POINTER_COUNT)return td?1:0;}return 0;
}
uint64_t emu_input_reads(int id){return id>=0 && id<16 ? inputReads[id]:0;}
uint64_t emu_axis_reads(int axis){return axis>=0 && axis<2 ? axisReads[axis]:0;}
uint64_t emu_pointer_reads(void){return pointerReads;}
unsigned emu_input_mask(void){return buttons;}
int emu_axis_value(int axis){return axis>=0 && axis<2 ? axes[0][axis]:0;}

static int writeMemory(unsigned type,const char *path){size_t n=p_retro_get_memory_size(type);void *p=p_retro_get_memory_data(type);if(!n||!p)return 0;char tmp[4400];snprintf(tmp,sizeof(tmp),"%s.tmp",path);FILE *f=fopen(tmp,"wb");if(!f)return 0;size_t wrote=fwrite(p,1,n,f);int ok=fclose(f)==0;if(wrote!=n||!ok)return 0;return rename(tmp,path)==0;}
static void readMemory(unsigned type,const char *path){size_t n=p_retro_get_memory_size(type);void *p=p_retro_get_memory_data(type);if(!n||!p)return;FILE *f=fopen(path,"rb");if(f){fread(p,1,n,f);fclose(f);}}
int emu_save(void){if(!loaded)return 0;int saved=writeMemory(RETRO_MEMORY_SAVE_RAM,savepath);char rtc[4300];snprintf(rtc,sizeof(rtc),"%s.rtc",savepath);writeMemory(RETRO_MEMORY_RTC,rtc);return saved;}
int emu_start(const char *core,const char *rom,const char *data){audioPriming=strstr(core,"ppsspp") ? 10240:3072;const char *ext=strrchr(rom,'.');gbMode=ext && (!strcmp(ext,".gbc") || !strcmp(ext,".gb"));emu_stop();err[0]=0;memset(inputReads,0,sizeof(inputReads));memset(axisReads,0,sizeof(axisReads));pointerReads=0;variableCount=0;format=RETRO_PIXEL_FORMAT_0RGB1555;memset(axes,0,sizeof(axes));snprintf(directory,sizeof(directory),"%s",data);const char *name=strrchr(rom,'/');name=name?name+1:rom;char stem[1024];snprintf(stem,sizeof(stem),"%s",name);char *dot=strrchr(stem,'.');if(dot)*dot=0;snprintf(savepath,sizeof(savepath),"%s/%s.srm",data,stem);lib=dlopen(core,RTLD_NOW|RTLD_LOCAL);if(!lib){snprintf(err,sizeof(err),"%s",dlerror());return 0;}
#define LOAD(n) *(void**)(&n)=dlsym(lib,(#n)+2);if(!n){snprintf(err,sizeof(err),"Missing %s",#n);return 0;}
LOAD(p_retro_get_system_info) LOAD(p_retro_init) LOAD(p_retro_deinit) LOAD(p_retro_set_environment) LOAD(p_retro_set_video_refresh) LOAD(p_retro_set_audio_sample) LOAD(p_retro_set_audio_sample_batch) LOAD(p_retro_set_input_poll) LOAD(p_retro_set_input_state) LOAD(p_retro_load_game) LOAD(p_retro_unload_game) LOAD(p_retro_run) LOAD(p_retro_get_system_av_info) LOAD(p_retro_get_memory_data) LOAD(p_retro_get_memory_size)
p_retro_serialize_size=dlsym(lib,"retro_serialize_size");p_retro_serialize=dlsym(lib,"retro_serialize");p_retro_unserialize=dlsym(lib,"retro_unserialize");stateIdentity=ue_identity(rom,core);snprintf(statePath,sizeof(statePath),"%s",savepath);stateError[0]=0;stateUnsafe=0;
p_retro_set_environment(environment);p_retro_set_video_refresh(video);p_retro_set_audio_sample(sample);p_retro_set_audio_sample_batch(batch);p_retro_set_input_poll(poll);p_retro_set_input_state(input);p_retro_init();initialized=1;
struct retro_system_info info={0};p_retro_get_system_info(&info);snprintf(coreName,sizeof(coreName),"%s",info.library_name?info.library_name:"");snprintf(coreVersion,sizeof(coreVersion),"%s",info.library_version?info.library_version:"");
void *bytes=NULL;size_t size=0;
if(!info.need_fullpath){FILE *f=fopen(rom,"rb");if(!f){snprintf(err,sizeof(err),"ROM not found");emu_stop();return 0;}if(fseek(f,0,SEEK_END)||ftell(f)<0){fclose(f);snprintf(err,sizeof(err),"Cannot read ROM");emu_stop();return 0;}size=(size_t)ftell(f);rewind(f);bytes=malloc(size);if(!bytes||fread(bytes,1,size,f)!=size){free(bytes);fclose(f);snprintf(err,sizeof(err),"Cannot read ROM data");emu_stop();return 0;}fclose(f);}
struct retro_game_info game={rom,bytes,size,NULL};bool ok=p_retro_load_game(&game);free(bytes);if(!ok){snprintf(err,sizeof(err),"Core rejected ROM: %s",hardware_error());emu_stop();return 0;}loaded=1;
struct retro_system_av_info av;p_retro_get_system_av_info(&av);
if(!hardware_resize(diagnosticLegacyTarget ? 2048:av.geometry.base_width,diagnosticLegacyTarget ? 2048:av.geometry.base_height)){snprintf(err,sizeof(err),"%s",hardware_error());emu_stop();return 0;}
if(!hardware_start()){snprintf(err,sizeof(err),"%s",hardware_error());emu_stop();return 0;}
loaded=1;frames=audioSamples=videoSerial=0;buttons=td=0;ri=wi=0;
readMemory(RETRO_MEMORY_SAVE_RAM,savepath);char rtc[4300];snprintf(rtc,sizeof(rtc),"%s.rtc",savepath);readMemory(RETRO_MEMORY_RTC,rtc);
coreFps=av.timing.fps>0 ? av.timing.fps:59.7275;AudioStreamBasicDescription a={0};a.mSampleRate=av.timing.sample_rate;a.mFormatID=kAudioFormatLinearPCM;a.mFormatFlags=kLinearPCMFormatFlagIsSignedInteger|kLinearPCMFormatFlagIsPacked;a.mBytesPerPacket=a.mBytesPerFrame=4;a.mFramesPerPacket=1;a.mChannelsPerFrame=2;a.mBitsPerChannel=16;if(!getenv("NDS_NO_AUDIO") && AudioQueueNewOutput(&a,audio_cb,NULL,NULL,NULL,0,&aq)==noErr){audioStarted=0;audioUnderruns=0;audioMinimum=~0u;for(int i=0;i<3;i++){AudioQueueAllocateBuffer(aq,2048,&audioBuffers[i]);}}return 1;}
static void state_audio_prepare(void){if(aq){AudioQueueStop(aq,true);AudioQueueReset(aq);audioStarted=0;}pthread_mutex_lock(&lock);ri=wi=0;pthread_mutex_unlock(&lock);}
int emu_state_exists(int slot){char path[4608];snprintf(path,sizeof(path),"%s.%s.uestate",statePath,slot==1?"auto":"manual");return loaded&&access(path,R_OK)==0;}
const char* emu_state_error(void){return stateError;}
int emu_state_save(int slot){if(!loaded)return 0;hardware_current();state_audio_prepare();char path[4608];snprintf(path,sizeof(path),"%s.%s.uestate",statePath,slot==1?"auto":"manual");UEStateCore c={p_retro_serialize_size,p_retro_serialize,p_retro_unserialize};return ue_state_save(c,path,stateIdentity,stateError,sizeof(stateError));}
int emu_state_load(int slot){if(!loaded)return 0;hardware_current();state_audio_prepare();char path[4608];snprintf(path,sizeof(path),"%s.%s.uestate",statePath,slot==1?"auto":"manual");UEStateCore c={p_retro_serialize_size,p_retro_serialize,p_retro_unserialize};int result=ue_state_load(c,path,stateIdentity,stateError,sizeof(stateError));if(result == -2)stateUnsafe=1;if(result==1){if(aq){AudioQueueStop(aq,true);AudioQueueReset(aq);audioStarted=0;}pthread_mutex_lock(&lock);ri=wi=0;pthread_mutex_unlock(&lock);buttons=td=0;memset(axes,0,sizeof(axes));}return result;}
void emu_stop(void){if(!initialized){hardware_stop();return;}if(loaded&&!stateUnsafe){if(frames>8)emu_state_save(1);emu_save();}if(aq){AudioQueueStop(aq,true);AudioQueueDispose(aq,true);aq=NULL;}hardware_current();hardware_release_core();if(loaded)p_retro_unload_game();hardware_stop();p_retro_deinit();loaded=initialized=0;/* Keep dylib mapped: core TLS may outlive deinit. */}
void emu_run(void){if(loaded){hardware_current();p_retro_run();frames++;}}void emu_button(int id,int down){if(id<0||id>15)return;if(down)buttons|=1<<id;else buttons&=~(1<<id);}void emu_touch(int x,int y,int down){tx=x;ty=y;td=down;}
const uint32_t *emu_pixels(void){return pixels;}int emu_width(void){return width;}int emu_height(void){return height;}const char *emu_error(void){return err;}unsigned long emu_frames(void){return frames;}unsigned long emu_audio_samples(void){return audioSamples;}
uint64_t emu_sram_hash(void){if(!loaded)return 0;size_t n=p_retro_get_memory_size(RETRO_MEMORY_SAVE_RAM);const unsigned char *p=p_retro_get_memory_data(RETRO_MEMORY_SAVE_RAM);uint64_t h=1469598103934665603ULL;for(size_t i=0;p&&i<n;i++){h^=p[i];h*=1099511628211ULL;}return h;}

double emu_fps(void){return coreFps;}

void emu_volume(float value){outputVolume=value<0?0:(value>1?1:value);if(aq)AudioQueueSetParameter(aq,kAudioQueueParam_Volume,outputVolume);}

void emu_axis(int stick,int axis,int value){if(stick>=0&&stick<2&&axis>=0&&axis<2)axes[stick][axis]=value<-32767?-32767:value>32767?32767:value;}
const char *emu_backend(void){return hardware_backend();}

const char *emu_core_option(const char *key){struct retro_variable v={key,NULL};return environment(RETRO_ENVIRONMENT_GET_VARIABLE,&v) && v.value ? v.value:"";}
const char *emu_core_name(void){return coreName;}
const char *emu_core_version(void){return coreVersion;}
double emu_readback_seconds(void){return hardware_readback_seconds();}
double emu_conversion_seconds(void){return hardware_conversion_seconds();}

unsigned emu_presentation_width(void){return hardware_target_width();}
unsigned emu_presentation_height(void){return hardware_target_height();}

void emu_diagnostic_legacy(int cpu,int target){diagnosticLegacyCPU=cpu;diagnosticLegacyTarget=target;}

unsigned long emu_video_serial(void){return videoSerial;}

unsigned long emu_audio_underruns(void){pthread_mutex_lock(&lock);unsigned long n=audioUnderruns;pthread_mutex_unlock(&lock);return n;}
unsigned emu_audio_buffered(void){pthread_mutex_lock(&lock);unsigned n=wi-ri;pthread_mutex_unlock(&lock);return n;}

uint64_t emu_vram_hash(void){if(!loaded)return 0;size_t n=p_retro_get_memory_size(RETRO_MEMORY_VIDEO_RAM);const void* p=p_retro_get_memory_data(RETRO_MEMORY_VIDEO_RAM);return p&&n?ue_hash(p,n):0;}
