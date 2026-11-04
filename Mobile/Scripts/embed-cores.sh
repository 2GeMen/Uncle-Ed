#!/bin/sh
set -eu
python3 "$SRCROOT/../Scripts/check-shared-visuals.py"
DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/cores"
mkdir -p "$DEST"
# Remove stale core products when a core is removed or the platform changes.
find "$DEST" -maxdepth 1 -name "*.dylib" -type f -delete
if [ "$PLATFORM_NAME" = "iphonesimulator" ]; then SOURCE="$SRCROOT/Cores/Simulator"; else SOURCE="$SRCROOT/Cores"; fi
for CORE in "$SOURCE"/*.dylib; do
  [ -f "$CORE" ] || continue
  cp "$CORE" "$DEST/$(basename "$CORE")"
  if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
    /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$DEST/$(basename "$CORE")"
  fi
done
