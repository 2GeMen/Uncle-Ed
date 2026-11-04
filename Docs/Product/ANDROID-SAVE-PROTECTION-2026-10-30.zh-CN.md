# Android 卡带存档写入保护

日期：2026-10-30。延续手机收口；OPPO未发现无线服务，旧端口拒绝连接。本轮没有安装/操作手机，Android平板继续延期。

## 已修问题

原Native存档在ofstream写入后不检查写入/关闭状态，直接rename覆盖正式文件；短写或磁盘满可将不完整文件替换旧档。现对SRAM/RTC逐文件使用同目录唯一临时文件，完整写入（支持短写、EINTR）、fsync成功、close成功后才原子rename。任一步失败都清理本次临时文件，保留对应旧文件。无跨SRAM/RTC的联合事务或断电持久化保证，不宣称两者一起回滚。

Native向会话返回失败状态，暂停/退出写入失败时向用户提示检查可用空间；同会话只提示一次，后续仍可重试。保存请求在写入前取走，避免写入中收到的新暂停请求被旧请求清空。失败不强行退出游戏，不降低模型或音频设置。

这项保护属于前端持有的卡带SRAM/RTC；PSP核心自行管理Memory Stick文件，未据此宣称PSP游戏内存档验收完成。

## 验证

- 原创真实文件夹具12项：正常/首次保存、短写、EINTR、磁盘满部分写入、fsync失败、close失败、rename失败、零长度写返回、目录不存在、空指针/空内容。检查每次失败后旧字节不变，临时文件无残留。
- macOS clang C++17、Wall/Wextra/Werror、AddressSanitizer与UBSan执行通过；同一测试NDK ARM64/API28静态C++运行库交叉编译通过，Android设备执行尚待连接。
- 主应用/测试包构建通过，32项JVM、5项公开隔离测试通过。APK签名检查及资源条目核对另存本地。
- 候选APK SHA-256：57c621c914c1c8c06200209d2d50e785dee34112cced3e7a8ee66cdfb5d8391a。**尚未部署OPPO**，上一轮实际GBC/FireRed保存结果属于旧候选，不冒充新增I/O保护的真机回归。

复现：clang++ -std=c++17 -Wall -Wextra -Werror -fsanitize=address,undefined Tests/Native/atomic-save-check.cpp -o /tmp/uncleed-save-check，然后执行该程序。测试不需要ROM。

本地证据：work/android-atomic-save-check.txt、android-atomic-save-check-arm64、android-save-protection-20261030-build.log。

## 下一步

无线恢复后，先执行同一ARM64故障测试，再保留数据安装候选，复验独立GBC存档及错误提示路径；继续PSP游戏内进度保存、完整战斗/城市场景。最新iOS整页配对与主观触感仍在清单中，平板不作为近期阻塞项。

## OPPO补验（无线恢复后）

新端口恢复连接；12项同一ARM64真实文件故障测试全部通过。主/测试候选已保留数据安装。用上轮独立宝可梦银档读取后，将该唯一cache存档目录暂时改为文件阻断写入；Native返回失败、实际App提示出现、备份旧档哈希未变。恢复目录、关闭提示、继续游戏及再次暂停保存成功；测试finally保证恢复原独立目录，未用于正式存档。

随后游戏自身SAVE正常结束，正常卸载核心→重新装载→CONTINUE恢复同人物/房间/左向。截图已检查。旧档RTC菜单从上轮Sunday10:17推进至本轮Monday02:56，为跨日显示观察，不作为人为控制的时间偏差/多日测试。

本轮独立存档异常与正常流程均欠载0；最终正式存档哈希核对、PSP后续结果另记。证据：私有work/android-save-protection-device-20261030/atomic-save-arm64.txt、save-failure-review.json、save-failure-dialog.png和gbc系列截图。上文“候选未部署”属于补验前状态，以此处更新为准。

## 本轮最终部署及战神复现

最终候选57c621c914c1c8c06200209d2d50e785dee34112cced3e7a8ee66cdfb5d8391a已保留数据部署。GBC故障提示/旧字节保护/恢复重试与正常游戏内保存重载通过。正式336个存档文件前后哈希一致，GBC/PSP探针均正常退出（code=-1、gracefulCoreStop=true），测试二进制已清理；未发布/推送。

战神本轮41339核心帧，覆盖新Easy游戏开场、第一艘船的肩键挣脱教学、短时多敌战斗和死亡重试。累计欠载2，均在开场转换时frame8520–8521附近（播放后约141.9秒）；首事件Native运行56.948ms、视频回调0.121ms。全会话播放后最坏75.047ms；音频追赶恢复29次，不能把欠载2写成全程无断续。后续战斗与重试未再增加欠载。该事件只是观测时的耗时，尚非完整CPU堆栈定位；不能据此断言唯一根因。SRAM/RTC前端写保护不覆盖PSP的Memory Stick写入，片头到该场景未执行卡带写入，未改变核心二进制或渲染设置。

未达到持久化保存点，独立SAVEDATA目录目前仅.nomedia，不将内存检查点/死亡重试当成进度落盘。尾段30秒已回到死亡/检查点菜单，不作为连续战斗基准。PSP实际存档与更完整战斗/城市仍待，后续需对开场141秒附近做有边界CPU采样，继续优化核心尖峰，不通过降低模型质量或扩大音频延迟掩盖。

证据：work/android-save-protection-device-20261030/summary.json、war-reproduced-underruns.json、war-report.json、war-39.png、normal-saves-before/after.txt。当前无线地址192.168.1.115:40419，仅为本轮连接记录，后续应重新发现服务。
