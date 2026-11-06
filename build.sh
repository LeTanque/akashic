#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
app_dir="$project_dir/build/Akashic.app"
binary_name="Akashic"

cd "$project_dir"
swift build -c release --product "$binary_name"

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$app_dir/Contents/Frameworks"
cp ".build/release/$binary_name" "$app_dir/Contents/MacOS/$binary_name"
cp Info.plist "$app_dir/Contents/Info.plist"

# SQLCipher is a dynamic framework (@rpath); ship it next to the binary via Frameworks.
sqlcipher_src=".build/release/SQLCipher.framework"
if [[ ! -d "$sqlcipher_src" ]]; then
  sqlcipher_src=".build/artifacts/sqlcipher.swift/SQLCipher/SQLCipher.xcframework/macos-arm64_x86_64/SQLCipher.framework"
fi
if [[ ! -d "$sqlcipher_src" ]]; then
  echo "error: SQLCipher.framework not found under .build/" >&2
  exit 1
fi
rm -rf "$app_dir/Contents/Frameworks/SQLCipher.framework"
cp -R "$sqlcipher_src" "$app_dir/Contents/Frameworks/SQLCipher.framework"
# Ensure the executable can resolve @rpath/SQLCipher.framework
install_name_tool -add_rpath "@executable_path/../Frameworks" "$app_dir/Contents/MacOS/$binary_name" 2>/dev/null || true

resource_src=".build/release/Akashic_Akashic.bundle"
if [[ -d "$resource_src" ]]; then
  cp -R "$resource_src" "$app_dir/Contents/Resources/"
fi

xattr -cr "$app_dir"
codesign --force --deep --sign - "$app_dir" 2>/dev/null || true

echo "Built $app_dir"
echo "Run: open \"$app_dir\""
