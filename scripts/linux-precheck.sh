#!/bin/bash
# Quick pre-check for machines without macOS (for example a Linux container
# or CI-less review). It cannot build Grove: SwiftUI and AppKit do not exist
# on Linux. It does:
#   1. syntax-check every Swift file (swiftc -parse), and
#   2. build and run the Foundation-only checks from scripts/check.sh.
# The full check is still `make check` on a Mac or the macOS CI job.
#
# Needs a Swift toolchain on PATH (https://www.swift.org/install/linux/) and
# /bin/zsh for the script check.
set -uo pipefail
cd "$(dirname "$0")/.."
command -v swiftc >/dev/null || { echo "swiftc not found on PATH"; exit 2; }
export SWIFT_BACKTRACE=enable=no
mkdir -p build/checks
status=0
for file in Sources/Grove/*.swift Tests/GroveTests/*.swift Checks/*.swift; do
  if ! swiftc -parse "$file" >/dev/null 2>build/checks/parse.err; then
    echo "PARSE FAIL $file"; cat build/checks/parse.err; status=1
  fi
done
echo "parse      all Swift files"
# name: sources (only checks whose sources need nothing beyond Foundation)
while read -r name sources; do
  [ -n "$name" ] || continue
  if ! swiftc $sources -o "build/checks/$name" 2>"build/checks/$name.err"; then
    echo "BUILD FAIL $name"; grep -A3 'error:' "build/checks/$name.err" | head -20; status=1
  elif output=$("build/checks/$name" 2>&1); then
    echo "ok         $name"
  else
    echo "FAIL       $name"; echo "$output" | grep -v '^0x' | head -8; status=1
  fi
done <<'CHECKS'
git-check Sources/Grove/Git.swift Checks/GitCheck.swift
state-check Sources/Grove/WorkspaceState.swift Checks/StateCheck.swift
script-check Sources/Grove/WorkspaceState.swift Sources/Grove/ScriptPreset.swift Checks/ScriptCheck.swift
agent-prompt-check Sources/Grove/AgentPrompt.swift Checks/AgentPromptCheck.swift
attention-alerts-check Sources/Grove/AttentionAlerts.swift Checks/AttentionAlertsCheck.swift
pr-summary-check Sources/Grove/PullRequestSummary.swift Checks/PullRequestSummaryCheck.swift
CHECKS
if python3 Checks/release_policy_check.py >/dev/null 2>&1; then echo "ok         release_policy_check"; else echo "FAIL       release_policy_check"; status=1; fi
if git diff --check HEAD >/dev/null; then echo "ok         git diff --check"; else git diff --check HEAD; status=1; fi
exit $status
