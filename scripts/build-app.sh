#!/bin/bash
set -euo pipefail

ditto_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ditto_root"
swift build -c release --product Ditto
ditto_bin="$(swift build -c release --show-bin-path)"
ditto_app="$ditto_root/build/Ditto.app"
mkdir -p "$ditto_app/Contents/MacOS" "$ditto_app/Contents/Resources"
cp "$ditto_bin/Ditto" "$ditto_app/Contents/MacOS/Ditto"
cp Resources/Info.plist "$ditto_app/Contents/Info.plist"
codesign --force --sign - --identifier com.vaibhav0806.ditto "$ditto_app"
codesign --verify --strict "$ditto_app"
printf '%s\n' "$ditto_app"
