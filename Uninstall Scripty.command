#!/bin/bash
#
# Double-click this in Finder to remove Scripty from a connected iPhone or iPad,
# or from a booted simulator if none is plugged in. It takes whatever the app
# was keeping with it; reinstalling is the only way back.
#
# It lives next to the project so it works whether you cloned the repository or
# downloaded it as a ZIP from GitHub. If macOS says it is from an unidentified
# developer the first time, right-click it and choose Open.
#
cd "$(dirname "$0")"
if [ ! -x scripts/finder-run.sh ]; then
    echo "This file has to stay next to Scripty's scripts folder to work." >&2
    echo "It looks like it was moved out of the project." >&2
    read -r -p "Press Return to close this window." _ || true
    exit 1
fi
exec scripts/finder-run.sh "The uninstall" ./scripts/uninstall.sh
