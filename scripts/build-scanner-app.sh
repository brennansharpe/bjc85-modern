#!/bin/sh
# The relocatable Utility supersedes the checkout-bound development app.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
exec /bin/sh "$project_dir/scripts/build-release.sh"
