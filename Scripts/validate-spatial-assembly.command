#!/bin/zsh
set -eu
cd -- "$(dirname -- "$0")/.."
AUDIT_ROOT="$PWD/Build/AssemblyAudit"
AUDIT_APP="$AUDIT_ROOT/AssemblyAudit.app"
mkdir -p "$AUDIT_APP/Contents/MacOS" "$AUDIT_APP/Contents/Resources"
ln -sfn "$PWD/Assets" "$AUDIT_APP/Contents/Resources/Assets"
cp Scripts/validate-spatial-assembly.swift "$AUDIT_ROOT/main.swift"
xcrun swiftc Sources/PickerMotion.swift Sources/SpatialMachine.swift "$AUDIT_ROOT/main.swift" -module-cache-path "$PWD/Build/ModuleCache" -o "$AUDIT_APP/Contents/MacOS/AssemblyAudit"
"$AUDIT_APP/Contents/MacOS/AssemblyAudit" "${1:-$AUDIT_ROOT/result.json}"
