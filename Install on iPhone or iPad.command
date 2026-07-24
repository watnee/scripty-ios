#!/bin/bash
#
# Double-click this in Finder to put Scripty on an iPhone or iPad plugged into
# this Mac — no terminal, no commands to type. It checks Xcode the way the other
# launchers do, then waits for the device, builds a signed copy, installs it,
# and opens it. A free Apple ID is enough to sign; if Developer Mode is off or
# the device hasn't trusted the certificate yet, it says exactly what to tap and
# waits while you do it, rather than failing in the build log.
#
# Unlike Install Scripty.command, which opens the offline demo in a simulator
# when nothing is plugged in, this one insists on a real device and waits for
# one to appear. Plug the device in over USB and unlock it before, or just after,
# you double-click.
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
exec scripts/finder-run.sh "The install" ./scripts/get.sh -- --device
