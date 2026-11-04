# 上游项目与致谢 / Upstream projects and acknowledgements

Uncle Ed. 感谢 RetroArch / libretro 社区和所有模拟器、图形及工具库维护者。掌机模拟能力来自下列上游项目；Uncle Ed. 的工作重点是机型呈现、浏览装载、输入交互、资源管理和各平台前端体验。

## RetroArch 与 libretro 的关系

- **[RetroArch](https://github.com/libretro/RetroArch)**：libretro API 的跨平台参考前端，采用 GPL-3.0。感谢其团队建设和维护的生态。
- **[libretro API / libretro-common](https://github.com/libretro/libretro-common)**：Uncle Ed. 使用的核心接口；[API 文档](https://docs.libretro.com/development/cores/developing-cores/)。
- 当前构建清单显示，Uncle Ed. 自行实现前端与宿主桥接，并加载 libretro 核心；不应将它描述为“把完整 RetroArch 应用打包换皮”。项目直接使用的 libretro.h 与 Vulkan 接口头保留了 The RetroArch team 的版权及各自的 MIT 风格许可，见 [libretro 许可](LICENSES/libretro-API-MIT.txt) 和 [Vulkan 接口许可](LICENSES/libretro-Vulkan-API-MIT.txt)。核心内部还可能使用 libretro-common，具体文件的许可沿用源码声明。

## 模拟器核心

| 上游 | 在本项目中的用途 | Android 测试版固定来源与许可 |
|---|---|---|
| [mGBA](https://github.com/mgba-emu/mgba) | GBA / GB / GBC 模拟 | [7a12d6d4…](https://github.com/mgba-emu/mgba/tree/7a12d6d4b9acb14c0ae62c9166b6a2f3d08007f6)，MPL-2.0 |
| [melonDS DS](https://github.com/JesseTG/melonds-ds) | NDS 的 libretro 核心 | [f394adba…](https://github.com/JesseTG/melonds-ds/tree/f394adbacb5722ee97c1b37c8064da9a25818310)，GPL-3.0-or-later |
| [melonDS](https://github.com/melonDS-emu/melonDS) / [所用分支](https://github.com/JesseTG/melonDS) | melonDS DS 的底层模拟实现 | [16f127db…](https://github.com/JesseTG/melonDS/tree/16f127dbb587a73371827ce79689c5d237c4b59b)，保留各文件 GPL 声明 |
| [PPSSPP](https://github.com/hrydgard/ppsspp) | PSP 模拟与 libretro 核心 | [9bece86f…](https://github.com/hrydgard/ppsspp/tree/9bece86f087c4f3a2fb1af58dd90d89282013616)，GPL-2.0-or-later |
| [Azahar](https://github.com/azahar-emu/azahar) | Apple 私用开发环境的 3DS 核心 | 不随本次 Android 测试包分发；Apple 二进制精确源码仍待核验，不以 Android 的验证结果代替 |

PPSSPP 的本地修改位于 [Android/patches](Android/patches)：卸载后的图形上下文保护、二进制追加模式、仅用于公开签名校验的固定有限域求逆优化。变更补丁保留上游版权；核心源码附件已经应用这些补丁，不能重复应用。

## 其他组件

| 项目 | 用途 | 许可与记录 |
|---|---|---|
| [FFmpeg](https://ffmpeg.org/) / [PPSSPP 内的实际源文件](https://github.com/hrydgard/ppsspp/tree/9bece86f087c4f3a2fb1af58dd90d89282013616/ext/ffmpeg) | PSP 音视频解码 | 随该 PPSSPP 修订提供的 FFmpeg 源码及构建配置，保留 LGPL-2.1-or-later 与文件级声明；不是仅指向另一个版本的下载链接 |
| [Filament](https://github.com/google/filament/tree/v1.66.0) | Android 3D 渲染 | 1.66.0，Apache-2.0；相关依赖保留其各自声明 |
| [MoltenVK](https://github.com/KhronosGroup/MoltenVK) | Apple Vulkan 图形桥接 | Apache-2.0；Apple 分发所用精确版本仍待锁定 |
| [Vulkan-Headers](https://github.com/KhronosGroup/Vulkan-Headers) | Apple 图形 API 声明 | 本地文件的 SPDX 声明及 Khronos 版权保留原样 |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | Apple ZIP 导入 | 0.9.20 / 22787ffb59de99e5dc1fbfe80b19c97a904ad48d，MIT |

melonDS DS 的十一项 FetchContent 依赖及精确修订见 [锁定清单](Shared/android-core-lock.json)；PPSSPP 的递归子模块和各文件许可见源码归档中的 SOURCE-MANIFEST.json 与原文件声明。此页是导航和致谢，不取代所有传递依赖的原始许可文本。

## 源码、许可与发行边界

- Uncle Ed. 自有代码采用 **GPL-3.0-or-later**，见 [LICENSE](LICENSE)。个人学习、非商业化是作者定位，不是对 GPL 使用者额外施加“禁止商用”的限制。
- [v0.1.0-beta.1](https://github.com/2GeMen/Uncle-Ed/releases/tag/v0.1.0-beta.1) 提供前端源码、三个 Android 核心及固定依赖的对应源码、本地补丁、重建脚本、许可包和 SHA-256。三核心均已从该源码归档重建，二进制入包的符号剥离过程另有指纹记录。
- 初次发布的二进制、核心源码和标签保持不变。此后补充的致谢/许可说明作为独立附件提供，并在 SHA256SUMS.txt 中记录，不将文档更新冒充新二进制版本。
- 源码和测试包不含商业 ROM、个人存档或签名私钥。原测试版在私有仓库准备；2026-11-04 按作者要求开放仓库和既有测试附件访问。第三方主题素材的再分发权利尚未核实，代码许可不覆盖第三方商标、图案、游戏封面及音乐。
- Uncle Ed. 是独立项目；上游链接及致谢不代表获得上游官方认证、合作或背书。

更细的组件说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，安装限制见 [测试版说明](Docs/Releases/v0.1.0-beta.1.zh-CN.md)。
