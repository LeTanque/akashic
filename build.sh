#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
app_dir="$project_dir/build/Akashic.app"
binary_name="Akashic"

cd "$project_dir"
swift build -c release --product "$binary_name"

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp ".build/release/$binary_name" "$app_dir/Contents/MacOS/$binary_name"
cp Info.plist "$app_dir/Contents/Info.plist"

resource_src=".build/release/Akashic_Akashic.bundle"
if [[ -d "$resource_src" ]]; then
  cp -R "$resource_src" "$app_dir/Contents/Resources/"
fi

xattr -cr "$app_dir"
codesign --force --sign - "$app_dir" 2>/dev/null || true

echo "Built $app_dir"
echo "Run: open \"$app_dir\""
