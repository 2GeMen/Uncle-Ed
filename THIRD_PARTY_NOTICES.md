# Third-party components

Do not replace upstream notices with Uncle Ed's GPL header. This inventory
separates frontend/API code from emulator implementations.

| Component | Usage | License / release condition |
|---|---|---|
| libretro API header | Apple and Android host declarations | MIT-style permission notice retained in each `libretro.h` |
| Filament 1.66.0 | Android native rendering | Apache-2.0; LICENSES/Filament-Apache-2.0.txt; Maven dependency |
| mGBA, revision 7a12d6d4b9acb14c0ae62c9166b6a2f3d08007f6 | Android GBA/GBC core development | MPL-2.0; LICENSES/mGBA-MPL-2.0.txt; provide exact source, modifications and build instructions for distribution |
| melonDS DS f394adbacb5722ee97c1b37c8064da9a25818310 | Android NDS core, software renderer + JIT | GPL-3.0-or-later; LICENSES/melonDS-DS-GPL-3.0.txt; dependency commits in Shared/android-core-lock.json; reproducible script; binary distribution audit still pending |
| PPSSPP 9bece86f087c4f3a2fb1af58dd90d89282013616 | Android PSP core, GLES + bundled FFmpeg | GPL-2.0-or-later; LICENSES/PPSSPP-GPL-2.0.txt; unload callback patch in Android/patches, reproducible script; FFmpeg/transitive source bundle and binary release audit still pending |
| Azahar | 3DS core, existing private setup | GPL-2.0-or-later; Android gameplay not enabled; exact source/build provenance pending |
| MoltenVK | macOS graphics dependency | Apache-2.0; corresponding binary version and notices must be locked before distribution |
| Vulkan headers | Apple C bridge declarations | Preserve Khronos/SPDX notices in Sources/Vendor; inventory transitive licenses before release |
| ZIPFoundation | Apple archive import | MIT; preserve package's license at the resolved revision |

Upstream core licenses must be rechecked against the exact revision actually
shipped. This file is not evidence that the pending core binaries have compliant
source packages. Unpinned nightly downloads are not accepted as release provenance.

No ROM, firmware, BIOS, keys, saves, commercial soundtrack or third-party character
artwork is granted a license by this document. Original branding and synthesized
sounds also require explicit entries in Shared/asset-provenance.json before public
packaging. Existing private theme resources remain outside public distribution.

Android core binary packs are generated outside this tree. PPSSPP's bundled FFmpeg and every FetchContent/submodule dependency must accompany the exact corresponding-source release and retain their own licenses. The development build records actual revisions and patches; source-built does not mean that the distribution checklist or commercial-game compatibility has passed. Original ARM/MIPS probe generators under Tests/Fixtures contain no Nintendo/Sony logo, BIOS, firmware dump or commercial game content. They are diagnostic programs, not built-in game content.

Android PPSSPP development build additionally carries the source patch `Android/patches/ppsspp-libretro-binary-append.patch` for binary append in libretro VFS, alongside the context teardown guard. The pinned upstream revision, patch hashes and reproducible flags remain recorded by `Scripts/build-android-ppsspp.py`; binary distribution approval remains pending.

The Android development PPSSPP build also carries `Android/patches/ppsspp-kirk-public-field-inverse.patch`, a fixed-field inverse fast path restricted to public signature verification. Original libkirk GPL-2.0-or-GPL-3.0 notices are preserved; private signing retains its original path. Differential tests are reproducible with `Scripts/check-android-kirk.py`. This does not make binary distribution ready.
