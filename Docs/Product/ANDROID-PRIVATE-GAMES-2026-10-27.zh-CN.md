# 原项目 ROM 同步与 OPPO 游戏回归 · 2026-10-27

用户要求把原项目 ROM 导入 Android，并用实际游戏验收一致性。来源为本机原项目私用库；ROM、哈希清单、商业游戏截图均仅留本地工作目录和手机应用数据，不进入源码或 APK。原项目存档未复制，手机现有存档未清空。

## 同步结果

25 个源文件共 7,190,887,298 字节；NDS 黑版 ZIP 与已有 NDS 内容相同，内容去重后为 24 款：GBA 6、GBC 7、NDS 7、PSP 2、3DS 2。Android 另外保留原有原创测试程序，共 25 条库记录。

所有 24 款正式库文件已在手机重新计算 SHA-256，与原项目原文件或 ZIP 实际游戏条目逐一相符。导入时新增 `originalName` 字段，保留地区/修订版信息；旧库缺少字段可正常读取，不改写既有游戏身份。

首次无 Activity 的长导入 instrumentation 被 ColorOS 以 Cached(nirvana) 清理，不是已证实的应用异常崩溃。修正测试为前台实际 Activity 后完整导入；未完成缓存支持重试，残留的一个 import 临时文件已定点清理。此结果不证明产品长时间后台导入已具备恢复能力。

## 真实游戏

- 13 款商业 GBA/GBC 各推进 600 帧，均产生非单色画面与 PCM；另保留原创测试程序回归。无节流的短核心测试只证明启动，不能替代真实速度/完整兼容。
- 宝可梦火红：通过真实页面进入主题、收藏、游玩，使用模型 Start/A 触点推进至操作说明；6,001 ms 推进 359 帧，约 59.82 核心 fps。
- 宝可梦银：手机转为竖屏，启动 GAME FREAK 片头，模型 Start/A 可推进初始交互。修复后 6,003 ms 推进 359 帧，约 59.80 核心 fps。
- 以上两个场景截图均实际查看；没有实测扬声器听感、长期冒险/战斗、双指肩键、游戏内保存/继续或独立游戏帧率。不标记完整 gameplayAccepted。
- PSP/NDS/3DS ROM 已保存在私用库；其 Android 核心未就绪，不能因为已导入就标记可游玩。手机仍只显示 GBA/GBC/PSP，其他库保留供后续平板/核心迁移。

## 本轮修复和仍有的视觉差距

宝可梦银首次真机截图暴露 GBC 旧 GLB 的贴字、纹样和屏幕 UV 上下颠倒。使用已修正的共享导出器重导 GBC theme 0 及媒体基础模型，重新构建安装并完成截图复核。其余 GBC 主题未因此自动通过；当前最新重导只有 GBA theme 0 与 GBC theme 0。

首页仍缺真实相邻机型滚轮；媒体页仍为无封面基础卡壳，缺封面资料绑定和邻居；插卡/UMD机械仪式未迁移；其他主题/材质与 iOS 对照仍未通过。用户反馈的一致性差距成立，不能把核心运行顺畅当作移植完成。

## 证据（本地 work）

- `android-private-sync-manifest.json`、`android-private-device-hashes.txt`、`android-private-library.json`。
- `android-private-import-probe-retry.txt`、`android-private-game-audit.json`。
- `android-private-gba-journey.txt`、`android-private-gameplay-qa/gba/`。
- `android-private-gbc-fixed-journey.txt`、`android-private-gameplay-qa/gbc-fixed/`；旧 `gbc/` 为修复前，不能作完成证据。
- `android-private-game-build.log`：构建和7项单元测试通过；`android-gbc-game-fix-build.log`：更新资源后的构建通过。

最终私用 debug APK SHA-256：`587f99a2e9fc5d7bbbb1a9d037308b37a52509271399265e05a476bc3af6a131`。已安装于 OPPO PGEM10 Android16，仍非 release。
