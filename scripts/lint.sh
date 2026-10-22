#!/bin/bash
# Checks formatting (swift-format) and lint rules (SwiftLint), as CI does.
#   scripts/lint.sh         check only
#   scripts/lint.sh --fix   apply formatting first
set -euo pipefail

SWIFTLINT_VERSION="0.65.1"
SWIFTLINT_SHA256="c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PATHS=(Sources Tests Package.swift)

if [ "${1:-}" = "--fix" ]; then
    swift format format --in-place --recursive --parallel "${PATHS[@]}"
fi

BIN_DIR="$ROOT/.build/swiftlint/$SWIFTLINT_VERSION"
SWIFTLINT="$BIN_DIR/swiftlint"
if [ ! -x "$SWIFTLINT" ]; then
    mkdir -p "$BIN_DIR"
    ZIP="$BIN_DIR/portable_swiftlint.zip"
    curl -fsSL -o "$ZIP" "https://github.com/realm/SwiftLint/releases/download/$SWIFTLINT_VERSION/portable_swiftlint.zip"
    if ! echo "$SWIFTLINT_SHA256  $ZIP" | shasum -a 256 -c - >/dev/null; then
        rm -f "$ZIP"
        echo "SwiftLint download failed checksum verification" >&2
        exit 1
    fi
    unzip -q -o "$ZIP" swiftlint -d "$BIN_DIR"
    rm -f "$ZIP"
fi

status=0
echo "swift-format $(swift format --version)"
swift format lint --strict --recursive --parallel "${PATHS[@]}" || status=1
echo "SwiftLint $("$SWIFTLINT" version)"
"$SWIFTLINT" lint --quiet --strict || status=1
exit $status
