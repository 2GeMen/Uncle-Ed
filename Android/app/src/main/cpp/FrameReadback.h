// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <GLES3/gl3.h>
#include <cstdint>
#include <cstring>

// Context-owned, ordered double buffering. Every submitted frame is consumed on
// the following callback; no polling/discarding and no change to pixel precision.
// Mapping may wait for the previous transfer, rather than the current render.
class FrameReadback {
 GLuint buffers_[2]{};unsigned width_=0,height_=0;int next_=0;bool pending_[2]{};bool disabled_=false;
 void clearBuffers(){glDeleteBuffers(2,buffers_);buffers_[0]=buffers_[1]=0;pending_[0]=pending_[1]=false;width_=height_=0;next_=0;}
 static void copyRows(uint8_t* out,const uint8_t* in,unsigned w,unsigned h,bool flip){for(unsigned y=0;y<h;y++)std::memcpy(out+y*w*4,in+(flip?h-1-y:y)*w*4,w*4);}
 public:
 void reset(){clearBuffers();disabled_=false;}
 bool read(GLuint fbo,unsigned w,unsigned h,bool flip,uint8_t* out){
  GLint oldFbo,oldBuffer,alignment,rowLength,skipRows,skipPixels;
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&oldFbo);glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING,&oldBuffer);glGetIntegerv(GL_PACK_ALIGNMENT,&alignment);glGetIntegerv(GL_PACK_ROW_LENGTH,&rowLength);glGetIntegerv(GL_PACK_SKIP_ROWS,&skipRows);glGetIntegerv(GL_PACK_SKIP_PIXELS,&skipPixels);
  glBindFramebuffer(GL_READ_FRAMEBUFFER,fbo);glPixelStorei(GL_PACK_ALIGNMENT,1);glPixelStorei(GL_PACK_ROW_LENGTH,0);glPixelStorei(GL_PACK_SKIP_ROWS,0);glPixelStorei(GL_PACK_SKIP_PIXELS,0);
  const GLsizeiptr bytes=static_cast<GLsizeiptr>(w)*h*4;bool ready=false;
  if(!disabled_){
   if(w!=width_||h!=height_){clearBuffers();width_=w;height_=h;glGenBuffers(2,buffers_);for(auto b:buffers_){glBindBuffer(GL_PIXEL_PACK_BUFFER,b);glBufferData(GL_PIXEL_PACK_BUFFER,bytes,nullptr,GL_STREAM_READ);GLint allocated=0;glGetBufferParameteriv(GL_PIXEL_PACK_BUFFER,GL_BUFFER_SIZE,&allocated);if(allocated!=bytes)disabled_=true;}}
   if(!disabled_){
    const int previous=1-next_;glBindBuffer(GL_PIXEL_PACK_BUFFER,buffers_[next_]);glReadPixels(0,0,w,h,GL_RGBA,GL_UNSIGNED_BYTE,nullptr);pending_[next_]=true;
    if(pending_[previous]){glBindBuffer(GL_PIXEL_PACK_BUFFER,buffers_[previous]);const auto* mapped=static_cast<const uint8_t*>(glMapBufferRange(GL_PIXEL_PACK_BUFFER,0,bytes,GL_MAP_READ_BIT));
     if(mapped){copyRows(out,mapped,w,h,flip);ready=glUnmapBuffer(GL_PIXEL_PACK_BUFFER)==GL_TRUE;}if(!ready)disabled_=true;pending_[previous]=false;
    }
    next_=previous;
   }
  }
  if(disabled_){clearBuffers();glBindBuffer(GL_PIXEL_PACK_BUFFER,0);glReadPixels(0,0,w,h,GL_RGBA,GL_UNSIGNED_BYTE,out);if(flip){for(unsigned y=0;y<h/2;y++)for(unsigned x=0;x<w*4;x++){const auto at=y*w*4+x,other=(h-1-y)*w*4+x;const auto b=out[at];out[at]=out[other];out[other]=b;}}ready=true;}
  glBindFramebuffer(GL_READ_FRAMEBUFFER,oldFbo);glBindBuffer(GL_PIXEL_PACK_BUFFER,oldBuffer);glPixelStorei(GL_PACK_ALIGNMENT,alignment);glPixelStorei(GL_PACK_ROW_LENGTH,rowLength);glPixelStorei(GL_PACK_SKIP_ROWS,skipRows);glPixelStorei(GL_PACK_SKIP_PIXELS,skipPixels);
  if(ready)for(size_t i=3;i<static_cast<size_t>(w)*h*4;i+=4)out[i]=255;
  return ready;
 }
};
