#!/bin/sh
# Current-user, loopback-only Image Capture integration. Never submits a scan.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
label=local.bjc85.native-scan
domain="gui/$(id -u)"
bundle="$project_dir/build/BJC-85 Scanner.app"
executable="$bundle/Contents/Helpers/is12-escl-bridge"
driver="$bundle/Contents/Helpers/bjc85-is12"
runtime_dir="$project_dir/.state"
prepared="$runtime_dir/$label.plist"
installed="$HOME/Library/LaunchAgents/$label.plist"
mode=${1:---prepare-only}
case "$mode" in --prepare-only|--scanner-installed|--stop) ;; *) echo "Usage: $0 --prepare-only|--scanner-installed|--stop" >&2; exit 2 ;; esac
[ "$#" -le 1 ] || exit 2
if [ "$mode" = --stop ]; then
    /bin/launchctl disable "$domain/$label"
    if /bin/launchctl print "$domain/$label" >/dev/null 2>&1; then /bin/launchctl bootout "$domain/$label"; fi
    exit 0
fi
[ -x "$executable" ] && [ -x "$driver" ] || { echo 'Build the scanner app first.' >&2; exit 1; }
/usr/bin/codesign --verify --deep --strict "$bundle"
[ "$(/usr/bin/lipo -archs "$executable")" = arm64 ] || exit 1
umask 077
mkdir -p "$runtime_dir/logs"
/usr/bin/plutil -create xml1 "$prepared"
/usr/bin/plutil -insert Label -string "$label" "$prepared"
/usr/bin/plutil -insert ProgramArguments -array "$prepared"
/usr/bin/plutil -insert ProgramArguments.0 -string "$executable" "$prepared"
/usr/bin/plutil -insert ProgramArguments.1 -string --scanner-installed "$prepared"
/usr/bin/plutil -insert ProgramArguments.2 -string "$driver" "$prepared"
/usr/bin/plutil -insert ProgramArguments.3 -string "$runtime_dir/is12-calibration-002/reference.bin" "$prepared"
/usr/bin/plutil -insert WorkingDirectory -string "$project_dir" "$prepared"
/usr/bin/plutil -insert RunAtLoad -bool YES "$prepared"
# A crash requires inspection; launchd must not replay or restart a scan.
/usr/bin/plutil -insert KeepAlive -bool NO "$prepared"
/usr/bin/plutil -insert ProcessType -string Background "$prepared"
/usr/bin/plutil -insert StandardOutPath -string "$runtime_dir/logs/scan-service.jsonl" "$prepared"
/usr/bin/plutil -insert StandardErrorPath -string "$runtime_dir/logs/scan-service.stderr.txt" "$prepared"
/usr/bin/plutil -lint "$prepared"
if [ "$mode" = --prepare-only ]; then echo "Prepared: $prepared"; exit 0; fi
if [ -e "$installed" ]; then
    existing=$(/usr/bin/plutil -extract ProgramArguments.0 raw "$installed")
    [ "$existing" = "$executable" ] || { echo "An unrelated service uses $label." >&2; exit 1; }
fi
if /usr/bin/lpstat -v BJC85_Native >/dev/null 2>&1; then
    queue_uri=$(/usr/bin/lpstat -v BJC85_Native)
    case "$queue_uri" in *ipp://localhost:8631/ipp/print) ;; *) echo 'Unexpected BJC85_Native queue URI.' >&2; exit 1 ;; esac
    pending=$(/usr/bin/lpstat -W not-completed -o BJC85_Native)
    [ -z "$pending" ] || { echo 'Finish or cancel pending print jobs first.' >&2; exit 1; }
    /usr/sbin/cupsdisable -r 'IS-12 scanner installed; restore BC-11e before printing.' BJC85_Native
fi
/bin/launchctl disable "$domain/local.bjc85.native-print"
if /bin/launchctl print "$domain/local.bjc85.native-print" >/dev/null 2>&1; then /bin/launchctl bootout "$domain/local.bjc85.native-print"; fi
if /bin/launchctl print "$domain/$label" >/dev/null 2>&1; then
    echo 'Scanner service is already loaded.'
    exit 0
fi
if /usr/bin/curl --fail --silent --max-time 1 http://127.0.0.1:8641/eSCL/ScannerCapabilities >/dev/null; then
    echo 'Port 8641 is occupied by a scanner outside this login service; stop that process first.' >&2
    exit 1
fi
mkdir -p "$HOME/Library/LaunchAgents"
/usr/bin/install -m 600 "$prepared" "$installed"
/bin/launchctl enable "$domain/$label"
/bin/launchctl bootstrap "$domain" "$installed"
attempt=0
until /usr/bin/curl --fail --silent --max-time 1 http://127.0.0.1:8641/eSCL/ScannerCapabilities >/dev/null; do
    attempt=$((attempt + 1))
    [ "$attempt" -lt 10 ] || { echo "Scanner service did not start; inspect $runtime_dir/logs/scan-service.stderr.txt" >&2; exit 1; }
    sleep 1
done
echo 'Canon BJC-85 IS-12 Native is available to Image Capture on this Mac.'
