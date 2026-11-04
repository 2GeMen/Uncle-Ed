// SPDX-License-Identifier: GPL-3.0-or-later
// Differential arithmetic and public ECDSA vectors; no ROM or private keys.
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
typedef unsigned char u8;
#include "kirk-test-curves.h"
typedef struct {void *h;void (*inv)(u8*,const u8*,const u8*,uint32_t);void (*to)(u8*,const u8*,uint32_t);void (*from)(u8*,const u8*,uint32_t);void (*mul)(u8*,const u8*,const u8*,const u8*,uint32_t);void (*reduce)(u8*,const u8*,uint32_t);int (*curve)(const u8*,const u8*,const u8*,const u8*,const u8*,const u8*);void(*pub)(u8*);int(*verify)(u8*,u8*,u8*);} API;
static API load(const char*p){API a={0};a.h=dlopen(p,RTLD_NOW|RTLD_LOCAL);if(!a.h){puts(dlerror());return a;}a.inv=dlsym(a.h,"bn_mon_inv_public");if(!a.inv)a.inv=dlsym(a.h,"bn_mon_inv");a.to=dlsym(a.h,"bn_to_mon");a.from=dlsym(a.h,"bn_from_mon");a.mul=dlsym(a.h,"bn_mon_mul");a.reduce=dlsym(a.h,"bn_reduce");a.curve=dlsym(a.h,"ecdsa_set_curve");a.pub=dlsym(a.h,"ecdsa_set_pub");a.verify=dlsym(a.h,"ecdsa_verify");return a;}
static uint32_t seed=0x12345678;static uint32_t random32(void){seed^=seed<<13;seed^=seed>>17;seed^=seed<<5;return seed;}
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec*1e-9;}
int main(int argc,char**argv){if(argc!=3)return 2;API r=load(argv[1]),o=load(argv[2]);if(!r.h||!o.h||!r.inv||!o.inv)return 3;const u8*moduli[]={ec_p,ec_N1,ec_N2};int cases=0;
for(int field=0;field<3;field++){int n=field?21:20;const u8*N=moduli[field];for(int k=0;k<2051;k++){u8 a[21]={0},m[21],x[21],y[21],product[21];if(k==1)a[n-1]=1;else if(k==2){memcpy(a,N,n);for(int i=n-1;i>=0;i--){if(a[i]--!=0)break;}}else if(k>2){for(int i=field?1:0;i<n;i++)a[i]=random32();r.reduce(a,N,n);}memcpy(m,a,n);r.to(m,N,n);r.inv(x,m,N,n);o.inv(y,m,N,n);if(memcmp(x,y,n)){printf("inverse mismatch field%d case%d\n",field,k);return 4;}if(k){r.mul(product,m,y,N,n);r.from(product,N,n);for(int i=0;i<n;i++)if(product[i]!=(i==n-1?1:0)){puts("inverse identity failed");return 5;}}cases++;}}
double times[2]={0,0};const u8*bs[]={ec_b1,ec_b2};const u8*ns[]={ec_N1,ec_N2};const u8*xs[]={Gx1,Gx2};const u8*ys[]={Gy1,Gy2};
for(int curve=0;curve<2;curve++){u8 pub[40],hash[20]={0},R[20],S[20],tmp[21]={0};hash[19]=1;memcpy(pub,xs[curve],20);memcpy(pub+20,ys[curve],20);memcpy(tmp+1,xs[curve],20);r.reduce(tmp,ns[curve],21);memcpy(R,tmp+1,20);for(int i=20;i>=0;i--){if(++tmp[i])break;}r.reduce(tmp,ns[curve],21);memcpy(S,tmp+1,20);
API *both[]={&r,&o};for(int a=0;a<2;a++){API*t=both[a];t->curve(ec_p,ec_a,bs[curve],ns[curve],xs[curve],ys[curve]);t->pub(pub);double begin=now();for(int j=0;j<4;j++){hash[19]=1;if(t->verify(hash,R,S)!=1){printf("valid signature rejected %d curve%d\n",a,curve);return 6;}hash[19]=2;if(t->verify(hash,R,S)!=0){puts("invalid signature accepted");return 7;}}times[a]+=now()-begin;}}
printf("PASS inverse_cases=%d signatures_valid=16 invalid=16 reference_ms=%.3f optimized_ms=%.3f ratio=%.3f\n",cases,times[0]*1000,times[1]*1000,times[0]/times[1]);return 0;}
