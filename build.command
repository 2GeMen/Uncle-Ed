#!/bin/zsh
set -eu
cd -- "$(dirname -- "$0")"
python3 Scripts/check-shared-visuals.py
mkdir -p Build
BUILD_CACHE="$(pwd)/Build/ModuleCache"
mkdir -p "$BUILD_CACHE"
xcrun clang -O2 -c Sources/Hardware.c -ISources -ISources/Vendor -o Build/Hardware.o -Wno-deprecated-declarations
xcrun clang -O2 -c Sources/Bridge.c -o Build/Bridge.o -Wno-deprecated-declarations
xcrun swiftc -O Sources/main.swift Sources/Classic.swift Sources/Library.swift Sources/GameCatalog.swift Sources/PickerMotion.swift Sources/Controls.swift Sources/Cartridges.swift Sources/Modern.swift Sources/GBCScene.swift Sources/MechanicalControls.swift Sources/SpatialMachine.swift Sources/SpatialCarousel.swift Sources/UniversalStage.swift Build/Bridge.o Build/Hardware.o -LFrameworks -lMoltenVK -Xlinker -rpath -Xlinker @executable_path/../Frameworks -framework SceneKit -framework OpenGL -module-cache-path "$BUILD_CACHE" -import-objc-header Sources/Bridge.h -framework Cocoa -framework AudioToolbox -o 'Uncle Ed.app/Contents/MacOS/UncleED'
mkdir -p 'Uncle Ed.app/Contents/Frameworks'
cp Frameworks/libMoltenVK.dylib 'Uncle Ed.app/Contents/Frameworks/'
mkdir -p 'Uncle Ed.app/Contents/Resources/cores'
mkdir -p 'Uncle Ed.app/Contents/Resources/Assets'
/usr/bin/rsync -a --delete Assets/ 'Uncle Ed.app/Contents/Resources/Assets/'
/usr/bin/rsync -a --delete Cores/ 'Uncle Ed.app/Contents/Resources/cores/'
cp Assets/Branding/UncleED.icns 'Uncle Ed.app/Contents/Resources/UncleED.icns'
codesign --force --deep --sign - 'Uncle Ed.app'
