#!/bin/bash
#
# One-shot shortcut: build Scripty and launch it in an iPad simulator
# straight into the offline demo (sample screenplay, no account, no backend).
#
#   ./scripts/demo.sh                       # newest-runtime iPad simulator
#   ./scripts/demo.sh --device "iPhone 17"  # pick a simulator by name
#   ./scripts/demo.sh --no-build            # relaunch what is already installed
#   ./scripts/demo.sh --reset               # discard edits made in a past demo
#
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="scripty.xcodeproj"
SCHEME="scripty"
DEVICE="${SCRIPTY_DEMO_SIM:-}"
BUILD=1
RESET=0

usage() {
    sed -n '3,10p' "$0" | cut -c3-
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --device) DEVICE="${2:-}"; [ -n "$DEVICE" ] || usage 1; shift 2 ;;
        --no-build) BUILD=0; shift ;;
        --reset) RESET=1; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1" >&2; usage 1 ;;
    esac
done

if ! xcrun -f xcodebuild >/dev/null 2>&1; then
    echo "xcodebuild not found. Install Xcode, then point the tools at it:" >&2
    echo "  sudo xcode-select --switch /Applications/Xcode.app" >&2
    exit 1
fi

# Resolve a simulator UDID (names repeat across runtimes, UDIDs don't):
# prefer $DEVICE by name, else an iPad, else any iPhone — always from the
# newest installed iOS runtime.
SIMULATOR=$(xcrun simctl list -j devices available |
    SCRIPTY_DEMO_SIM="$DEVICE" /usr/bin/python3 -c '
import json, os, sys

data = json.load(sys.stdin)
wanted = os.environ.get("SCRIPTY_DEMO_SIM", "")
runtimes = sorted(
    (rt for rt in data["devices"] if "iOS" in rt),
    key=lambda rt: [int(part) for part in rt.rsplit("-", 2)[-2:]],
    reverse=True)

def pick(match):
    for runtime in runtimes:
        for device in data["devices"][runtime]:
            if match(device["name"]):
                return device
    return None

device = None
if wanted:
    device = pick(lambda name: name == wanted)
    if device is None:
        sys.exit(f"No available simulator named {wanted!r}. "
                 "List them with: xcrun simctl list devices available")
device = device or pick(lambda name: name.startswith("iPad")) \
                or pick(lambda name: name.startswith("iPhone"))
if device is None:
    sys.exit("No available iOS simulator found. Install one via Xcode > Settings > Components.")
print(device["udid"], device["name"], sep="\t")
')
SIM_ID="${SIMULATOR%%$'\t'*}"
SIM_NAME="${SIMULATOR##*$'\t'}"
DESTINATION="platform=iOS Simulator,id=$SIM_ID"
echo "Simulator: $SIM_NAME ($SIM_ID)"

# Ask the build system for the bundle id and the .app path rather than
# hardcoding them, so renaming the target can't silently break the shortcut.
SETTINGS=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -destination "$DESTINATION" -configuration Debug -showBuildSettings 2>/dev/null |
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

if [ "$BUILD" -eq 1 ]; then
    echo "Building $SCHEME…"
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
        -destination "$DESTINATION" -configuration Debug -quiet build
elif [ ! -d "$APP_PATH" ]; then
    echo "Nothing built yet at $APP_PATH — run once without --no-build." >&2
    exit 1
fi

# `simctl install` fails on a device that is still booting, so wait for boot
# to finish (-b boots it first if needed) instead of racing it.
echo "Booting $SIM_NAME…"
xcrun simctl bootstatus "$SIM_ID" -b >/dev/null
open -a Simulator

xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
if [ "$RESET" -eq 1 ]; then
    # Demo data lives in memory, so uninstalling clears everything it kept.
    xcrun simctl uninstall "$SIM_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
fi

xcrun simctl install "$SIM_ID" "$APP_PATH"
xcrun simctl launch "$SIM_ID" "$BUNDLE_ID" -scripty.demo YES >/dev/null

echo "Scripty demo running on $SIM_NAME — sample screenplay, no account needed."
