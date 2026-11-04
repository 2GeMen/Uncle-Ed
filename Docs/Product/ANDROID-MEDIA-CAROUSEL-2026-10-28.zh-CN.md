# Android 选卡连续滚轮

2026-10-28。无线 OPPO PGEM10 / Android 16，使用既有 24 款私用游戏库；保留 ROM、封面缓存与存档。

## 本轮结果

独立选卡页加入最多两个相邻媒体实体，共用一个 Filament 渲染器。横拖位置直接驱动三张媒体，松手吸附；短按邻居只选择，短按中心才启动游戏；长按拖动仍可旋转，释放后回正且不误启动。分页点可选远处目标，逐项连续到达，快速新目标覆盖旧目标。主题页切换仍沿用既有实现，不在本轮宣称已连续化。

滑入的实体直接升为中心，原中心转为反向邻居；不重载主模型、不全局淡出、不改变媒体比例。焦点提交等待实际 SurfaceTexture 呈现终点；资料与封面随已提交焦点更新。返回/进入下一阶段/导入完成时取消旧的滚轮事务，启动游戏时屏蔽预览翻页。

每个实体分别持有预期游戏 ID、卡贴纹理、上传缓冲和卡壳颜色，防止邻居覆盖主卡、旧异步结果串图。封面准备好后再发布邻居。释放离开三个活动槽位的纹理，GPU 卡贴纹理最多三份，不随收藏数量增长。缺失封面用占位图，仍可浏览。

原物理卡带、保护壳和主题几何未简化；媒体间距按预览视口和真实实体边界确定。未选中项只压暗材质 RGB，保留 alpha，不把根节点改透明。

## 真实截图发现并修复的两项问题

1. 同名材质包含多个独立实例，原绑定按名称去重，使卡壳只在侧边变色、正面灰白。现逐实例更新原色和焦点明暗，保留透明度；卡壳与卡贴颜色在滑入/滑出时连续。
2. UMD 的印刷网格依赖圆形透明遮罩，矩形封面直接上传会出现方角。Android 贴图增加圆形 alpha，导出消光 cover 使用 MASK / alphaCutoff 0.5；内部像素仍是不透明印刷，保留 sRGB，避免恢复环境反光泛白。五种媒体 GLB 已重导；只对三种手机媒体完成本轮实际核查。

## 验证

- 私用 App 和测试 APK 构建成功；19 项 JVM 单测通过。`work/android-media-carousel-release-check.log`。
- 最终 GBA 连续拖动、同实体升格、反向复用、长按旋转、快速最终目标、纹理上限通过。实际呈现 21 个不同位置；升格边界 0px 偏移；主模型载入计数 2→2，滑入实体 ID 前后一致；最终活动纹理 3 份。
- GBC、PSP：点击右侧邻居不会启动核心；滑入实体直接升格；反向复用原实体；长按旋转与回正；活动纹理不超过 3 份。PSP 核心未启动，不能据此宣称 PSP 可游玩。
- 遮罩/像素/评分离线探针通过：UMD 四角 alpha 0、中心 alpha 255；GBA 裁剪/RGBA 正确，严格平台媒体评分筛选仍通过。`work/android-media-mask-probe.txt`。
- 共用渲染器改动后的首页慢滑、静止长按、邻居点击、快速目标及连续升格回归通过。`work/android-media-home-regression.txt`。
- 两款实际游戏短启动/Start/A 再次通过：`work/android-media-gba-regression.txt`、`work/android-media-gbc-regression.txt`。最后导航取消保护加入后的 GBA 启动也通过：`work/android-media-launch-final.txt`。这些是短启动和输入，不是长期性能/听感/游戏内存档验收。

最终媒体证据统一保存在 `work/android-media-carousel-delivery/files/`：media-carousel-qa 和 media-shelf-qa/{gbc,psp}。已查看 GBA 三卡、拖动、升格、旋转，GBC 首项和第二项，以及 PSP 正面与旋转截图；最终圆形遮罩已肉眼确认没有方角越出 UMD。帧序列和 report.json 为本次最新；早期灰壳和方形溢出截图只作修复过程记录，不能混作交付证据。

对应最终日志：`work/android-media-carousel-delivery-probe.txt`、`work/android-media-shelf-gbc-final.txt`、`work/android-media-shelf-psp-final.txt`。首页证据在 `work/android-media-carousel-final-qa/files/home-gesture-qa`。

## 边界与后续

本轮以手机横屏媒体页为验证范围。Android 平板、NDS/3DS 媒体、全部主题、系统字体/多窗口/生命周期压力尚未完成；未选中媒体标题和焦点拿起细节仍需与 iOS 完整对照。UMD 读盘面衍射、全转背面细节与机械装载四段动画/声音不算通过。整页体验验收仍为 0，不把局部回归等同整体移植完成。

下一项优先：沿共享 MediaLoadingMotion 逐机型实现拿起、对槽、插卡和开机连续动作；PSP 是整套 UMD 放入后仓，关盖后仅内部盘片旋转，再翻正面，机械声去重。继续保留原建模质量，不以裸盘/淡出替代。

原 Mac/iOS 工程未修改；私用导出模型、ROM、封面及证据只留在外置私用资源/设备/work，不放公开仓库；未创建自动化，未发布 release。
