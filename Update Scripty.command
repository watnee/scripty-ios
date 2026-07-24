#!/bin/bash
#
# Double-click this in Finder to update Scripty and relaunch it — it fetches the
# latest version into this checkout, then runs the app the way the installer
# does. (Run from inside a clone, the installer deliberately leaves your copy
# untouched, so the update happens here.)
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

# A ZIP download is not a git checkout, so this can fail with nothing to pull —
# say so and carry on to relaunch what is already here.
if [ -d .git ]; then
    echo "Fetching the latest Scripty…"
    git pull --ff-only || echo "Couldn't fast-forward — relaunching the version already here."
else
    echo "This copy wasn't cloned with git, so there's nothing to update — relaunching it."
fi

exec scripts/finder-run.sh "The update" ./scripts/get.sh
