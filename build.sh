#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP=PromptDesigner.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
# Compile all Swift sources into the app binary
echo "Compiling PromptDesigner..."
swiftc -O -o "$APP/Contents/MacOS/PromptDesigner" \
  Sources/Models.swift \
  Sources/CompilerService.swift \
  Sources/ViewModels.swift \
  Sources/Views.swift \
  Sources/App.swift \
  -framework Cocoa -framework SwiftUI -framework UniformTypeIdentifiers

# Copy example workflows BEFORE signing
mkdir -p "$APP/Contents/Resources/Examples"
cp -R Examples/* "$APP/Contents/Resources/Examples" 2>/dev/null || true

# Ad-hoc sign (or use Developer ID if available)
if security find-identity -v -p codesigning | grep -q "QuickAssist Dev Signing"; then
  codesign --force --sign "QuickAssist Dev Signing" "$APP" 2>&1 | tail -n 5
else
  codesign --force --sign - "$APP" 2>&1 | tail -n 5
fi

echo "Built $PWD/$APP"
echo "Run with: open $PWD/$APP"
