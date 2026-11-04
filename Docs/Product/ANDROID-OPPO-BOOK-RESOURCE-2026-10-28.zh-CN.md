# Android 真机回归、加载恢复与 NDS 书本握法

日期：2026-10-28。用户恢复 OPPO 真机调试，沿原已配对无线服务 Android-2.local:37383 接通；无需重新配对。所有安装保留库与存档，没有公开发布。

## 真机发现与修复

首轮多指和文字区测试均失败：连续换机后主模型的异步资源未就绪，卡贴与相邻模型不再出现。手机亮屏、未锁定，不能归咎于系统锁屏；也不能把此前模拟器重跑通过当作该故障已解决。

修复应用对 Filament ResourceLoader 的生命周期管理：取消资源任务后销毁并重建解码队列，避免取消状态影响下一轮；检查 primary / neighbour 的 asyncBeginLoad 返回值，并记录 resourceLoad 进度、当前所有者及 epoch。没有降低模型、贴图分辨率或修改第三方库。

实现依据：本地 Filament 头文件以及 [Filament 1.66.0 ResourceLoader 官方实现](https://github.com/google/filament/blob/v1.66.0/libs/gltfio/src/ResourceLoader.cpp)。这是本应用生命周期修复及实测结果，不宣称已证实为上游库缺陷。

修复后 OPPO 三机型连续路径通过：

- GBA/GBC/PSP 非连续 pointer ID、多指同时按键、松开一指保留另一指、取消及焦点丢失全部释放。
- GBA/PSP 实体肩键组合；PSP 捕获摇杆滑出获取圈继续维持方向，同时按 A、松开摇杆而保留 A。
- 实际库三机型卡片文字区：点击邻居只选中、长按旋转回正、滑动前一张，未启动游戏核心。

证据：`work/android-oppo-input-boundaries-resource-fixed.txt`、`work/android-oppo-caption-shelf-resource-fixed.txt`、`work/android-oppo-input-fixed-qa`、`work/android-oppo-caption-fixed-qa`。实际截图已读取核对。前两份失败日志保留为 `android-oppo-input-boundaries-final.txt` 和 `android-oppo-caption-shelf-final.txt`，不计通过。输入测试走 View 处理和实体投影，不等于用户手指操作舒适度、全部主题或整页 iOS 一致性已验收。

## NDS 书本握法

菜单仅 NDS 提供「切换书本握法 / 恢复双屏握法」。用 450ms 连续旋转把上下双屏变为左右双屏，机身、实体按键、屏幕一起旋转，重新计算投影范围和显示位置余量。3DS 不提供入口。

转换时释放输入，并等待实际呈现帧到达终点后恢复触控；不能只依据 CPU 动画数值。下屏通过逆变换映射，十字键按实体方向映射，避免屏幕坐标方向随旋转混乱。换机重置书本姿态。

独立软件平板模拟器、原创 NDS 程序通过：真实装载/启动、90° 实际呈现终点截图、下屏中心与两个边角、实体右方向按下/释放、切回原姿态。五机型输入/受限窗口回归同时确认只在 NDS 菜单出现书本入口。

证据 `work/android-nds-book-corners-final.txt`、`work/android-nds-book-presented-qa/book.png`、`work/android-nds-book-corners.json`、`work/android-tablet-input-book-final.txt`、`work/android-tablet-resource-book-final-qa`。首次只等动画数值的截图仍是中间角度，已加强呈现判据并重新截图，不用该初始截图作终点证明。软件模拟器仍为 1280×800/160dpi QA 模式；不是 Android 平板真机或商业游戏书本触控验收。

## 战神采样

OPPO Ghost of Sparta 启动/菜单 120.223 秒，未发送游戏按键、未开始新游戏：核心均值 59.964fps，最低五秒 59.844fps，实际呈现约 60.399fps。音频累计欠载 4 次，首个五秒样本时已为 4，后续 23 个窗口未增加；末次 run p95 16.583ms。不能称战斗性能或启动音频已解决。

证据 `work/android-war-resource-final-120s.txt`、`work/android-war-resource-final-qa/summary.json`。新增有界（最多12条）音频欠载事件诊断：帧号、播放后时间、次数、缓冲余量和本帧运行时间，不更改音频延迟、播放速度或画质；最终短采样见 `work/android-war-audio-events-final.txt`，详细事件另保存本地。首轮事件诊断捕获 frame35：播放后628ms、run244633µs；frame39：690ms、31005µs；frame1119：18728ms、83557µs，累计欠载3。这一短样本在约18.7秒也有尖峰，不能由前述两分钟样本推断后续永远无欠载。另加 nativeRun / videoCallback 分段耗时，以区分核心和视频读回；最终结果见 `work/android-war-native-timing-final.txt`。

最终 native 分段样本（`work/android-war-native-timing-qa`）：frame34 的247618µs native执行中，视频回调5484µs；累计欠载1。说明该尖峰主要不在前端像素读回，但尚不能区分核心内部的编译、加载或模拟调度。

发现原性能探针没有正常关闭核心即结束 instrumentation，因此补为返回首页并等待 coreWorkerAlive=false，再保存 shutdown.json。两次30秒样本正常退出均通过；实际缓存目录仍为空，重复样本仍有3次欠载（frame34/38/1118，约245ms/33ms/79ms），没有证实“缓存正常写入后即可解决”。不得把这组测试流程修正称为性能修复。证据 `work/android-war-graceful-{first,repeat}.txt`、对应两个 `-qa` 目录及 `work/android-war-graceful-cache.txt`。

## 交付边界与后续

24项JVM单测通过；代码隔离、调试签名及ROM/存档不随包检查在收尾记录。最新开发包已保留数据更新到 OPPO。Mac/iOS 原工程未修改。

仍待：启动音频欠载根因与优化、GTA城市场景/战神战斗长期负载、商业游戏内存档/继续、多指主观手感、Android系统分屏/平板真机、全主题逐页iOS同尺寸视觉验收。整页验收数仍为0；3DS后端未开放。公开素材、许可证收尾和正式发行包保持未就绪。
