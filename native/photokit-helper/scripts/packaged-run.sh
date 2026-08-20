#!/bin/sh

set -u

launcher_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
app_path="$launcher_directory/PhotoKit Node Helper.app"
binary_path="$app_path/Contents/MacOS/photokit-helper"

if [ "$(uname -s)" != "Darwin" ]; then
    printf '%s\n' "photokit-helper: this package supports macOS only" >&2
    exit 69
fi

if [ ! -x "$binary_path" ]; then
    printf '%s\n' "photokit-helper: packaged app bundle is missing its executable" >&2
    exit 66
fi

host_architecture=$(uname -m)
packaged_architectures=$(lipo -archs "$binary_path" 2>/dev/null || true)
case " $packaged_architectures " in
    *" $host_architecture "*) ;;
    *)
        printf '%s\n' "photokit-helper: packaged architectures ($packaged_architectures) do not support this Mac ($host_architecture)" >&2
        exit 69
        ;;
esac

if [ "${1:-}" = "--" ]; then
    shift
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
