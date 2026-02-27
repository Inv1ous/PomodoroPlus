#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/PomodoroPlus.xcodeproj}"
SCHEME="${SCHEME:-PomodoroPlus}"
CONFIGURATION="${CONFIGURATION:-Release}"
RELEASE_TAG="${RELEASE_TAG:-}"

if [[ -z "$RELEASE_TAG" ]]; then
  RELEASE_TAG="$(/usr/bin/git -C "$ROOT_DIR" describe --tags --abbrev=0 2>/dev/null || true)"
fi

if [[ -z "$RELEASE_TAG" ]]; then
  RELEASE_TAG="manual-$(date +%Y%m%d%H%M%S)"
fi

BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pomodoroplus_personal_release.XXXXXX")"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/PomodoroPlus.app"

mkdir -p "$DERIVED_DATA"

echo "[personal-release] Building app..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "generic/platform=macOS" \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "[personal-release] Build output app not found: $APP_PATH" >&2
  exit 1
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
IDENTITY_MODE="$(/usr/libexec/PlistBuddy -c 'Print :PomodoroPlusUpdateIdentityMode' "$INFO_PLIST" 2>/dev/null || true)"
if [[ "${IDENTITY_MODE,,}" != "personal" ]]; then
  echo "[personal-release] Expected PomodoroPlusUpdateIdentityMode=personal, got '${IDENTITY_MODE:-missing}'" >&2
  exit 1
fi

DIST_DIR="$ROOT_DIR/dist"
mkdir -p "$DIST_DIR"

SAFE_TAG="${RELEASE_TAG#refs/tags/}"
SAFE_TAG="${SAFE_TAG#v}"
ARTIFACT_NAME="PomodoroPlus-v${SAFE_TAG}.zip"
ARTIFACT_PATH="$DIST_DIR/$ARTIFACT_NAME"

echo "[personal-release] Packaging app zip..."
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ARTIFACT_PATH"

echo "$ARTIFACT_PATH" > "$DIST_DIR/release_artifact_path.txt"

echo "[personal-release] Done: $ARTIFACT_PATH"
