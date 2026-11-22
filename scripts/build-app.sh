#!/bin/sh
set -eu

project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

swift build -c release --build-system native "$@"
binary_dir=$(swift build -c release --build-system native --show-bin-path "$@")
stage=$(mktemp -d "${TMPDIR:-/tmp}/thinkbox-package.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT

app_path="$stage/Think Box.app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$project_root/scripts/Info.plist")
archive_path="$project_root/dist/Think Box $version.zip"

mkdir -p "$app_path/Contents/MacOS"
install -m 755 "$binary_dir/ThinkBox" "$app_path/Contents/MacOS/ThinkBox"
install -m 644 "$project_root/scripts/Info.plist" "$app_path/Contents/Info.plist"
ditto "$project_root/Sources/ThinkBox/Fonts" "$app_path/Contents/Resources/Fonts"
install -m 644 "$project_root/scripts/AppIcon.icns" "$app_path/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app_path"
codesign --verify --strict "$app_path"

# Package off iCloud Drive so its Finder metadata cannot modify the bundle.
ditto -c -k --keepParent "$app_path" "$stage/Think Box.zip"
mkdir -p "$project_root/dist"
mv "$stage/Think Box.zip" "$archive_path"
printf '%s\n' "$archive_path"
