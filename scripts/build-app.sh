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
ditto_signing_identity="${DITTO_SIGN_IDENTITY:-}"
if [[ -z "$ditto_signing_identity" && -f "$ditto_root/.build/signing-identity" ]]; then
    IFS= read -r ditto_signing_identity < "$ditto_root/.build/signing-identity"
fi
ditto_signing_identity="${ditto_signing_identity:--}"
codesign --force --sign "$ditto_signing_identity" --identifier com.vaibhav0806.ditto "$ditto_app"
codesign --verify --strict "$ditto_app"
printf '%s\n' "$ditto_signing_identity" > "$ditto_root/.build/signing-identity"
printf '%s\n' "$ditto_app"
