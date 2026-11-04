# Uncle Ed.

经典再次上场。A tactile, three-dimensional handheld-emulation frontend for
rediscovering games you already own.

**Development staging — not a public release. The Android prototype has not passed product-experience acceptance.** The Apple application exists;
Android is a native port in progress. An APK compiling successfully does not
establish gameplay compatibility, save reliability, performance, or parity.
See [Android acceptance](Docs/ANDROID-PARITY.md) and
[distribution boundaries](Docs/DISTRIBUTION.md).

The private repository's [v0.1.0-beta.1 closed-test package](Docs/Releases/v0.1.0-beta.1.zh-CN.md)
provides an isolated Android ARM64 installer and corresponding core source.
It does not establish public asset clearance, full platform parity, or an Apple
distribution release. Game files and user saves remain separate.

## Built with the open-source community

感谢 [RetroArch](https://github.com/libretro/RetroArch) / [libretro](https://github.com/libretro/libretro-common)
团队，以及 [mGBA](https://github.com/mgba-emu/mgba)、[melonDS DS](https://github.com/JesseTG/melonds-ds)、
[melonDS](https://github.com/melonDS-emu/melonDS) 和 [PPSSPP](https://github.com/hrydgard/ppsspp) 的维护者。
Uncle Ed. 自行实现前端与 libretro 宿主；模拟能力来自各上游核心。
详见 [项目来源、版本及本地修改](UPSTREAM.md) 和 [第三方许可](THIRD_PARTY_NOTICES.md)。

## Product requirements and migration

The [consolidated requirements](Docs/Product/PRODUCT-REQUIREMENTS.zh-CN.md), [staged Android plan](Docs/Product/ANDROID-IMPLEMENTATION-PLAN.zh-CN.md), and [79-item traceability matrix](Docs/Product/REQUIREMENTS-TRACEABILITY.csv) are the product baseline. Match the established iOS experience; do not evolve the generic prototype UI as the product.

## Repository layout

- `Sources`: shared Apple geometry, materials and desktop application.
- `Mobile`: native UIKit application for iPhone and iPad.
- `Android`: native Android application, Filament renderer and libretro bridge.
- `Shared`: distribution readiness and asset provenance records.
- `Scripts`: model conversion and publication auditing.

Game files, firmware, saves, emulator binaries, private theme artwork and signing
credentials are supplied separately. This project provides no commercial games
or firmware. Use the system document picker to import files you are entitled to
use. Do not commit personal libraries or build output.

The existing private appearance is retained in a local development asset pack.
The owner has **not yet approved the public asset selection**. Software licensing
does not grant permission to redistribute third-party character artwork.

## Android development

Requires JDK 21, Gradle 8.13, Android SDK 36, NDK 27.2.12479018, CMake 3.22.1.
See [Android build instructions](Android/README.md). The first physical target is
OPPO Find X6. Tablet testing currently uses an emulator; it must not be reported
as physical tablet testing.

## License

Self-authored source: **GPL-3.0-or-later**, see [LICENSE](LICENSE).
The author's personal learning / non-commercial intent adds no restriction to
GPL recipients. Dependencies retain their licenses and notices; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Artwork is separately licensed.
