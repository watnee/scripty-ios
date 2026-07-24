#!/bin/bash
#
# The shared body of the double-click launchers at the repo root (Install
# Scripty.command and its siblings). Finder opens those in a Terminal window and
# they hand straight here: the first argument is a short label for the closing
# line, the rest is the command to run. This exists so those four files don't
# each repeat the one thing a double-clicked window needs — holding itself open
# on exit so the output is still readable, and saying whether the run worked.
#
#   scripts/finder-run.sh "Setup" ./scripts/get.sh -- --simulator
#
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

LABEL="${1:-This}"
shift || true

# Run it without -e so a failure still reaches the summary below rather than
# killing the window on the spot.
"$@"
STATUS=$?

echo
if [ "$STATUS" -eq 0 ]; then
    echo "$LABEL finished. You can close this window."
else
    echo "$LABEL stopped before it finished — the lines above say why."
fi
read -r -p "Press Return to close this window." _ || true
exit "$STATUS"
