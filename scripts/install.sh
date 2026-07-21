#!/bin/bash
#
# Build Scripty and install it on a real iPhone or iPad plugged into this Mac.
# Unlike scripts/demo.sh (simulator, no signing), this needs a signing team —
# any free Apple ID team will do.
#
#   ./scripts/install.sh                             # the connected device
#   ./scripts/install.sh --device "Clint iPhone"     # pick a device by name
#   ./scripts/install.sh --list                      # show paired devices
#   ./scripts/install.sh --team ABCDE12345           # signing team, else auto
#   ./scripts/install.sh --bundle-id com.you.scripty # if the default is taken
#   ./scripts/install.sh --demo                      # start in the offline demo
#   ./scripts/install.sh --no-launch                 # install without launching
#
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="scripty.xcodeproj"
SCHEME="scripty"
DEVICE="${SCRIPTY_DEVICE:-}"
TEAM="${SCRIPTY_TEAM_ID:-}"
BUNDLE_OVERRIDE="${SCRIPTY_BUNDLE_ID:-}"
LAUNCH=1
DEMO=0

usage() {
    sed -n '3,13p' "$0" | cut -c3-
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --device) DEVICE="${2:-}"; [ -n "$DEVICE" ] || usage 1; shift 2 ;;
        --team) TEAM="${2:-}"; [ -n "$TEAM" ] || usage 1; shift 2 ;;
        --bundle-id) BUNDLE_OVERRIDE="${2:-}"; [ -n "$BUNDLE_OVERRIDE" ] || usage 1; shift 2 ;;
        --demo) DEMO=1; shift ;;
        --no-launch) LAUNCH=0; shift ;;
        --list) exec xcrun devicectl list devices ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1" >&2; usage 1 ;;
    esac
done

if ! xcrun -f xcodebuild >/dev/null 2>&1; then
    echo "xcodebuild not found. Install Xcode, then point the tools at it:" >&2
    echo "  sudo xcode-select --switch /Applications/Xcode.app" >&2
    exit 1
fi

# Pick a device. devicectl mixes a human table into --json-output when that is
# a pipe, so write the JSON to a real file and read it back.
DEVICES_JSON=$(mktemp -t scripty-devices)
trap 'rm -f "$DEVICES_JSON"' EXIT
xcrun devicectl list devices --json-output "$DEVICES_JSON" >/dev/null

TARGET=$(SCRIPTY_DEVICE="$DEVICE" /usr/bin/python3 -c '
import json, os, sys

devices = json.load(open(sys.argv[1]))["result"]["devices"]
wanted = os.environ.get("SCRIPTY_DEVICE", "")

def name(device):
    return device["deviceProperties"]["name"]

devices = [d for d in devices
           if d["hardwareProperties"]["platform"] in ("iOS", "iPadOS")
           and d["connectionProperties"]["pairingState"] == "paired"]
if wanted:
    devices = [d for d in devices
               if wanted in (name(d), d["identifier"], d["hardwareProperties"]["udid"])]
    if not devices:
        sys.exit(f"No paired device named {wanted!r}. "
                 "List them with: ./scripts/install.sh --list")
if not devices:
    sys.exit("No iPhone or iPad is paired with this Mac. Plug one in over USB, "
             "unlock it, and tap Trust.")

# A paired device that is not currently reachable would fail deep inside
# xcodebuild with an unhelpful message, so say so plainly up front — but keep
# going, since tunnelState lags behind reality right after a device is plugged in.
live = [d for d in devices if d["connectionProperties"]["tunnelState"] != "unavailable"]
if not live:
    listed = ", ".join(name(d) for d in devices)
    print(f"{listed} is paired but not connected right now. "
          "Plug it in and unlock it if this fails.", file=sys.stderr)
elif len(live) > 1 and not wanted:
    listed = ", ".join(name(d) for d in live)
    sys.exit(f"Several devices are connected ({listed}). Choose one with: --device NAME")

device = (live or devices)[0]
if device["deviceProperties"].get("developerModeStatus") == "disabled":
    sys.exit(f"Developer Mode is off on {name(device)}. Turn it on in Settings > "
             "Privacy & Security > Developer Mode, restart the device, then rerun.")
print(device["identifier"], device["hardwareProperties"]["udid"], name(device), sep="\t")
' "$DEVICES_JSON")

IFS=$'\t' read -r DEVICE_ID DEVICE_UDID DEVICE_NAME <<<"$TARGET"
echo "Device: $DEVICE_NAME"

# Signing on a device is not optional. One team in the keychain is the common
# case, so find it rather than making everyone look up their team id.
if [ -z "$TEAM" ]; then
    TEAM=$(security find-identity -v -p codesigning 2>/dev/null |
        sed -n 's/^ *[0-9]*) [0-9A-Fa-f]* "\(Apple Develop[^"]*\)"$/\1/p' |
        while IFS= read -r identity; do
            security find-certificate -c "$identity" -p 2>/dev/null |
                openssl x509 -noout -subject 2>/dev/null |
                tr ',' '\n' | sed -n 's/.*OU *= *\([A-Z0-9]\{6,\}\).*/\1/p' | head -1
        done | sort -u)
fi
set -- $TEAM
case "$#" in
    0) echo "No Apple development certificate in your keychain. Open Xcode > Settings" >&2
       echo "> Accounts, add your Apple ID, and let it create one — a free account is" >&2
       echo "enough. Then rerun, or pass the team id with --team." >&2
       exit 1 ;;
    1) ;;
    *) echo "Several signing teams found: $(tr '\n' ' ' <<<"$TEAM")" >&2
       echo "Pick one with: --team TEAMID" >&2
       exit 1 ;;
esac
echo "Team: $TEAM"

DESTINATION="platform=iOS,id=$DEVICE_UDID"
OVERRIDES=(-allowProvisioningUpdates "DEVELOPMENT_TEAM=$TEAM")
[ -n "$BUNDLE_OVERRIDE" ] && OVERRIDES+=("PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_OVERRIDE")

# Ask the build system for the bundle id and the .app path rather than
# hardcoding them, so renaming the target can't silently break the shortcut.
SETTINGS=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -destination "$DESTINATION" -configuration Debug "${OVERRIDES[@]}" \
    -showBuildSettings 2>/dev/null |
    awk -F' = ' '
        !id  && /PRODUCT_BUNDLE_IDENTIFIER/ { id = $2 }
        !dir && /TARGET_BUILD_DIR/          { dir = $2 }
        !app && /WRAPPER_NAME/              { app = $2 }
        END { print id; print dir "/" app }')
BUNDLE_ID=$(sed -n 1p <<<"$SETTINGS")
APP_PATH=$(sed -n 2p <<<"$SETTINGS")

if [ -z "$BUNDLE_ID" ] || [ "$APP_PATH" = "/" ]; then
    echo "Could not read build settings for scheme '$SCHEME'." >&2
    exit 1
fi

echo "Building $SCHEME for $DEVICE_NAME…"
if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -destination "$DESTINATION" -configuration Debug "${OVERRIDES[@]}" -quiet build; then
    echo >&2
    echo "Build failed. If the error mentions the bundle identifier, '$BUNDLE_ID'" >&2
    echo "is already registered to someone else — pick your own, for example:" >&2
    echo "  ./scripts/install.sh --bundle-id com.yourname.scripty" >&2
    exit 1
fi

echo "Installing…"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" >/dev/null

if [ "$LAUNCH" -eq 1 ]; then
    # `--` keeps devicectl from reading the leading-dash demo flag as its own.
    LAUNCH_ARGS=()
    [ "$DEMO" -eq 1 ] && LAUNCH_ARGS=(-- -scripty.demo YES)
    if ! xcrun devicectl device process launch --device "$DEVICE_ID" \
        --terminate-existing "$BUNDLE_ID" "${LAUNCH_ARGS[@]+"${LAUNCH_ARGS[@]}"}" >/dev/null; then
        echo >&2
        echo "Installed, but the app would not start. A free Apple ID signs apps with" >&2
        echo "a certificate the device does not trust until you approve it: on the" >&2
        echo "device, Settings > General > VPN & Device Management > tap your Apple ID" >&2
        echo "> Trust. Then open Scripty from the Home Screen." >&2
        exit 1
    fi
fi

echo "Scripty is installed on $DEVICE_NAME."
