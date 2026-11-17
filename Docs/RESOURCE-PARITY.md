# Public/local runtime resource parity · 2026-11-17

At the owner's request, the public source now includes the actual local runtime
resources, including the original app icon. It does not substitute a generic icon,
plain-color themes, simplified models or lower-resolution textures.

| Source package location | Restored resources |
|---|---|
| Assets/Branding | Original PNG and Mac ICNS; Mac bundle icon metadata |
| Mobile/Resources/Images.xcassets | Native 1024px iOS AppIcon and machine logos |
| Assets/Skins, Patterns, Logos | Shared Apple 3D scenes, prints, static bakes and theme previews |
| Assets/Sounds | Original generated mechanical loading/read sounds |
| Assets/Covers and catalog JSON | Existing bundled illustration/metadata resources, not ROM files |
| Assets/Systems and Licenses | Existing upstream replacement system resources and notices |
| Android/app/src/main/assets | All 525 existing Android model, rim, lighting, logo, audio, catalog and replacement-system resources |
| Android/app/src/main/res | Original icon in five launcher densities, adaptive icon, colors and splash |

The shared Apple resource tree is the existing iOS superset; all files common to
the Mac and iOS local trees were byte-identical. Android files and launcher input
files were compared byte-for-byte with the existing local development packs.
All 905 inventoried runtime files are registered in Shared/asset-provenance.json.
The clean source export omits none of these files.

Default Android builds no longer need UNCLEED_PRIVATE_ASSETS or
UNCLEED_PRIVATE_RESOURCES for appearance or branding. These legacy overrides remain
optional for development. Emulator libraries remain build dependencies, not
artwork: use UNCLEED_CORE_PACK pointing at an ABI-organized pack built from the
provided exact corresponding sources. The old UNCLEED_PRIVATE_CORES variable is
still accepted for compatibility. Personal libraries, saved games and signing
credentials are excluded from Git and from resource packs.

Beta.2 is built from the clean exported source without private artwork overrides.
Its 525 runtime assets, six packaged PNG icon resources and three emulator core
libraries match the prior downloaded beta byte-for-byte. The version code changes
to 2, preserving the beta package ID and signing identity for updates. Mac source
build packaging and native iPhone/iPad icon catalog compilation were separately
checked; these checks do not create publicly distributable Apple installers.

The inventory distinguishes approved original project branding/audio from
owner-authorized third-party artwork whose redistribution rights have not been
independently established. Inclusion is not a blanket GPL relicense of third-party
prints, marks or game illustrations. The audit still rejects ROMs, personal saves,
credentials, arbitrary cover-cache files and unregistered/hash-changed artwork.
