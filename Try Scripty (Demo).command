#!/bin/bash
#
# Double-click this in Finder to open Scripty's offline demo in a simulator — a
# sample screenplay, no account, no device, nothing to sign. It checks Xcode the
# same way the installer does, then boots a simulator and lands in the demo.
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
exec scripts/finder-run.sh "The demo" ./scripts/get.sh -- --simulator
