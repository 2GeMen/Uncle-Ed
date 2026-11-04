// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef UNCLEED_STATE_STORE_H
#define UNCLEED_STATE_STORE_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <sys/stat.h>
#define UE_STATE_LIMIT (512u*1024u*1024u)
typedef struct {size_t (*size)(void);bool (*save)(void*,size_t);bool (*load)(const void*,size_t);} UEStateCore;
static uint64_t ue_hash(const void* p,size_t n){const unsigned char* b=(const unsigned char*)p;uint64_t h=UINT64_C(14695981039346656037);while(n--)h=(h^*b++)*UINT64_C(1099511628211);return h;}
static uint64_t ue_core_hash(const char* path){FILE* f=fopen(path,"rb");if(!f)return 0;unsigned char b[65536];size_t n;uint64_t h=UINT64_C(14695981039346656037);while((n=fread(b,1,sizeof(b),f)))for(size_t i=0;i<n;i++)h=(h^b[i])*UINT64_C(1099511628211);int ok=!ferror(f);fclose(f);return ok?h:0;}
static uint64_t ue_identity(const char* rom,const char* core){struct stat st;if(stat(rom,&st))return 0;const char* name=strrchr(rom,'/');name=name?name+1:rom;char value[2048];snprintf(value,sizeof(value),"%s|%llu|%llu|%llu|%zu",name,(unsigned long long)st.st_size,(unsigned long long)st.st_mtime,(unsigned long long)ue_core_hash(core),sizeof(void*));return ue_hash(value,strlen(value));}
static void ue_put(unsigned char* p,uint64_t n){for(int i=0;i<8;i++){p[i]=(unsigned char)n;n>>=8;}}
static uint64_t ue_get(const unsigned char* p){uint64_t n=0;for(int i=7;i>=0;i--)n=(n<<8)|p[i];return n;}
static int ue_fail(char* error,size_t capacity,const char* message){snprintf(error,capacity,"%s",message);return 0;}
static int ue_state_save(UEStateCore c,const char* path,uint64_t identity,char* error,size_t capacity){
 if(!c.size||!c.save||!c.load)return ue_fail(error,capacity,"当前核心不支持即时存档");
 size_t n=c.size();if(!n||n>UE_STATE_LIMIT)return ue_fail(error,capacity,"核心尚未准备好，或即时存档超过容量上限，请稍后重试");
 void* bytes=calloc(1,n);if(!bytes)return ue_fail(error,capacity,"内存不足，未覆盖旧存档");
 if(!c.save(bytes,n)){free(bytes);return ue_fail(error,capacity,"核心保存运行状态失败，未覆盖旧存档");}
 unsigned char h[40]={0};memcpy(h,"UESTv001",8);ue_put(h+8,n);ue_put(h+16,ue_hash(bytes,n));ue_put(h+24,identity);ue_put(h+32,(uint64_t)time(NULL));
 char temp[4608];if(snprintf(temp,sizeof(temp),"%s.tmp-XXXXXX",path)>=(int)sizeof(temp)){free(bytes);return ue_fail(error,capacity,"存档路径过长");}
 int fd=mkstemp(temp);FILE* f=fd<0?NULL:fdopen(fd,"wb");int ok=0;
 if(f){ok=fwrite(h,1,40,f)==40&&fwrite(bytes,1,n,f)==n&&fflush(f)==0&&fsync(fileno(f))==0;if(fclose(f))ok=0;}else if(fd>=0)close(fd);
 free(bytes);if(ok&&rename(temp,path)==0){error[0]=0;return 1;}unlink(temp);return ue_fail(error,capacity,"即时存档未写入，请检查可用空间；旧存档已保留");
}
// Validate before changing the core; keep a rollback state in memory. -2 means
// rollback also failed, and the host must stop this session rather than resume it.
static int ue_state_load(UEStateCore c,const char* path,uint64_t identity,char* error,size_t capacity){
 if(!c.size||!c.save||!c.load)return ue_fail(error,capacity,"当前核心不支持即时存档");
 FILE* f=fopen(path,"rb");if(!f)return ue_fail(error,capacity,"还没有这个即时存档");unsigned char h[40];
 if(fread(h,1,40,f)!=40||memcmp(h,"UESTv001",8)||ue_get(h+24)!=identity){fclose(f);return ue_fail(error,capacity,"存档不属于当前游戏/核心版本，或文件已损坏");}
 uint64_t length=ue_get(h+8);struct stat st;if(!length||length>UE_STATE_LIMIT||fstat(fileno(f),&st)||st.st_size!=(off_t)(40+length)){fclose(f);return ue_fail(error,capacity,"即时存档不完整或容量异常");}
 void* bytes=malloc((size_t)length);if(!bytes){fclose(f);return ue_fail(error,capacity,"内存不足，尚未改变当前游戏");}
 int valid=fread(bytes,1,(size_t)length,f)==length&&ue_hash(bytes,(size_t)length)==ue_get(h+16);fclose(f);if(!valid){free(bytes);return ue_fail(error,capacity,"即时存档校验失败，尚未改变当前游戏");}
 size_t n=c.size();if(!n||n>UE_STATE_LIMIT){free(bytes);return ue_fail(error,capacity,"核心尚未准备好，请稍后再恢复");}void* undo=calloc(1,n);
 if(!undo||!c.save(undo,n)){free(undo);free(bytes);return ue_fail(error,capacity,"无法保护当前进度，取消恢复");}
 int ok=c.load(bytes,(size_t)length);free(bytes);if(ok){free(undo);error[0]=0;return 1;}
 int reverted=c.load(undo,n);free(undo);ue_fail(error,capacity,reverted?"恢复失败，已回到恢复前的进度":"恢复及回滚失败，请重新启动游戏");return reverted?0:-2;
}
#endif
