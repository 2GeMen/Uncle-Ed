# Android 游戏封面与资料迁移

2026-10-28。OPPO PGEM10 / Android 16，无线调试。属于阶段 3 的增量，整页体验验收仍为 0。

## 已实现

- 启动、ROM 导入结束及进入选卡页后，在后台匹配封面和资料。封面两条工作线程、资料单独串行；解码和贴纸处理不在 UI 线程运行。
- 保留原文件名，用名称、机型、地区和版本标记匹配；重音、标点、别名归一化，拒绝歧义地区和试玩/正式版混配。随机改名的文件尚无 ROM 头/数据库兜底。
- Libretro thumbnails / GitHub 索引提供封面，Wikidata 提供实体资料，Metacritic 仅取同名同平台媒体分。缺失字段为“/”；首次发行与本平台日期分别标注。
- 网络请求受已保存的授权约束。用户本轮明确允许向上述服务发送游戏名称、机型、地区。匹配器不读取或上传 ROM、存档、账户信息；限制 HTTPS 主机、响应体大小、超时和重定向。首次安装的产品级授权入口仍待公开版设计，当前 OPPO 的授权由真机验证工具保存。
- 文件原子落盘，失败退避，已完成资料保留七日刷新间隔；本地缓存可离线显示。快速换卡采用游戏 ID 和 generation 防止迟到的封面覆盖当前选择。
- 五种媒体模型重导：印刷封面采用消光不透明材质；外壳、金属仍用原 PBR。GBA 盒图回退在去左侧平台书脊后铺满贴纸，最多裁去底部 12%，保留顶部游戏标题；未取得单独原装卡贴时不声称是原卡贴。
- 贴纸 sRGB 上传，显式 RGBA 通道；卡壳按原 Mac 的色族量化算法选主色，转换到线性材质输入，不改写用户原色缓存。PSP UMD 不使用卡壳主色替换。
- 媒体预览与机身比例分开：手机最大 160dp 高、290dp 宽，平板 280dp / 360dp，同时受视口约束，保持长宽比。资料区收紧，标题和资料允许换行。平板最终视觉未验收。

## 私用游戏库

24 款实际游戏（6 GBA、7 GBC、7 NDS、2 PSP、2 3DS）的封面均已缓存。库中另外保留 1 条既有原创测试程序，无商业封面，不能计为缺失的一款实际游戏。

19 张封面来自原应用按 ROM SHA-256 命名的现代缓存，余下通过后台匹配补齐。旧的按代码命名 manifest 存在版本错配，未使用。原始 metadata / index 种子仅放在外置私用 assets；封面图片、ROM、存档均未写入公开源码或 APK。更新安装保留数据，未复制或改动用户存档。

## 已取得的证据

- 最终私用 debug APK 与测试 APK 构建成功；19 项 JVM 测试通过（7 输入、6 手势、6 资源匹配）。`work/android-catalog-final-build.log`。
- OPPO 离线解析探针通过：拒绝错平台、10 分用户评分、无评论数、错标题及试玩版分数；同时验证贴纸尺寸、RGBA 通道、图像上下方向。该探针无网络。`work/android-catalog-offline-probe.txt`；本轮最终版本也再次通过，见工具执行记录。
- 在 OPPO 上新建只有名称的《Advance Wars (USA)》验证记录（不含 ROM），实时取得封面、Intelligent Systems、Nintendo、2001-09-09、本平台 92 分，来源记录包含 Wikidata Q953229 与对应 Metacritic 页面。`work/android-catalog-online-probe.txt`、`work/android-catalog-qa/catalog-report.json`。
- 原缓存离线加载：注入禁止网络的传输器，网络调用为 0，封面和资料可读取。最终增强复测也已通过：实时新查询落盘后再次离线打开，网络调用同样为 0。
- 火红、银完成真实选机/主题/选卡/启动及投影 Start/A 输入。6 秒核心短采样约 60fps，仅为短启动验证，不代表持续游玩、听感或游戏内存档通过。`work/android-catalog-gba-ui-probe.txt`、`work/android-catalog-gbc-ui-probe.txt`。
- 已查看两款媒体实际截图。银封面正向、文字清楚、资料已显示；旧火红裁剪碰到顶部标题，已改为只裁底部。证据 `work/android-catalog-qa/{gba,gbc}/media.png`。这些是微调前证据；最终版本截图与报告统一在 `work/android-catalog-final-qa`，下面记录最终结论。

## 最终 OPPO 回归（用户再次解锁后）

最终 App / 测试包已安装，四项真机探针全部通过：

| 探针 | 结果与证据 |
|---|---|
| catalog | 24 款实际游戏均有封面；库共 25 条含原创探针；Advance Wars 新名称实时匹配、旧缓存和新下载缓存离线重开均 0 次网络调用。`work/android-catalog-final-network.txt`、`work/android-catalog-final-qa/catalog-report.json` |
| catalog-ui | 火红、绿宝石封面/开发商/评分显示；同一媒体实体，切卡不重载；五次交替选择后最终封面、标题及游戏 ID 一致。`work/android-catalog-final-ui.txt`、`work/android-catalog-final-qa/files/media-local-qa/report.json` |
| game-gba | 实际导航至火红、进入开机动画、投影 Start/A 触摸；6.001 秒推进 358 帧，约 59.66 核心 fps。`work/android-catalog-final-gba.txt` |
| game-gbc | 实际导航至银、横屏选卡后竖屏启动、投影 Start/A 触摸；同样 6.001 秒 358 帧。`work/android-catalog-final-gbc.txt` |

已逐张查看最终 FireRed.png、Emerald.png，以及 gameplay-qa 中 GBC media.png、两机 boot.png / after-input.png。GBA 顶部 Pokémon 和版本名完整，红/绿卡壳与封面对应，印刷没有白色反光覆盖，资料靠近卡带且分页点独立；GBC 银封面正向、深蓝卡壳、资料清晰，缺评分显示“/”。火红可见开机动画与帮助页，银可见 GAME FREAK 开机动画及输入后的对话框。GBA 盒图仍属合理裁剪拉伸回退，不冒充原装贴纸。

上述只证明这三款卡带的最终截图、快速绑定，以及两款游戏短启动/输入，不是持续游戏性能、实际音频听感、全部主题、全部游戏或游戏内存档验收。未操作系统锁屏设置；测试窗口启动后仅通过 KEEP_SCREEN_ON 防止中途锁屏。验证已结束，恢复普通应用首页。

其余缺口：媒体邻居连续滚轮、完整拿起/机械装载与音效、PSP/NDS/3DS 核心和长时间性能、所有主题与平板实际观感尚未完成。本轮不扩大到公开发布或平台整体适配完成。Mac 与 iOS 原工程 git 状态保持干净。
