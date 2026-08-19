#!/bin/sh

set -u

package_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
binary_directory=$(swift build --package-path "$package_directory" --show-bin-path)
app_path="$binary_directory/PhotoKit Node Helper.app"

if [ "${1:-}" = "--" ]; then
    shift
fi

if [ ! -d "$app_path" ]; then
    printf '%s\n' "photokit-helper: run pnpm run native:build first" >&2
    exit 66
fi

output_directory=$(mktemp -d "${TMPDIR:-/tmp}/photokit-helper.XXXXXX")
stdout_path="$output_directory/stdout"
stderr_path="$output_directory/stderr"
launcher_stderr_path="$output_directory/launcher-stderr"

cleanup()
{
    rm -rf "$output_directory"
}
trap cleanup EXIT HUP INT TERM

open -W -n "$app_path" --stdout "$stdout_path" --stderr "$stderr_path" --args "$@" \
    2> "$launcher_stderr_path" || true

if [ -s "$stderr_path" ]; then
    cat "$stderr_path" >&2
fi

if [ ! -s "$stdout_path" ]; then
    if [ -s "$launcher_stderr_path" ]; then
        cat "$launcher_stderr_path" >&2
    fi
    printf '%s\n' "photokit-helper: application exited without a response" >&2
    exit 70
fi

cat "$stdout_path"
