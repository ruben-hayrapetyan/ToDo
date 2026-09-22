#!/bin/bash
# Compiles the model and store with the tests and runs them. Only the
# non-UI sources are included, so no window ever opens.
set -euo pipefail

cd "$(dirname "$0")"
mkdir -p build
xcrun swiftc \
  -swift-version 5 \
  -target "$(uname -m)-apple-macos13.0" \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  Sources/Todo.swift Sources/TodoStore.swift Tests/main.swift \
  -o build/tests
build/tests
