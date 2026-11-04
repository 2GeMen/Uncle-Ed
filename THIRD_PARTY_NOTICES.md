# Third-party components and source attribution

Uncle Ed. credits the [RetroArch team](https://github.com/libretro/RetroArch)
and the [libretro ecosystem](https://github.com/libretro/libretro-common).
It implements its own frontend/host bridge and loads libretro cores. Using the
libretro API does not establish that the complete RetroArch application is
embedded. The API headers retain their original RetroArch-team copyright and
MIT-style permission statements; RetroArch itself is GPL-3.0.

See [UPSTREAM.md](UPSTREAM.md) for upstream links, pinned sources, local changes
and the exact distinction between frontend, API and emulator implementations.
Do not replace upstream copyright notices with Uncle Ed's GPL header.

| Component | Upstream / use | License / record |
|---|---|---|
| libretro API headers | [libretro-common](https://github.com/libretro/libretro-common), host API | Original header-specific MIT-style notices retained; LICENSES/libretro-API-MIT.txt and libretro-Vulkan-API-MIT.txt |
| mGBA | [mgba-emu/mgba](https://github.com/mgba-emu/mgba), GBA/GBC | MPL-2.0; Android revision 7a12d6d4b9acb14c0ae62c9166b6a2f3d08007f6 |
| melonDS DS | [JesseTG/melonds-ds](https://github.com/JesseTG/melonds-ds), NDS | GPL-3.0-or-later; Android revision f394adbacb5722ee97c1b37c8064da9a25818310; dependency revisions in Shared/android-core-lock.json |
| melonDS | [upstream](https://github.com/melonDS-emu/melonDS) / [used fork](https://github.com/JesseTG/melonDS) | Per-file GPL notices retained; Android revision 16f127dbb587a73371827ce79689c5d237c4b59b |
| PPSSPP | [hrydgard/ppsspp](https://github.com/hrydgard/ppsspp), PSP | GPL-2.0-or-later; Android revision 9bece86f087c4f3a2fb1af58dd90d89282013616; all three local patches in Android/patches |
| FFmpeg | [FFmpeg](https://ffmpeg.org/), vendored by pinned PPSSPP | LGPL-2.1-or-later and file-specific notices retained; exact sources and ext/ffmpeg-build configuration in PPSSPP source archive |
| Filament 1.66.0 | [google/filament](https://github.com/google/filament), Android rendering | Apache-2.0; LICENSES/Filament-Apache-2.0.txt; Maven dependencies |
| Azahar | [azahar-emu/azahar](https://github.com/azahar-emu/azahar), private Apple 3DS core | GPL-2.0-or-later; absent from Android beta; Apple exact source/build provenance still pending |
| MoltenVK | [KhronosGroup/MoltenVK](https://github.com/KhronosGroup/MoltenVK), Apple graphics | Apache-2.0; exact Apple binary provenance still pending |
| Vulkan headers | [KhronosGroup/Vulkan-Headers](https://github.com/KhronosGroup/Vulkan-Headers) | Copyright/SPDX notices retained per file in Sources/Vendor |
| ZIPFoundation 0.9.20 | [weichsel/ZIPFoundation](https://github.com/weichsel/ZIPFoundation), Apple ZIP import | MIT, LICENSES/ZIPFoundation-MIT.txt; revision 22787ffb59de99e5dc1fbfe80b19c97a904ad48d |

## Android closed-test release evidence

The private v0.1.0-beta.1 Release includes the three core source archives,
recursive tracked PPSSPP submodules, vendored FFmpeg, eleven pinned melonDS DS
FetchContent dependencies, applied local changes, build flags and a rebuild
script. All three core targets were rebuilt from those archives. The APK's core
bytes were matched to recorded input binaries after reproducing NDK symbol
stripping. This is source/build evidence, not an all-game compatibility claim
or public artwork clearance. Preserve each dependency's original source notices;
this table is not a substitute for its file-level licenses.

PPSSPP changes cover unload-context protection, libretro binary append mode,
and a fixed-field inverse fast path restricted to public signature verification.
The latter preserves original libkirk notices and leaves private signing on its
original path. See Android/patches and Scripts/check-android-kirk.py.

## Separate rights and remaining work

Self-authored code is GPL-3.0-or-later. The author's personal learning and
non-commercial intent adds no restriction to GPL recipients. No ROM, firmware,
keys, saves, soundtrack or third-party character artwork is licensed by this
notice. The owner requested public access to the existing beta on 2026-11-04;
third-party appearance redistribution rights have not been established. Apple nightly binaries still need
exact source/build provenance before an Apple distribution release.

No upstream endorsement or affiliation is implied. Keep upstream license and
copyright notices, source access and local-change records when redistributing.
