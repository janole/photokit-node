#!/bin/sh

set -eu

package_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
signing_identifier="com.janole.photokit-node.helper"

swift build --package-path "$package_directory" "$@"
binary_directory=$(swift build --package-path "$package_directory" "$@" --show-bin-path)
app_path="$binary_directory/PhotoKit Node Helper.app"
helper_path="$app_path/Contents/MacOS/photokit-helper"

rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS"
cp "$binary_directory/photokit-helper" "$helper_path"
cp "$package_directory/Resources/PhotoKitHelper-Info.plist" "$app_path/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "${PHOTOKIT_HELPER_VERSION:-0.1.0}" "$app_path/Contents/Info.plist"

if [ -n "${PHOTOKIT_CODE_SIGN_IDENTITY:-}" ]; then
    codesign --force --sign "$PHOTOKIT_CODE_SIGN_IDENTITY" --identifier "$signing_identifier" "$app_path"
else
    codesign --force --sign - --identifier "$signing_identifier" \
        --requirements "=designated => identifier \"$signing_identifier\"" "$app_path"
fi

codesign --verify --strict "$app_path"
codesign --display --requirements - "$app_path" 2>&1
printf '%s\n' "$helper_path"
