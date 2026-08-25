#!/bin/bash
# Builds OpenFlow and assembles a signed .app bundle in build/.
#
# Signing with a real identity matters: macOS ties the Microphone and
# Accessibility permissions to the code signature, so an ad-hoc signature would
# make you re-grant them after every rebuild.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP="$ROOT/build/OpenFlow.app"

# Any "Apple Development" identity in the login keychain will do; override with
# IDENTITY=... to pick a specific one, or IDENTITY=- for ad-hoc signing.
if [[ -z "${IDENTITY:-}" ]]; then
	IDENTITY="$(security find-identity -v -p codesigning \
		| grep -m1 'Apple Development' \
		| sed -E 's/.*"(.*)"/\1/')"
fi
if [[ -z "$IDENTITY" ]]; then
	echo "warning: no Apple Development identity found, falling back to ad-hoc signing" >&2
	echo "warning: you will have to re-grant Accessibility after every rebuild" >&2
	IDENTITY="-"
fi

echo "==> swift build -c $CONFIG"
cd "$ROOT"
swift build -c "$CONFIG"
BINARY="$(swift build -c "$CONFIG" --show-bin-path)/OpenFlow"
RESOURCE_BUNDLE="$(dirname "$BINARY")/OpenFlow_OpenFlow.bundle"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/OpenFlow"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/OpenFlow_OpenFlow.bundle"
for STRINGS in "$RESOURCE_BUNDLE"/*.lproj/InfoPlist.strings; do
	LOCALE="$(basename "$(dirname "$STRINGS")")"
	mkdir -p "$APP/Contents/Resources/$LOCALE"
	cp "$STRINGS" "$APP/Contents/Resources/$LOCALE/InfoPlist.strings"
done
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> codesign ($IDENTITY)"
codesign --force --deep --options runtime \
	--entitlements "$ROOT/Resources/OpenFlow.entitlements" \
	--sign "$IDENTITY" "$APP"
codesign --verify --verbose=2 "$APP"

echo
echo "Gotowe: $APP"
echo "Uruchom: open \"$APP\""
