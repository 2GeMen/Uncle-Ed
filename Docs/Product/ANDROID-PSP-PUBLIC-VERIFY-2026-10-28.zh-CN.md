# Android PSP 公开签名验证热点优化

日期：2026-10-28。延续上一轮缓存修复，仍保持原建模、贴图、音频缓冲和游戏速度设置。

## 定位证据

Android simpleperf 对本调试应用采样20秒，11121个样本、丢失0。只采本应用，不做全系统采集。使用与安装包同版本的本地未裁剪核心符号解析。

战神 EmuThread 的调用链：sceUtilityLoadModule → 固件模块加载 → PRX解密 → KIRK签名校验 → ECDSA → bn_mon_inv。求逆样本集中在一段约217ms区间，与此前frame34约243ms尖峰相符。热点位于核心的固件模块加载路径。

证据 `work/android-war-simpleperf-record.txt`、`work/android-war-emu-profile.txt`、`work/android-war-crypto-sample-groups.json`。原始perf.data仅在私用work，不进入公开源码快照。

## 最终实现

为公开ECDSA验证中的椭圆曲线点运算增加固定有限域求逆路径：对KIRK的指定160位素数域使用有界二进制扩展GCD，保留Montgomery输入/输出形式；其他模数、非规范输入和预算不足回退原求逆实现。

只在ecdsa_verify的点运算调用链传入public_input；私钥签名、私钥到公钥和其他原有调用继续用原路径。完整签名校验、哈希、解密和验证结果不省略，不绕过原有模块签名检查。没有改变HLE表或存档序列化格式，也未增加全局验证状态。

风险边界：新增数学实现可能影响验证正确性，所以必须用原实现做差分、检查逆元恒等式、有效及无效签名、实际加密模块启动和上游回归；可变时间算法仅用于公开验证输入。既有私钥运算路径不改变；这不是对整个libkirk作新的安全或恒定时间承诺。

补丁 `Android/patches/ppsspp-kirk-public-field-inverse.patch`，仍锁定上游9bece86f087c4f3a2fb1af58dd90d89282013616并保留前两份已验证补丁。构建脚本严格核对三份补丁及允许修改的源码文件。ThinLTO尝试约1.01倍、实际长帧仍240ms，已移除，不作为成果。

## 验证

可复现测试脚本 `Scripts/check-android-kirk.py` 与 `Tests/Native/kirk-public-inverse-check.c`：直接从锁定Git基线构建参考库，与最终源码库在Android上比较，包含：

- 6153组原实现/新实现差分及模逆恒等式，覆盖0、1、模数减1、随机数和三组模数，每组2051个输入；指定素数域使用快速路径，其余模数组及零输入回退原实现。
- 两条KIRK曲线的已知有效签名和变更消息向量，共16次接受/16次拒绝检查（包括基准重复与参考/新实现执行，独立向量对为2组）。
- 新路径验证基准约12.8倍加速；这是独立算例耗时，不是游戏整体加速倍率。

证据 `work/android-kirk-repro-isolated/result.txt`。测试不使用ROM或实际私钥，临时设备目录自动清理。最终原生源码另跑90项C++单测、480项HLE回归；证据 `work/ppsspp-public-inverse-unit-final.txt`、`work/ppsspp-public-inverse-hle-final.txt`。

实际游戏：首次战神启动/菜单30秒欠载0，随后120秒欠载0；GTA Vice City Stories启动30秒欠载0。前一120秒期间另有同机数学基准，故再做无额外基准干扰的最终120秒，不把前一轮单独作为最终性能证明。证据分别为 `work/android-kirk-public-war-first-qa`、`work/android-kirk-public-war-final-120s-qa`、`work/android-kirk-public-gta-final-qa`；最终无干扰样本 `work/android-kirk-public-war-clean-120s-qa`。

## 后续边界

这些是启动/菜单/片头采样，skipKeys=true，不进入新游戏或覆盖用户进度。不能自动视为战神战斗、GTA城市场景、所有ROM兼容和长期听感验收。仍需这些场景、商业游戏内保存/重载，以及系统分屏、Android平板真机与全主题逐页iOS同尺寸视觉验收。3DS后端与公共发行素材仍未就绪。

最终无同机额外负载样本：120.227秒，核心均值59.9366fps、最低五秒59.6926fps，实际呈现约60.2087fps；音频欠载0、恢复0、焦点丢失0。播放开始后的最坏核心调用43.360ms（此前复现约243ms），整个会话最坏83.366ms包含音频播放前的启动。不能把后者误报为仍有同一音频尖峰。GTA30秒欠载0，播放后最坏约20.535ms。

最终源码对应90项C++单测、480项HLE测试通过；另有24项应用单测、5项公开树隔离测试。签名/安装包核心哈希、用户库数量以 `work/android-public-inverse-final-build-audit.json` 为准。原Mac/iOS工程未改。本地已保留修复提交，未推送；构建工作树仍是锁定基线加三份补丁。
