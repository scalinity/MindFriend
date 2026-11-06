#!/bin/sh
# Release symbols must match the distributed binary. Source files are not uploaded.
set -eu

[ "${CONFIGURATION:-}" = "Release" ] || exit 0

if ! command -v sentry-cli >/dev/null 2>&1; then
  echo "warning: Sentry symbols were not uploaded: sentry-cli is unavailable. Verify symbol upload before distribution."
  exit 0
fi

symbols_dir=${DWARF_DSYM_FOLDER_PATH:-${CONFIGURATION_BUILD_DIR:-}}
if [ -z "$symbols_dir" ] || [ ! -d "$symbols_dir" ]; then
  echo "error: Sentry symbol directory is unavailable."
  exit 1
fi

# A direct invocation propagates upload and server-processing errors to Xcode.
# Sentry CLI 3 uses --wait-for; the old --force-foreground flag is unsupported.
export SENTRY_ORG=scalinity
export SENTRY_PROJECT=mindfriend
sentry-cli debug-files upload --type dsym --no-sources --wait-for 60 "$symbols_dir"
echo "Sentry debug-symbol upload completed."
