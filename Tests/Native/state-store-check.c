// SPDX-License-Identifier: GPL-3.0-or-later
#include "../../Android/app/src/main/cpp/StateStore.h"
#include <assert.h>
static unsigned value=1;static int reject=0,loads=0;
static size_t size(void){return 4;}
static bool save(void* data,size_t n){if(n!=4)return false;memcpy(data,&value,4);return true;}
static bool load(const void* data,size_t n){loads++;if(n!=4)return false;memcpy(&value,data,4);if(reject){reject--;value=999;return false;}return true;}
int main(void){char dir[]="/tmp/uestate-XXXXXX";assert(mkdtemp(dir));char p[1024],err[1024];snprintf(p,sizeof(p),"%s/test.uestate",dir);UEStateCore c={size,save,load};
 assert(ue_core_hash(p)==0);assert(ue_identity(p,p)==0);
 assert(ue_state_save(c,p,123,err,sizeof(err))==1);value=42;assert(ue_state_load(c,p,123,err,sizeof(err))==1&&value==1);
 value=42;int before=loads;assert(ue_state_load(c,p,456,err,sizeof(err))==0&&value==42&&loads==before);
 reject=1;assert(ue_state_load(c,p,123,err,sizeof(err))==0&&value==42);reject=2;assert(ue_state_load(c,p,123,err,sizeof(err)) == -2);
 value=50;FILE* f=fopen(p,"r+b");assert(f);fseek(f,40,SEEK_SET);fputc(55,f);fclose(f);before=loads;assert(ue_state_load(c,p,123,err,sizeof(err))==0&&value==50&&loads==before);
 assert(ue_state_save(c,p,123,err,sizeof(err))==1);assert(truncate(p,42)==0);assert(ue_state_load(c,p,123,err,sizeof(err))==0&&value==50);
 UEStateCore unsupported={0};assert(!ue_state_save(unsupported,p,123,err,sizeof(err)));assert(!ue_state_load(unsupported,p,123,err,sizeof(err)));
 unlink(p);rmdir(dir);puts("PASS: state roundtrip, identity/checksum/truncation rejection before core mutation, rollback, fatal rollback and unsupported core");
}
