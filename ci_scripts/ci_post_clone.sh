#!/bin/sh
#
# Xcode Cloud runs this once, right after it clones the repository and before it
# resolves dependencies or builds. We use it to run the pure-Swift logic checks
# in Tests/run.sh: the ported stats/pagination arithmetic and the demo backend's
# HAL contract. The app has no XCTest target, so a build's Test action has
# nothing to run — this is where CI actually exercises that logic.
#
# A non-zero exit here fails the whole Xcode Cloud build.
#
set -e

# Xcode Cloud checks the primary repo out here; the fallback keeps the script
# runnable by hand from anywhere in the tree.
cd "${CI_PRIMARY_REPOSITORY_PATH:-"$(dirname "$0")/.."}"

./Tests/run.sh
