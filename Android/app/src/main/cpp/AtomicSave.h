// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <cerrno>
#include <cstdlib>
#include <string>
#include <vector>
#include <unistd.h>
#include <cstdio>

namespace uncleed {
struct SaveFileIO {
 int create(char* path){return mkstemp(path);}
 ssize_t write(int fd,const void* bytes,size_t count){return ::write(fd,bytes,count);}
 int sync(int fd){return fsync(fd);}
 int close(int fd){return ::close(fd);}
 int replace(const char* from,const char* to){return rename(from,to);}
};

// One core owner calls this on its own thread. Only a complete, flushed,
// closed file may replace the previous save; every failed attempt is removed.
// Rename is atomic in the same directory. This is not a multi-file transaction.
template<class IO=SaveFileIO>
bool writeSaveAtomically(const std::string& path,const void* bytes,size_t count,IO io={}) {
 if(!bytes||!count)return false;
 std::string pattern=path+".tmp-XXXXXX";
 std::vector<char> temporary(pattern.begin(),pattern.end());temporary.push_back('\0');
 int fd=io.create(temporary.data());if(fd<0)return false;
 const auto* data=static_cast<const unsigned char*>(bytes);size_t written=0;bool ok=true;
 while(written<count){const ssize_t n=io.write(fd,data+written,count-written);
  if(n<0&&errno==EINTR)continue;
  if(n<=0||static_cast<size_t>(n)>count-written){ok=false;break;}
  written+=static_cast<size_t>(n);
 }
 if(ok&&io.sync(fd)!=0)ok=false;
 // Do not retry close on EINTR: on Android/Linux the descriptor may be closed.
 if(io.close(fd)!=0)ok=false;
 if(ok&&io.replace(temporary.data(),path.c_str())==0)return true;
 unlink(temporary.data());return false;
}
}
