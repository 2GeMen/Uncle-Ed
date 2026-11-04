# Public distribution boundaries

The public source tree starts from a clean snapshot, not from the private
repository's history. Do not push the old history: it contains game artwork,
private test captures and local library metadata even when current ignores hide
ROM directories.

## Never distributed

Commercial ROMs/disc images; BIOS, firmware and console keys; saves, save states,
shader caches, cover caches, game-derived screenshots/audio, downloaded reference
photos, user documents, signing keys/profiles, developer credentials and build
machine paths. No ROM download links or instructions to bypass encryption.
Users import files they are entitled to use with the platform's file picker.

## Assets are separate from code

Original Uncle Ed branding and synthesized mechanical sounds are candidates for
inclusion. Third-party character artwork, logos and limited-edition prints are
not relicensed by the software license. Do not bundle the private Assets tree.
All distributable assets require an explicit provenance entry. Unreviewed assets
block public release. A local private asset pack can preserve the existing demo
appearance without being copied to source archives or installers.

## Emulation dependencies

This is an independent libretro frontend. Using the libretro API does not mean
all of RetroArch is embedded. Preserve the actual notices for every header,
core, graphics library and package used. For each distributed core, record an
immutable source revision, local patches, build flags/toolchain and the binary
hash; provide corresponding source and scripts alongside the release. A link to
an unpinned nightly binary is not an adequate provenance record.

Self-authored code is licensed GPL-3.0-or-later, as approved by the owner on 2026-10-27. See LICENSE.
Each dependency retains its own license. A non-commercial personal motivation
is not an additional restriction on GPL recipients.

## Installers are not equivalent across platforms

Android requires an APK signed with the project's persistent key and native
libraries for the declared ABI/page size. Debug APKs are test builds only.
macOS ad-hoc signing is not Developer ID notarization.
iOS/iPadOS device installs require provisioning appropriate to the recipient;
an unsigned IPA or simulator app is not a universally installable release.
Do not claim cross-device validation from compilation alone.

Release workflow is blocked until asset, license, source, build, input, save,
audio/performance and distribution-signing checks are recorded.
