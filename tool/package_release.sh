#!/bin/sh
#
# Build and package media_info release artifacts locally, without CI.
#
# Produces exactly the same package shapes as .github/workflows/build.yml:
#   Windows : dist/media_info-v<version>-windows-x64.zip
#             (the whole build/windows/x64/runner/Release directory)
#   macOS   : dist/media_info-v<version>-macos-universal.tar.gz
#             (the build/macos/Build/Products/Release/<name>.app bundle)
#
# This is the POSIX counterpart of tool/package_release.ps1. On Windows it is
# meant to be run from a POSIX-ish shell (Git Bash / MSYS). WSL is NOT
# supported: the Flutter SDK is a Windows binary.
#
# Usage:
#   tool/package_release.sh [windows|macos] [--skip-build] [--version X.Y.Z]
#
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)

usage() {
    sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
}

platform=""
skip_build=0
version=""

while [ $# -gt 0 ]; do
    case "$1" in
        windows | macos)
            platform="$1"
            ;;
        --skip-build)
            skip_build=1
            ;;
        --version)
            [ $# -ge 2 ] || { echo "--version needs an argument" >&2; exit 2; }
            version="$2"
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "unknown argument: $1" >&2
            exit 2
            ;;
    esac
    shift
done

# Detect the host platform when the caller did not name one.
if [ -z "$platform" ]; then
    case "$(uname -s)" in
        Darwin) platform=macos ;;
        Linux | MINGW* | MSYS* | CYGWIN*) platform=windows ;;
        *)
            echo "cannot detect platform from '$(uname -s)'; pass windows or macos" >&2
            exit 2
            ;;
    esac
fi

# Version: explicit flag wins, otherwise the version from pubspec.yaml.
if [ -z "$version" ]; then
    version=$(sed -n 's/^version:[[:space:]]*\([0-9][^ +]*\).*/\1/p' "$repo_root/pubspec.yaml" | head -1)
    if [ -z "$version" ]; then
        echo "could not read version from pubspec.yaml" >&2
        exit 1
    fi
fi

out_dir="$repo_root/dist"
mkdir -p "$out_dir"

echo "==> media_info v$version ($platform)"

if [ "$skip_build" -eq 0 ]; then
    echo "==> flutter build $platform --release"
    (cd "$repo_root" && flutter build "$platform" --release)
fi

case "$platform" in
    windows)
        src="$repo_root/build/windows/x64/runner/Release"
        if [ ! -f "$src/media_info.exe" ]; then
            echo "media_info.exe not found in $src" >&2
            exit 1
        fi
        archive="$out_dir/media_info-v$version-windows-x64.zip"
        echo "==> zipping $src -> $archive"
        if command -v zip >/dev/null 2>&1; then
            (cd "$src" && zip -q -r -X "$archive" .)
        elif command -v powershell.exe >/dev/null 2>&1; then
            # No `zip` on this box: fall back to the Windows-native compressor.
            # MSYS-style paths must be translated before PowerShell sees them.
            win_src=$(cygpath -w "$src" 2>/dev/null || echo "$src")
            win_archive=$(cygpath -w "$archive" 2>/dev/null || echo "$archive")
            powershell.exe -NoProfile -Command \
                "Compress-Archive -Path '$win_src/*' -DestinationPath '$win_archive' -Force" >/dev/null
        else
            echo "neither zip nor powershell.exe is available to build the zip" >&2
            exit 1
        fi
        ;;
    macos)
        products="$repo_root/build/macos/Build/Products/Release"
        app=$(find "$products" -maxdepth 1 -name '*.app' | head -1)
        if [ -z "$app" ]; then
            echo "no .app bundle found under $products" >&2
            exit 1
        fi
        archive="$out_dir/media_info-v$version-macos-universal.tar.gz"
        echo "==> tarring $app -> $archive"
        tar -czf "$archive" -C "$(dirname "$app")" "$(basename "$app")"
        ;;
esac

echo
echo "==> artifacts"
for f in "$out_dir"/media_info-v"$version"-*; do
    [ -e "$f" ] || continue
    size=$(wc -c <"$f" | tr -d ' ')
    echo "    $(basename "$f")  ($size bytes)"
done
echo
echo "Done. Artifacts are in $out_dir"
