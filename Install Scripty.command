#!/bin/bash
#
# Double-click this in Finder to install and run Scripty — no terminal, no
# commands to type. Finder opens it in a Terminal window, and from there it is
# the same setup scripts/get.sh does: it checks Xcode, updates this checkout,
# and launches the app, asking before anything that needs a password.
#
# It lives next to the project so it works whether you cloned the repository or
# downloaded it as a ZIP from GitHub. If macOS says it is from an unidentified
# developer the first time, right-click it and choose Open — that button runs it
# once and remembers your answer.
#
cd "$(dirname "$0")"
if [ ! -x scripts/finder-run.sh ]; then
    echo "This file has to stay next to Scripty's scripts folder to work." >&2
    echo "It looks like it was moved out of the project." >&2
    read -r -p "Press Return to close this window." _ || true
    exit 1
fi
exec scripts/finder-run.sh "Setup" ./scripts/get.sh
