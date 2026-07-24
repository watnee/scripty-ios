#!/bin/bash
#
# Double-click this in Finder to install and run Scripty — no terminal, no
# commands to type. Finder opens it in a Terminal window, and everything from
# there is the same setup scripts/get.sh does: it checks Xcode, updates this
# checkout, and launches the app, asking before anything that needs a password.
#
# It lives next to the project so it works whether you cloned the repository or
# downloaded it as a ZIP from GitHub. If macOS says it is from an unidentified
# developer the first time, right-click it and choose Open — that button runs it
# once and remembers your answer.
#
set -euo pipefail

# A double-clicked .command starts wherever Finder was, not here. Everything
# below assumes this file sits at the top of the checkout, so move there.
cd "$(dirname "$0")"

if [ ! -x scripts/get.sh ]; then
    echo "This file has to stay next to Scripty's scripts folder to work." >&2
    echo "It looks like it was moved out of the project." >&2
    read -r -p "Press Return to close this window." _ || true
    exit 1
fi

# Hand off to the same script the one-line install uses. It does the talking
# from here.
set +e
./scripts/get.sh
STATUS=$?
set -e

# A double-clicked window can close the moment this exits, taking any error
# message with it. Hold it open so whatever get.sh said is still readable, and
# say plainly whether it worked.
echo
if [ "$STATUS" -eq 0 ]; then
    echo "Done. You can close this window."
else
    echo "Setup stopped before it finished — the lines above say why."
fi
read -r -p "Press Return to close this window." _ || true
exit "$STATUS"
