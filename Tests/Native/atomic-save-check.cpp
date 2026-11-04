// SPDX-License-Identifier: GPL-3.0-or-later
#include "../../Android/app/src/main/cpp/AtomicSave.h"
#include <algorithm>
#include <cassert>
#include <dirent.h>
#include <fstream>
#include <iostream>
#include <iterator>

struct FaultIO:uncleed::SaveFileIO {
 enum Mode{Normal,Short,Interrupted,Full,SyncFailure,CloseFailure,RenameFailure,Zero};
 Mode mode;int calls=0;
 explicit FaultIO(Mode m):mode(m){}
 ssize_t write(int fd,const void* data,size_t count){
  ++calls;
  if(mode==Interrupted&&calls==1){errno=EINTR;return -1;}
  if(mode==Full&&calls>1){errno=ENOSPC;return -1;}
  if(mode==Zero)return 0;
  return SaveFileIO::write(fd,data,(mode==Short||mode==Full)?std::min(count,size_t(3)):count);
 }
 int sync(int fd){if(mode==SyncFailure){errno=EIO;return -1;}return SaveFileIO::sync(fd);}
 int close(int fd){int result=SaveFileIO::close(fd);return mode==CloseFailure?-1:result;}
 int replace(const char* a,const char* b){if(mode==RenameFailure){errno=EIO;return -1;}return SaveFileIO::replace(a,b);}
};
std::string read(const std::string& p){std::ifstream f(p,std::ios::binary);return {std::istreambuf_iterator<char>(f),{}};}
void noTemps(const std::string& root){DIR* d=opendir(root.c_str());assert(d);while(auto* e=readdir(d))assert(std::string(e->d_name).find(".tmp-")==std::string::npos);closedir(d);}
int main(){char folder[]="/tmp/uncleed-save-XXXXXX";const char* created=mkdtemp(folder);assert(created);std::string root=created,path=root+"/game.srm",old="original-save",data(8192,'x');int cases=0;
 for(auto mode:{FaultIO::Normal,FaultIO::Short,FaultIO::Interrupted,FaultIO::Full,FaultIO::SyncFailure,FaultIO::CloseFailure,FaultIO::RenameFailure,FaultIO::Zero}){
  {std::ofstream f(path,std::ios::binary);f<<old;}
  const bool expected=mode==FaultIO::Normal||mode==FaultIO::Short||mode==FaultIO::Interrupted;
  assert(uncleed::writeSaveAtomically(path,data.data(),data.size(),FaultIO(mode))==expected);
  assert(read(path)==(expected?data:old));noTemps(root);cases++;
 }
 assert(!uncleed::writeSaveAtomically(root+"/missing/game.srm",data.data(),data.size()));cases++;
 assert(!uncleed::writeSaveAtomically(path,nullptr,data.size()));assert(read(path)==old);cases++;
 assert(!uncleed::writeSaveAtomically(path,data.data(),0));assert(read(path)==old);cases++;
 unlink(path.c_str());assert(uncleed::writeSaveAtomically(path,data.data(),data.size()));assert(read(path)==data);cases++;
 noTemps(root);unlink(path.c_str());rmdir(root.c_str());std::cout<<"PASS: "<<cases<<" atomic save cases; prior bytes preserved on failed writes/flush/close/rename; no temporary leftovers\n";
}
