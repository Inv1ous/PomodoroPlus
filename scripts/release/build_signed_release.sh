#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFY_SCRIPT="$ROOT_DIR/scripts/release/verify_release_signature.sh"

PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/PomodoroPlus.xcodeproj}"
SCHEME="${SCHEME:-PomodoroPlus}"
CONFIGURATION="${CONFIGURATION:-Release}"
RELEASE_TAG="${RELEASE_TAG:-}"

TEAM_ID="${APPLE_TEAM_ID:-}"
NOTARY_KEY_ID="${APPLE_NOTARY_KEY_ID:-}"
NOTARY_ISSUER_ID="${APPLE_NOTARY_ISSUER_ID:-}"
NOTARY_API_KEY_FILE="${APPLE_NOTARY_API_KEY_FILE:-}"

if [[ -z "$TEAM_ID" ]]; then
  echo "[release] APPLE_TEAM_ID is required" >&2
  exit 1
fi

if [[ -z "$NOTARY_KEY_ID" || -z "$NOTARY_ISSUER_ID" || -z "$NOTARY_API_KEY_FILE" ]]; then
  echo "[release] Notary credentials are required (APPLE_NOTARY_KEY_ID, APPLE_NOTARY_ISSUER_ID, APPLE_NOTARY_API_KEY_FILE)" >&2
  exit 1
fi

if [[ ! -f "$NOTARY_API_KEY_FILE" ]]; then
  echo "[release] Notary API key file not found: $NOTARY_API_KEY_FILE" >&2
  exit 1
fi

if [[ ! -x "$VERIFY_SCRIPT" ]]; then
  echo "[release] Verify script missing or not executable: $VERIFY_SCRIPT" >&2
  exit 1
fi

if [[ -z "$RELEASE_TAG" ]]; then
  RELEASE_TAG="$(/usr/bin/git -C "$ROOT_DIR" describe --tags --abbrev=0 2>/dev/null || true)"
fi

if [[ -z "$RELEASE_TAG" ]]; then
  RELEASE_TAG="manual-$(date +%Y%m%d%H%M%S)"
fi

BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pomodoroplus_release.XXXXXX")"
ARCHIVE_PATH="$BUILD_ROOT/PomodoroPlus.xcarchive"
EXPORT_PATH="$BUILD_ROOT/export"
NOTARIZE_ZIP="$BUILD_ROOT/PomodoroPlus-notarize.zip"
EXPORT_OPTIONS_PLIST="$BUILD_ROOT/ExportOptions.plist"

mkdir -p "$EXPORT_PATH"

cat > "$EXPORT_OPTIONS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
</dict>
</plist>
PLIST

echo "[release] Archiving app..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  POMODOROPLUS_EXPECTED_TEAM_IDENTIFIER="$TEAM_ID"

echo "[release] Exporting signed archive..."
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

APP_PATH="$(find "$EXPORT_PATH" -maxdepth 2 -name '*.app' -print -quit)"
if [[ -z "$APP_PATH" ]]; then
  echo "[release] Export did not produce an .app bundle" >&2
  exit 1
fi

echo "[release] Verifying pre-notarization signature..."
"$VERIFY_SCRIPT" "$APP_PATH" "$TEAM_ID"

echo "[release] Creating zip for notarization..."
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"

echo "[release] Submitting for notarization..."
xcrun notarytool submit "$NOTARIZE_ZIP" \
  --key "$NOTARY_API_KEY_FILE" \
  --key-id "$NOTARY_KEY_ID" \
  --issuer "$NOTARY_ISSUER_ID" \
  --wait

echo "[release] Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"

echo "[release] Verifying stapled app..."
"$VERIFY_SCRIPT" "$APP_PATH" "$TEAM_ID"

DIST_DIR="$ROOT_DIR/dist"
mkdir -p "$DIST_DIR"

SAFE_TAG="${RELEASE_TAG#refs/tags/}"
SAFE_TAG="${SAFE_TAG#v}"
ARTIFACT_NAME="PomodoroPlus-v${SAFE_TAG}.zip"
ARTIFACT_PATH="$DIST_DIR/$ARTIFACT_NAME"

echo "[release] Creating distributable artifact..."
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ARTIFACT_PATH"

echo "$ARTIFACT_PATH" > "$DIST_DIR/release_artifact_path.txt"

echo "[release] Done: $ARTIFACT_PATH"
