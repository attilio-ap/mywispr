#!/bin/bash
# Compiles and runs every suite under Tests/.
#
# Each suite is a standalone executable built against the app sources (main.swift
# is excluded — it holds the app's entry point, which would clash with the
# suite's own top-level code).
#
# Usage:
#   ./run-tests.sh                 run everything
#   ./run-tests.sh Analytics       run one suite
set -euo pipefail

# Sources under test. Mirrors build.sh minus main.swift.
SOURCES="AppState.swift DictationStateMachine.swift Localization.swift Theme.swift KeyboardManager.swift SpeechManager.swift OllamaManager.swift PasteManager.swift OverlayWindow.swift DashboardView.swift Logger.swift"

SDK_PATH=$(xcrun --show-sdk-path --sdk macosx)
BUILD_DIR=".build/tests"
mkdir -p "$BUILD_DIR"

FILTER="${1:-}"
suites=()
for dir in Tests/*/; do
    name=$(basename "$dir")
    [ -f "$dir/main.swift" ] || continue
    if [ -n "$FILTER" ] && [ "$name" != "$FILTER" ]; then continue; fi
    suites+=("$name")
done

if [ ${#suites[@]} -eq 0 ]; then
    echo "No suites found${FILTER:+ matching '$FILTER'}."
    exit 1
fi

failed=0
for name in "${suites[@]}"; do
    echo "──────── $name ────────"
    swiftc \
        -sdk "$SDK_PATH" \
        -target arm64-apple-macosx13.0 \
        Tests/TestSupport.swift "Tests/$name/main.swift" $SOURCES \
        -o "$BUILD_DIR/$name"
    if "$BUILD_DIR/$name"; then :; else failed=$((failed + 1)); fi
    echo ""
done

if [ "$failed" -eq 0 ]; then
    echo "════════ all suites passed ════════"
else
    echo "════════ $failed suite(s) FAILED ════════"
fi
exit "$failed"
