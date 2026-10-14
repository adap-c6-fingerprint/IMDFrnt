#!/bin/bash
# Run the app's CLI checks without launching SwiftUI/NSApplication.
set -uo pipefail

if [[ $# -lt 1 || ! -x "$1/Contents/MacOS/IM-DFrnt" ]]; then
  echo "Usage: $0 /path/to/IM-DFrnt.app [--imdf-test-input /path/to/IMDFData] [--imdf-test-zip /path/to/IMDF.zip] [--legacy-test-input /path/to/project.imdfrnt]" >&2
  exit 2
fi

app_binary="$1/Contents/MacOS/IM-DFrnt"
shift
log_directory="$(mktemp -d "${TMPDIR:-/tmp}/imdfrnt-self-tests.XXXXXX")" || exit 2
echo "Logs: $log_directory"
{
  sw_vers
  uname -m
  shasum -a 256 "$app_binary"
} > "$log_directory/environment.txt"

failures=0
for mode in selftest building-selftest project-selftest document-open-selftest routing-selftest drawing-loading-selftest; do
  log_file="$log_directory/$mode.log"
  "$app_binary" "--$mode" "$@" > "$log_file" 2>&1
  status=$?
  echo "$mode: exit $status"
  tail -n 1 "$log_file"
  if [[ $status -ne 0 ]] || ! awk '
    /== CLI self-test: before AppKit application startup ==/ { entry = 1 }
    /^== .*PASS ==$/ { summary = 1 }
    /^\[FAIL\]/ { failed = 1 }
    END { exit !(entry && summary && !failed) }
  ' "$log_file"; then
    failures=$((failures + 1))
    tail -n 12 "$log_file" >&2
  fi
done

echo "Result: $((6 - failures))/6 modes passed; logs: $log_directory"
[[ $failures -eq 0 ]]
