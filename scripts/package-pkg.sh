#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_dir="$project_dir/dist/BJC-85 Utility.app"
[ -d "$app_dir" ] || { echo 'Build the release app first.' >&2; exit 1; }
python3 "$project_dir/scripts/audit-release.py" "$app_dir"
if [ -n "${BJC85_INSTALLER_IDENTITY:-}" ]; then
    /usr/bin/codesign -dv "$app_dir" 2>&1 | /usr/bin/grep -q 'Authority=Developer ID Application:' || { echo 'Build the app with Developer ID Application before signing the installer.' >&2; exit 1; }
    /usr/bin/productbuild --sign "$BJC85_INSTALLER_IDENTITY" --component "$app_dir" /Applications "$project_dir/dist/BJC85-Utility.pkg"
else
    /usr/bin/productbuild --component "$app_dir" /Applications "$project_dir/dist/BJC85-Utility-unsigned.pkg"
fi
