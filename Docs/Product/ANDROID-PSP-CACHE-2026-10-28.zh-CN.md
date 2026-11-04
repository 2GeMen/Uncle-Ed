# Android PSP 缓存写入与回归 · 2026-10-28

## 已确认原因与修复

上一轮已测到战神启动 frame34 约245ms、frame1118约80ms，长帧主体在模拟核心执行路径。继续检查发现：PPSSPP 能生成着色器缓存，退出时配置启用、路径有效、draw 有效、已有21个程序；但追加校验码时的 `File::OpenCFile(filename, "ab")` 被 libretro VFS 分支拒绝，继而触发 `Failed to write the shader cache` 并删除文件。

证据 `work/android-cache-state-log.txt`、`work/android-cache-diagnostic-state.txt`，以及 OPPO 的 UncleEdCore 日志。文件目录权限正常，不能归咎于 Android 存储权限。

最终修复只有 libretro 文件适配层的两处条件：将 `ab` 加入写入模式，并按已有追加方式打开文件、定位末尾。普通读写路径、Android Content URI 路径、图形算法、核心速度与画质参数不变；不改存档格式。回归风险限于新启用的二进制追加路径，需要核对既有内容未被截断以及缓存校验/重载。

最初探索的 GPU DeviceLost 保存改动和临时 WARN 诊断均已移除，未作为最终修复保留。可复现补丁 `Android/patches/ppsspp-libretro-binary-append.patch`，仍基于 PPSSPP `9bece86f087c4f3a2fb1af58dd90d89282013616`，保留之前的 context-destroy guard。来源和补丁哈希由构建脚本输出到本地 provenance；不是新版本下载或不明二进制替换。

## 实测范围

修复前实际缓存目录为空。修复后 OPPO 正常退出生成 `NPHG00092.glshadercache`，548字节；重启后文件保留。第一次30秒启动/菜单采样欠载3，缓存重载后的30秒样本欠载2；frame1118的欠载没有在该次重复样本出现，但 frame34约244ms尖峰仍在。因此只确认缓存写入修复，不能由单次减少推断持续性能已经达标。

证据 `work/android-cache-append-first-qa/summary.json`、`work/android-cache-append-repeat-qa/summary.json`、`work/android-cache-append-files.txt`。最终最小补丁另做120秒重载回归，见 `work/android-append-final-war-120s.txt` 和同名 `-qa` 目录。最终120.215秒：核心均值59.959fps，最低五秒59.764fps，累计欠载3，均在播放后623–686ms出现，之后没有增加；frame34仍242735µs，视频回调1017µs。因此没有宣称启动音频已解决。独立XXH3校验检查确认548字节缓存末尾校验有效，证据 `work/android-psp-cache-checksum.txt`；未截断缓存主体。全程 skipKeys，不开始新游戏或覆盖游戏进度。

## 构建与上游测试

- C++ 上游单元测试90项通过，证据 `work/ppsspp-append-unit-final.txt`。
- pspautotests 以 `-g --graphics=software` 运行：479项主测试与1项独立参数测试通过，共480，失败/缺失0；证据 `work/ppsspp-append-hle-final.txt`。这不是 Android GLES 画质或商业游戏长期验收。
- 首次测试环境未启用FFmpeg，出现11项音视频失败；补齐编解码器后上述最终测试通过。首次VFS单测失败来自运行目录缺少固定zip资源，改在源码目录运行后90项通过。保留初始日志，不将初始失败计为通过。
- 应用私用核心源目录此前直接混入编译目录，触发非ABI路径打包失败。现用 Sync 只复制 arm64-v8a / x86_64 顶层动态库，调试源集保留条件隔离，避免编译产物或 provenance 文件进入 JNI 库目录。
- 核心构建脚本统一解析绝对SDK路径，严格核对两份补丁和允许修改的源码文件；Shared/android-core-lock.json同步补丁列表。

## 仍未完成

战神启动尖峰仍需继续在 PPSSPP 内部定位；该补丁不宣称解决JIT、解码、驱动编译等尚未证实的原因。还需战斗/城市场景、商业游戏内存档/重载、Android系统分屏/平板真机、逐页iOS同尺寸视觉验收。3DS后端和公开发行素材仍未就绪，整体移植不能标记完成。

按上游维护约定已保留本地修复提交（`work/ppsspp-append-local-commit.txt`），没有推送。构建工作树恢复为锁定上游基线加两份补丁，保证现有复现脚本仍可直接核对。

最终打包/安装核对：APK内核心与新构建strip后逐字节一致，没有临时缓存WARN诊断；无ROM/存档或非ABI库路径，签名通过；24项应用单测、5项源码隔离测试通过。手机库仍24款，已回普通首页。证据 `work/android-append-final-build-audit.json`，正式release仍未就绪。
