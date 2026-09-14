#!/bin/sh
set -eu
[ "$#" -eq 1 ] || { echo 'Usage: notarize.sh SIGNED-PKG-OR-APP' >&2; exit 2; }
[ -n "${BJC85_NOTARY_PROFILE:-}" ] || { echo 'Set BJC85_NOTARY_PROFILE to an existing notarytool keychain profile.' >&2; exit 1; }
artifact=$1
case "$artifact" in
    *.app)
        /usr/bin/codesign -dv "$artifact" 2>&1 | /usr/bin/grep -q 'Authority=Developer ID Application' || { echo 'Developer ID Application signing is required.' >&2; exit 1; }
        upload="$artifact.notarization.zip"
        /usr/bin/ditto -c -k --keepParent "$artifact" "$upload"
        ;;
    *.pkg)
        /usr/sbin/pkgutil --check-signature "$artifact" | /usr/bin/grep -q 'Developer ID Installer:' || { echo 'Developer ID Installer signing is required.' >&2; exit 1; }
        upload="$artifact"
        ;;
    *) echo 'Expected a signed .app or .pkg.' >&2; exit 2 ;;
esac
/usr/bin/xcrun notarytool submit "$upload" --keychain-profile "$BJC85_NOTARY_PROFILE" --wait
/usr/bin/xcrun stapler staple "$artifact"
/usr/bin/xcrun stapler validate "$artifact"
