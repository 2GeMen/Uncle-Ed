// SPDX-License-Identifier: GPL-3.0-or-later
#include "../../Android/app/src/main/cpp/FrameReadback.h"
#include <EGL/egl.h>
#include <vector>
#include <cstdio>
#include <cstdlib>
static void check(bool b,const char* s){if(!b){std::fprintf(stderr,"FAIL: %s EGL=%x GL=%x\n",s,eglGetError(),glGetError());std::exit(1);}}
int main(){
 const auto display=eglGetDisplay(EGL_DEFAULT_DISPLAY);check(eglInitialize(display,nullptr,nullptr),"initialize");EGLConfig config;EGLint n;
 EGLint attrs[]={EGL_SURFACE_TYPE,EGL_PBUFFER_BIT,EGL_RENDERABLE_TYPE,EGL_OPENGL_ES3_BIT,EGL_RED_SIZE,8,EGL_GREEN_SIZE,8,EGL_BLUE_SIZE,8,EGL_ALPHA_SIZE,8,EGL_NONE};check(eglChooseConfig(display,attrs,&config,1,&n)&&n,"config");EGLint ca[]={EGL_CONTEXT_CLIENT_VERSION,3,EGL_NONE},sa[]={EGL_WIDTH,32,EGL_HEIGHT,32,EGL_NONE};const auto context=eglCreateContext(display,config,EGL_NO_CONTEXT,ca);const auto surface=eglCreatePbufferSurface(display,config,sa);check(eglMakeCurrent(display,surface,surface,context),"make current");
 GLuint texture,fbo,foreign;glGenTextures(1,&texture);glBindTexture(GL_TEXTURE_2D,texture);glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA,32,32,0,GL_RGBA,GL_UNSIGNED_BYTE,nullptr);glGenFramebuffers(1,&fbo);glBindFramebuffer(GL_FRAMEBUFFER,fbo);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,texture,0);check(glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE,"target");glGenBuffers(1,&foreign);glBindBuffer(GL_PIXEL_PACK_BUFFER,foreign);glBufferData(GL_PIXEL_PACK_BUFFER,4096,nullptr,GL_STREAM_READ);
 glPixelStorei(GL_PACK_ALIGNMENT,8);glPixelStorei(GL_PACK_ROW_LENGTH,48);glPixelStorei(GL_PACK_SKIP_ROWS,2);glPixelStorei(GL_PACK_SKIP_PIXELS,3);
 FrameReadback reader;std::vector<uint8_t> pixels(32*32*4+32,0xcd);
 auto paint=[&](int blue){glEnable(GL_SCISSOR_TEST);glScissor(0,0,32,16);glClearColor(1,0,blue/255.f,.2f);glClear(GL_COLOR_BUFFER_BIT);glScissor(0,16,32,16);glClearColor(0,1,blue/255.f,.2f);glClear(GL_COLOR_BUFFER_BIT);glDisable(GL_SCISSOR_TEST);};
 auto state=[&](){GLint b,a,r,s,p,f;glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING,&b);glGetIntegerv(GL_PACK_ALIGNMENT,&a);glGetIntegerv(GL_PACK_ROW_LENGTH,&r);glGetIntegerv(GL_PACK_SKIP_ROWS,&s);glGetIntegerv(GL_PACK_SKIP_PIXELS,&p);glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&f);check(b==static_cast<GLint>(foreign)&&a==8&&r==48&&s==2&&p==3&&f==static_cast<GLint>(fbo),"core GL state preserved");};
 paint(0);check(!reader.read(fbo,32,32,true,pixels.data()),"first callback queued");state();
 for(int frame=1;frame<=64;frame++){paint(frame);check(reader.read(fbo,32,32,true,pixels.data()),"previous callback ready");state();for(int y=0;y<32;y++)for(int x=0;x<32;x++){const int i=(y*32+x)*4;check(pixels[i]==(y<16?0:255)&&pixels[i+1]==(y<16?255:0)&&pixels[i+2]==frame-1&&pixels[i+3]==255,"ordered RGBA, vertical origin and opaque LCD");}for(size_t i=32*32*4;i<pixels.size();i++)check(pixels[i]==0xcd,"output guard");}
 // Resize invalidates previous-size pixels; next callback is from the new size.
 glBindBuffer(GL_PIXEL_PACK_BUFFER,0);glBindTexture(GL_TEXTURE_2D,texture);glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA,16,16,0,GL_RGBA,GL_UNSIGNED_BYTE,nullptr);glClearColor(0,0,1,1);glClear(GL_COLOR_BUFFER_BIT);glBindBuffer(GL_PIXEL_PACK_BUFFER,foreign);check(!reader.read(fbo,16,16,false,pixels.data()),"resize invalidates pending frame");check(reader.read(fbo,16,16,false,pixels.data()),"resized frame ready");for(int i=0;i<16*16;i++)check(pixels[i*4]==0&&pixels[i*4+1]==0&&pixels[i*4+2]==255&&pixels[i*4+3]==255,"resized color");
 reader.reset();state();check(glGetError()==GL_NO_ERROR,"no GL errors");glDeleteBuffers(1,&foreign);glDeleteFramebuffers(1,&fbo);glDeleteTextures(1,&texture);eglMakeCurrent(display,EGL_NO_SURFACE,EGL_NO_SURFACE,EGL_NO_CONTEXT);eglDestroySurface(display,surface);eglDestroyContext(display,context);eglTerminate(display);std::puts("PASS: 64 ordered RGBA frames, flip/alpha/guards, pack and framebuffer state, resize and reset on actual GLES3");
}
