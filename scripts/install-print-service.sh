#!/bin/sh
# Install the local development build for the current user's login session.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
label=local.bjc85.native-print
queue=BJC85_Native
domain="gui/$(id -u)"
executable="$project_dir/build/bjc85-ipp"
runtime_dir="$project_dir/.state"
prepared="$runtime_dir/$label.plist"
installed="$HOME/Library/LaunchAgents/$label.plist"
mode=${1:-install}
case "$mode" in install|--prepare-only) ;; *) echo "Usage: $0 [--prepare-only]" >&2; exit 2 ;; esac
[ "$#" -le 1 ] || exit 2
[ -x "$executable" ] || { echo "Build bjc85-ipp first." >&2; exit 1; }
[ "$(/usr/bin/lipo -archs "$executable")" = arm64 ] || { echo "Expected an ARM64-only service." >&2; exit 1; }
umask 077
mkdir -p "$runtime_dir/print-spool" "$runtime_dir/logs"
/usr/bin/plutil -create xml1 "$prepared"
/usr/bin/plutil -insert Label -string "$label" "$prepared"
/usr/bin/plutil -insert ProgramArguments -array "$prepared"
/usr/bin/plutil -insert ProgramArguments.0 -string "$executable" "$prepared"
/usr/bin/plutil -insert ProgramArguments.1 -string --print-cartridge=bc11e "$prepared"
/usr/bin/plutil -insert ProgramArguments.2 -string --spool-dir "$prepared"
/usr/bin/plutil -insert ProgramArguments.3 -string "$runtime_dir/print-spool" "$prepared"
/usr/bin/plutil -insert ProgramArguments.4 -string --port "$prepared"
/usr/bin/plutil -insert ProgramArguments.5 -string 8631 "$prepared"
/usr/bin/plutil -insert WorkingDirectory -string "$project_dir" "$prepared"
/usr/bin/plutil -insert RunAtLoad -bool YES "$prepared"
/usr/bin/plutil -insert KeepAlive -bool YES "$prepared"
/usr/bin/plutil -insert ThrottleInterval -integer 10 "$prepared"
/usr/bin/plutil -insert ProcessType -string Background "$prepared"
/usr/bin/plutil -insert StandardOutPath -string "$runtime_dir/logs/print-service.log" "$prepared"
/usr/bin/plutil -insert StandardErrorPath -string "$runtime_dir/logs/print-service.log" "$prepared"
/usr/bin/plutil -lint "$prepared"
if [ "$mode" = --prepare-only ]; then
  echo "Prepared: $prepared"
  exit 0
fi
if [ -e "$installed" ]; then
  existing=$(/usr/bin/plutil -extract ProgramArguments.0 raw "$installed")
  [ "$existing" = "$executable" ] || { echo "An unrelated service uses $label; leaving it alone." >&2; exit 1; }
fi
if /usr/bin/lpstat -v "$queue" >/dev/null 2>&1; then
  /usr/bin/lpstat -v "$queue" | /usr/bin/grep -F "ipp://localhost:8631/ipp/print" >/dev/null || {
    echo "An unrelated queue uses $queue; leaving it alone." >&2; exit 1;
  }
  pending=$(/usr/bin/lpstat -W not-completed -o "$queue")
  [ -z "$pending" ] || { echo "Finish or cancel queued jobs before restarting the service." >&2; exit 1; }
fi
if /bin/launchctl print "$domain/$label" >/dev/null 2>&1; then
  /bin/launchctl bootout "$domain/$label"
fi
mkdir -p "$HOME/Library/LaunchAgents"
/usr/bin/install -m 600 "$prepared" "$installed"
/bin/launchctl bootstrap "$domain" "$installed"
attempt=0
until /usr/bin/curl --fail --silent --max-time 1 http://127.0.0.1:8631/ >/dev/null; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 10 ] || { echo "Service did not start; inspect $runtime_dir/logs/print-service.log" >&2; exit 1; }
  sleep 1
done
/usr/sbin/lpadmin -p "$queue" -E -v ipp://localhost:8631/ipp/print -m everywhere \
  -D 'Canon BJC-85 Native' -o printer-is-shared=false -o printer-error-policy=stop-printer
echo "Installed Canon BJC-85 Native for this user's login session. Default printer unchanged."
