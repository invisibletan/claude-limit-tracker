#!/bin/bash
# Runs the unit tests.
#
# The extra flags make swift-testing work on machines with only the Xcode
# Command Line Tools (no full Xcode): CLT ships Testing.framework outside the
# default search path, and its Foundation cross-import overlay is broken there.
set -euo pipefail
cd "$(dirname "$0")"

FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
if [ -d "$FW/Testing.framework" ]; then
    exec swift test \
        -Xswiftc -F -Xswiftc "$FW" \
        -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
        -Xlinker -F -Xlinker "$FW" \
        -Xlinker -rpath -Xlinker "$FW" \
        "$@"
fi
exec swift test "$@"
