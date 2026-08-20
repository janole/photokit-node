#!/bin/sh

set -eu

repository_directory=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
native_directory="$repository_directory/native/photokit-helper"
package_directory="$repository_directory/packages/cli"
output_directory="$package_directory/native"
expected_output_directory="$repository_directory/packages/cli/native"

if [ "$output_directory" != "$expected_output_directory" ]; then
    printf '%s\n' "photokit-helper: refusing unexpected package output path: $output_directory" >&2
    exit 70
fi

package_version=$(node -p "require(process.argv[1]).version" "$package_directory/package.json")
PHOTOKIT_HELPER_VERSION="$package_version" sh "$native_directory/scripts/build.sh" -c release --arch arm64

binary_directory=$(swift build --package-path "$native_directory" -c release --arch arm64 --show-bin-path)
source_app="$binary_directory/PhotoKit Node Helper.app"
source_binary="$source_app/Contents/MacOS/photokit-helper"
packaged_app="$output_directory/PhotoKit Node Helper.app"
packaged_binary="$packaged_app/Contents/MacOS/photokit-helper"
packaged_launcher="$output_directory/photokit-helper"

if [ ! -x "$source_binary" ]; then
    printf '%s\n' "photokit-helper: release build did not produce the signed helper app" >&2
    exit 70
fi

rm -rf "$output_directory"
mkdir -p "$output_directory"
ditto "$source_app" "$packaged_app"
cp "$native_directory/scripts/packaged-run.sh" "$packaged_launcher"
chmod 755 "$packaged_launcher"

architectures=$(lipo -archs "$packaged_binary")
if [ "$architectures" != "arm64" ]; then
    printf '%s\n' "photokit-helper: expected an arm64 package, built: $architectures" >&2
    exit 70
fi

codesign --verify --strict "$packaged_app"
printf '%s\n' "$packaged_launcher"
