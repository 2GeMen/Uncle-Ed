#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES3/gl.h>
#include "Hardware.h"
#include "libretro.h"
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
static double readbackSeconds,conversionSeconds;
static double monotonic_seconds(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
static EAGLContext *context;
static struct retro_hw_render_callback hw;
static GLuint framebufferID,textureID,depthID;
static bool resetCalled;
static unsigned presentationWidth=2048,presentationHeight=2048;
static char errorText[256];
static uintptr_t framebuffer(void){return framebufferID;}
static retro_proc_address_t proc(const char *name){return (retro_proc_address_t)dlsym(RTLD_DEFAULT,name);}
bool hardware_environment(unsigned cmd,void *data){
    if(cmd==RETRO_ENVIRONMENT_GET_PREFERRED_HW_RENDER){*(enum retro_hw_context_type*)data=RETRO_HW_CONTEXT_OPENGLES3;return true;}
    if(cmd==RETRO_ENVIRONMENT_SET_HW_SHARED_CONTEXT)return true;
    if(cmd!=RETRO_ENVIRONMENT_SET_HW_RENDER)return false;
    struct retro_hw_render_callback *requested=data;
    if(requested->context_type!=RETRO_HW_CONTEXT_OPENGLES2 && requested->context_type!=RETRO_HW_CONTEXT_OPENGLES3 && requested->context_type!=RETRO_HW_CONTEXT_OPENGLES_VERSION){snprintf(errorText,sizeof(errorText),"This iOS build requires an OpenGL ES or software core; Vulkan/desktop OpenGL is not enabled.");return false;}
    if(requested->version_major>3){snprintf(errorText,sizeof(errorText),"Unsupported OpenGL ES version");return false;}
    // ES 3 is backwards compatible with ES 2 and lets the core advertise a
    // matching GLSL version for fragment-depth shaders used by GTA.
    context=[[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if(!context && requested->context_type==RETRO_HW_CONTEXT_OPENGLES2)context=[[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if(!context){snprintf(errorText,sizeof(errorText),"Cannot create iOS graphics context");return false;}
    [EAGLContext setCurrentContext:context];
    glGenFramebuffers(1,&framebufferID);glBindFramebuffer(GL_FRAMEBUFFER,framebufferID);
    glGenTextures(1,&textureID);glBindTexture(GL_TEXTURE_2D,textureID);glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA,2048,2048,0,GL_RGBA,GL_UNSIGNED_BYTE,NULL);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,textureID,0);
    if(requested->depth || requested->stencil){glGenRenderbuffers(1,&depthID);glBindRenderbuffer(GL_RENDERBUFFER,depthID);glRenderbufferStorage(GL_RENDERBUFFER,GL_DEPTH24_STENCIL8,2048,2048);glFramebufferRenderbuffer(GL_FRAMEBUFFER,GL_DEPTH_ATTACHMENT,GL_RENDERBUFFER,depthID);if(requested->stencil)glFramebufferRenderbuffer(GL_FRAMEBUFFER,GL_STENCIL_ATTACHMENT,GL_RENDERBUFFER,depthID);}
    if(glCheckFramebufferStatus(GL_FRAMEBUFFER)!=GL_FRAMEBUFFER_COMPLETE){snprintf(errorText,sizeof(errorText),"Incomplete iOS framebuffer");hardware_stop();return false;}
    hw=*requested;requested->get_current_framebuffer=framebuffer;requested->get_proc_address=proc;return true;
}
// Match the presentation target to the core output. An always-2048-square
// target wastes full-surface clears and tile stores even at native PSP output.
int hardware_resize(unsigned width,unsigned height){
 if(!context)return 1;if(!width||!height||width>2048||height>2048)return 0;
 hardware_current();GLint f,t,r;glGetIntegerv(GL_FRAMEBUFFER_BINDING,&f);glGetIntegerv(GL_TEXTURE_BINDING_2D,&t);glGetIntegerv(GL_RENDERBUFFER_BINDING,&r);
 glBindFramebuffer(GL_FRAMEBUFFER,framebufferID);glBindTexture(GL_TEXTURE_2D,textureID);glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA,width,height,0,GL_RGBA,GL_UNSIGNED_BYTE,NULL);
 if(depthID){glBindRenderbuffer(GL_RENDERBUFFER,depthID);glRenderbufferStorage(GL_RENDERBUFFER,GL_DEPTH24_STENCIL8,width,height);}
 int ok=glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE;
 if(ok){presentationWidth=width;presentationHeight=height;}
 glBindTexture(GL_TEXTURE_2D,t);glBindRenderbuffer(GL_RENDERBUFFER,r);glBindFramebuffer(GL_FRAMEBUFFER,f);
 if(!ok)snprintf(errorText,sizeof(errorText),"Incomplete core-size framebuffer");return ok;
}
int hardware_start(void){readbackSeconds=conversionSeconds=0;if(context && !resetCalled){[EAGLContext setCurrentContext:context];if(hw.context_reset)hw.context_reset();resetCalled=true;}return errorText[0]==0;}
void hardware_current(void){if(context)[EAGLContext setCurrentContext:context];}
int hardware_read(uint32_t *pixels,unsigned width,unsigned height){
    if(!context || width>2048 || height>2048)return 0;
    hardware_current();GLint oldFramebuffer,oldAlignment;glGetIntegerv(GL_FRAMEBUFFER_BINDING,&oldFramebuffer);glGetIntegerv(GL_PACK_ALIGNMENT,&oldAlignment);glBindFramebuffer(GL_FRAMEBUFFER,framebufferID);glPixelStorei(GL_PACK_ALIGNMENT,1);
    GLint oldPack=0,oldRow=0;
    if(context.API==kEAGLRenderingAPIOpenGLES3){glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING,&oldPack);glGetIntegerv(GL_PACK_ROW_LENGTH,&oldRow);glBindBuffer(GL_PIXEL_PACK_BUFFER,0);glPixelStorei(GL_PACK_ROW_LENGTH,0);}
    // glReadPixels synchronizes its readback; a preceding glFinish stalls the entire GPU twice.
    static unsigned char rgba[2048*2048*4];double readStart=monotonic_seconds();glReadPixels(0,0,width,height,GL_RGBA,GL_UNSIGNED_BYTE,rgba);GLenum error=glGetError();readbackSeconds+=monotonic_seconds()-readStart;double convertStart=monotonic_seconds();
    for(unsigned y=0;y<height;y++)for(unsigned x=0;x<width;x++){unsigned source=((hw.bottom_left_origin ? height-1-y : y)*width+x)*4;pixels[y*width+x]=0xff000000|rgba[source]<<16|rgba[source+1]<<8|rgba[source+2];}
    conversionSeconds+=monotonic_seconds()-convertStart;
    if(context.API==kEAGLRenderingAPIOpenGLES3){glBindBuffer(GL_PIXEL_PACK_BUFFER,oldPack);glPixelStorei(GL_PACK_ROW_LENGTH,oldRow);}glPixelStorei(GL_PACK_ALIGNMENT,oldAlignment);glBindFramebuffer(GL_FRAMEBUFFER,oldFramebuffer);return error==GL_NO_ERROR;
}
void hardware_release_core(void){hardware_current();if(resetCalled && hw.context_destroy)hw.context_destroy();resetCalled=false;}
void hardware_stop(void){hardware_release_core();if(context){glDeleteFramebuffers(1,&framebufferID);glDeleteTextures(1,&textureID);glDeleteRenderbuffers(1,&depthID);[EAGLContext setCurrentContext:nil];context=nil;}framebufferID=textureID=depthID=0;memset(&hw,0,sizeof(hw));errorText[0]=0;}
const char *hardware_error(void){return errorText;}
const char *hardware_backend(void){return context ? "OpenGL ES / iOS" : "Software / iOS";}

double hardware_readback_seconds(void){return readbackSeconds;}
double hardware_conversion_seconds(void){return conversionSeconds;}

unsigned hardware_target_width(void){return context ? presentationWidth:0;}
unsigned hardware_target_height(void){return context ? presentationHeight:0;}
