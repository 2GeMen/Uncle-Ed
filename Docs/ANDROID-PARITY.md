> Superseded for implementation planning by [the consolidated product requirements](Product/PRODUCT-REQUIREMENTS.zh-CN.md) and [the phased migration plan](Product/ANDROID-IMPLEMENTATION-PLAN.zh-CN.md). Existing Android screens have NOT passed visual or interaction acceptance.

# Android parity contract

Android phones mirror the current iPhone scope: GBC, GBA, PSP. Tablets expose the
five-family UI, with unavailable emulation explicitly disabled until verified.
Do not claim 3DS runtime support merely from successful import or 3D rendering.

Shared behavior: machine → theme → independent media shelf → physical loading →
gameplay. Remember each machine's last theme. Every preview can be rotated; a
short swipe changes one item, a longer direct drag rotates the focused model.
Selection light follows the physical outline and real lighting stays active.
Keep game pixels and input coordinates in the same aspect-preserving transform.

Phones browse in landscape; selecting GBC media transitions to portrait before
loading. GBA/PSP play in landscape with fixed input axes. Tablets honor safe
areas and display size/height settings. Menu access belongs in the upper left,
not over the D-pad. Navigation targets are at least 48dp on Android.

Use Android document selection with scoped storage; copy into private app data,
stream SHA-256, reject traversal/symlink/oversized archive content and deduplicate
by payload hash. Never delete the external source. Cover/metadata queries need
an informed opt-in and send titles/platform/region, not ROM bytes or saves.

Track touches by pointer ID. Release every key on CANCEL, focus loss, pause,
rotation, eject and navigation. Respect platform haptic settings. D-pads tilt
as one assembly; PSP keeps separate caps. GBA/PSP shoulder inputs target their
modeled physical keys. NDS/3DS keep their accessible auxiliary shoulder buttons.

Preserve PCM audio without an unbounded queue, use emulated FPS for pacing, and
record frame/audio underrun metrics. Test software and hardware cores separately.
Archive real evidence for import, loading, diagonal/multi-touch, stick, shoulder,
audio, safe exit and in-game save/reload on both a phone and tablet.
