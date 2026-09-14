#!/bin/sh
# Operator must have replaced the IS-12; do not infer cartridge type from USB.
set -eu
[ "$#" -eq 1 ] && [ "$1" = --bc11e-installed ] || { echo "Usage: $0 --bc11e-installed" >&2; exit 2; }
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
domain="gui/$(id -u)"
print_plist="$HOME/Library/LaunchAgents/local.bjc85.native-print.plist"
[ -f "$print_plist" ] || { echo 'Install the native print service first.' >&2; exit 1; }
printer=$(/usr/bin/plutil -extract ProgramArguments.0 raw "$print_plist")
[ "$printer" = "$project_dir/build/bjc85-ipp" ] || { echo 'The print service does not belong to this project.' >&2; exit 1; }
if /bin/launchctl print "$domain/local.bjc85.native-scan" >/dev/null 2>&1; then
    status=$(/usr/bin/curl --fail --silent --max-time 3 http://127.0.0.1:8641/eSCL/ScannerStatus)
    case "$status" in *'<pwg:State>Idle</pwg:State>'*) ;; *) echo 'Finish or cancel the active scan first.' >&2; exit 1 ;; esac
fi
/bin/sh "$project_dir/scripts/install-scanner-service.sh" --stop
/bin/launchctl enable "$domain/local.bjc85.native-print"
if ! /bin/launchctl print "$domain/local.bjc85.native-print" >/dev/null 2>&1; then
    /bin/launchctl bootstrap "$domain" "$print_plist"
fi
/usr/sbin/cupsenable BJC85_Native
echo 'Canon BJC-85 Native printing enabled.'
