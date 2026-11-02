#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/checks
swiftc Sources/Grove/Git.swift Checks/GitCheck.swift -o build/checks/git-check
build/checks/git-check
swiftc Sources/Grove/WorkspaceState.swift Checks/StateCheck.swift -o build/checks/state-check
build/checks/state-check
swiftc Sources/Grove/WorkspaceState.swift Sources/Grove/ScriptPreset.swift Checks/ScriptCheck.swift -o build/checks/script-check
build/checks/script-check
swiftc Sources/Grove/OpenTarget.swift Checks/OpenTargetCheck.swift -o build/checks/open-target-check
build/checks/open-target-check
python3 Checks/release_policy_check.py
python3 Checks/screen_check.py
scripts/grove --help >/dev/null
if [ "${GROVE_SKIP_BUILD:-0}" != "1" ]; then bash scripts/build-app.sh; fi
python3 scripts/verify_app.py
if [ "${GROVE_RUN_GUI_CHECKS:-0}" = "1" ]; then python3 Checks/app_relaunch_check.py; fi
