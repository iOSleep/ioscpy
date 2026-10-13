#!/bin/bash
#
# Builds ioscpy.app: a double-clickable wrapper around the CLI that asks whether
# to mirror only or to mirror and record.
#
#   ./packaging/macos-app/build-app.sh                 # into ~/Applications
#   ./packaging/macos-app/build-app.sh /Applications    # straight into place
#
# The CLI has to be on PATH when the app runs (brew install ioscpy, or
# cargo install --path host); this script only assembles the bundle.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
out_dir="${1:-$HOME/Applications}"
app="$out_dir/ioscpy.app"
icon_src="$repo/host/assets/ioscpyIcon.png"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

install -m 755 "$here/launcher.sh" "$app/Contents/MacOS/ioscpy-launcher"
install -m 644 "$here/Info.plist" "$app/Contents/Info.plist"

# Icon: an .iconset of the sizes Finder asks for, then iconutil. The bundled PNG
# has no color profile and iconutil refuses to convert it as-is ("Failed to
# generate ICNS"), so tag each resize with sRGB on the way through.
if [ -f "$icon_src" ] && command -v iconutil >/dev/null 2>&1; then
    iconset="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$iconset"
    profile="/System/Library/ColorSync/Profiles/sRGB Profile.icc"
    for spec in "16 icon_16x16.png" "32 icon_32x32.png" "64 icon_32x32@2x.png" \
                "128 icon_128x128.png" "256 icon_256x256.png" \
                "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do
        size="${spec%% *}"
        name="${spec#* }"
        if [ -f "$profile" ]; then
            sips -z "$size" "$size" -m "$profile" "$icon_src" --out "$iconset/$name" >/dev/null
        else
            sips -z "$size" "$size" "$icon_src" --out "$iconset/$name" >/dev/null
        fi
    done
    if ! iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns" 2>/dev/null; then
        echo "warning: could not build AppIcon.icns; the app gets the generic icon" >&2
    fi
fi

echo "built $app"
echo "recording path: \$HOME/Movies/ioscpy-<timestamp>.mp4 (needs the --record flag)"
