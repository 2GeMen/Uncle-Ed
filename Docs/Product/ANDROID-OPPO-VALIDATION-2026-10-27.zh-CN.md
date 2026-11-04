# OPPO Android 真机回归 · 2026-10-27

设备：PGEM10（用户提供 OPPO Find X6），Android 16。使用保留数据的 `adb install -r` 更新；未清空用户库或存档。
APK SHA-256：`e565ced5ccffe017426a7d360e46f369baf124817540782953a91004f77a0d18`。

## 展示交互

`work/android-oppo-showcase-probe.txt` 通过。已实际查看 `work/android-oppo-showcase-qa/home.png`、`rotated.png`、`returned.png`。

- GBA 原生黄色：首页/主题同为 2256×774 展示区，halfHeight 均 0.5736715；modelLoads 保持 1。
- 注入长按旋转达到 yaw 101.52° / pitch 23.22°，实际截图侧面可见、无裁边；旋转期间轮廓隐藏，背景光束保留。
- 松手后回正，未误确认；轮廓随实际机身恢复，没有白色占位或独立漂浮的金框。
- 本轮只覆盖该主题和该路径，不作为全角度、多主题或全页 iOS 体验验收。

## 核心与资料库回归

`work/android-oppo-core-regression.txt` 通过，使用现有原创 272 字节 GBA 输入测试程序。
240 帧、按 A 后画面由红转绿、产生 1,049,616 字节 PCM；SRAM 文件首字节正确，核心重新加载并可推进。另通过流式导入、内容哈希去重与 ZIP 路径穿越拒绝。
核心无节流运行约 98.47 ms；这不是实际游戏帧率。未验证扬声器听感、商业游戏持续运行、游戏内保存继续或 PSP。

## 展示性能短采样

启动展示后采样约 15 秒，未同时录屏/截图。原始 `gfxinfo.txt`、`meminfo.txt`、`crashes.txt` 在证据目录。
Android View/HWUI 共 917 帧，新口径 deadline miss 3 帧（0.33%）；P50 9 ms、P95 19 ms、P99 22 ms。legacy janky 273 帧（29.77%），不能只报更好看的新口径。系统还报告 high input latency 917；空闲采样没有主动触摸，不能据此推断真实触摸延迟。以上不是 Filament 独立帧呈现频率或游戏核心频率，持续性能仍需专门追踪。
总 PSS 303,765 KiB（约 297 MiB），单次采样不能证明没有泄漏。过滤日志无本轮 fatal crash 记录。

## 后续

真实邻居滚轮、其余主题重导、材质并排对照、快速分页、游戏持续性能与平板验证仍待完成。整页视觉验收维持 0。调试包保留在手机上，测试后已重新打开首页供用户查看。
