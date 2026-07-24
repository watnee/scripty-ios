#!/bin/bash
#
# Remove Scripty again — the reverse of install.sh (a real iPhone or iPad) and
# demo.sh (a simulator). Without a build to ask, it removes both names the other
# scripts might have used: the default scripty.scripty, and, if install.sh had
# to pick one, the com.<team>.scripty it wrote into .scripty-install. Whatever
# the app was keeping goes with it, so this only asks before nothing.
#
#   ./scripts/uninstall.sh                    # a connected device, else a booted simulator
#   ./scripts/uninstall.sh --simulator        # a booted simulator, even with a device plugged in
#   ./scripts/uninstall.sh --device "iPhone"  # a device by name
#   ./scripts/uninstall.sh --bundle-id ID     # remove one specific id instead
#
set -euo pipefail
cd "$(dirname "$0")/.."

CONF=".scripty-install"
WANT=""          # "", "simulator", or "device"
DEVICE_NAME=""
BUNDLE_OVERRIDE="${SCRIPTY_BUNDLE_ID:-}"

usage() {
    sed -n '3,14p' "$0" | cut -c3-
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --simulator|--sim) WANT=simulator; shift ;;
        --device)
            WANT=device
            case "${2:-}" in
                ""|-*) shift ;;
                *) DEVICE_NAME="$2"; shift 2 ;;
            esac ;;
        --bundle-id) BUNDLE_OVERRIDE="${2:-}"; [ -n "$BUNDLE_OVERRIDE" ] || usage 1; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1" >&2; usage 1 ;;
    esac
done

if ! xcrun -f simctl >/dev/null 2>&1; then
    echo "xcrun not found — nothing here can reach a device or simulator." >&2
    echo "Install Xcode, then:  sudo xcode-select --switch /Applications/Xcode.app" >&2
    exit 1
fi

# Which ids to remove. A specific --bundle-id wins; otherwise both names the
# other scripts use — whatever install.sh remembered, then the default that
# demo.sh and a first install.sh both fall back to.
BUNDLE_IDS=()
if [ -n "$BUNDLE_OVERRIDE" ]; then
    BUNDLE_IDS=("$BUNDLE_OVERRIDE")
else
    REMEMBERED=$([ -f "$CONF" ] && sed -n 's/^BUNDLE_ID=//p' "$CONF" | tail -1 || true)
    [ -n "$REMEMBERED" ] && [ "$REMEMBERED" != "scripty.scripty" ] && BUNDLE_IDS+=("$REMEMBERED")
    BUNDLE_IDS+=("scripty.scripty")
fi

REMOVED=0

# --- A real device, via devicectl -------------------------------------------
DEVICES_JSON=$(mktemp -t scripty-uninstall)
trap 'rm -f "$DEVICES_JSON"' EXIT

device_line() {
    xcrun devicectl list devices --json-output "$DEVICES_JSON" >/dev/null 2>&1 || true
    SCRIPTY_DEVICE="$DEVICE_NAME" /usr/bin/python3 -c '
import json, os, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
wanted = os.environ.get("SCRIPTY_DEVICE", "")
def name(d): return d["deviceProperties"]["name"]
live = [d for d in devices
        if d["hardwareProperties"]["platform"] in ("iOS", "iPadOS")
        and d["connectionProperties"]["pairingState"] == "paired"
        and d["connectionProperties"]["tunnelState"] != "unavailable"]
if wanted:
    live = [d for d in live
            if wanted in (name(d), d["identifier"], d["hardwareProperties"]["udid"])]
if not live:
    sys.exit(1)
d = live[0]
print(d["identifier"], name(d), sep="\t")
' "$DEVICES_JSON"
}

remove_from_device() {
    local id="$1" label="$2" bundle
    for bundle in "${BUNDLE_IDS[@]}"; do
        if xcrun devicectl device uninstall app --device "$id" "$bundle" >/dev/null 2>&1; then
            echo "Removed $bundle from $label."
            REMOVED=$((REMOVED + 1))
        fi
    done
}

if [ "$WANT" != simulator ]; then
    if DEV=$(device_line); then
        IFS=$'\t' read -r DEV_ID DEV_NAME <<<"$DEV"
        remove_from_device "$DEV_ID" "$DEV_NAME"
        [ "$REMOVED" -eq 0 ] && echo "Scripty wasn't installed on $DEV_NAME."
        exit 0
    fi
    if [ "$WANT" = device ]; then
        if [ -n "$DEVICE_NAME" ]; then
            echo "No connected device named '$DEVICE_NAME'." >&2
        else
            echo "No iPhone or iPad is connected. Plug one in and unlock it, or pass" >&2
            echo "--simulator to remove it from a booted simulator instead." >&2
        fi
        exit 1
    fi
    echo "No device connected — looking at booted simulators instead."
fi

# --- A booted simulator, via simctl -----------------------------------------
BOOTED=$(xcrun simctl list -j devices | /usr/bin/python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
for runtime in data:
    for d in data[runtime]:
        if d.get("state") == "Booted":
            print(d["udid"], d["name"], sep="\t")
')

if [ -z "$BOOTED" ]; then
    echo "No simulator is booted, so there is nothing to remove there." >&2
    echo "Open one from Xcode, or run ./scripts/demo.sh to boot one." >&2
    exit 1
fi

while IFS=$'\t' read -r SIM_ID SIM_NAME; do
    [ -n "$SIM_ID" ] || continue
    for bundle in "${BUNDLE_IDS[@]}"; do
        if xcrun simctl get_app_container "$SIM_ID" "$bundle" >/dev/null 2>&1; then
            xcrun simctl uninstall "$SIM_ID" "$bundle"
            echo "Removed $bundle from the $SIM_NAME simulator."
            REMOVED=$((REMOVED + 1))
        fi
    done
done <<<"$BOOTED"

[ "$REMOVED" -eq 0 ] && echo "Scripty wasn't installed on any booted simulator."
exit 0
