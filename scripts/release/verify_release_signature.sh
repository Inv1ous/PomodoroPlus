#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $0 <app_path> [expected_team_id]

Verifies that a macOS app bundle is non-adhoc signed, has a TeamIdentifier,
and passes Gatekeeper assessment.
USAGE
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 1
fi

APP_PATH="$1"
EXPECTED_TEAM_ID="${2:-}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "[verify] App bundle not found: $APP_PATH" >&2
  exit 1
fi

if ! CODESIGN_OUTPUT="$(/usr/bin/codesign -dv --verbose=4 "$APP_PATH" 2>&1)"; then
  echo "[verify] codesign metadata check failed" >&2
  echo "$CODESIGN_OUTPUT" >&2
  exit 1
fi

SIGNATURE="$(printf '%s\n' "$CODESIGN_OUTPUT" | awk -F= '/^Signature=/{print $2; exit}' | xargs || true)"
TEAM_ID="$(printf '%s\n' "$CODESIGN_OUTPUT" | awk -F= '/^TeamIdentifier=/{print $2; exit}' | xargs || true)"
BUNDLE_ID="$(printf '%s\n' "$CODESIGN_OUTPUT" | awk -F= '/^Identifier=/{print $2; exit}' | xargs || true)"

if [[ -z "$SIGNATURE" ]]; then
  echo "[verify] Missing Signature field in codesign metadata" >&2
  echo "$CODESIGN_OUTPUT" >&2
  exit 1
fi

if [[ "${SIGNATURE,,}" == "adhoc" ]]; then
  echo "[verify] Refusing adhoc-signed app: $APP_PATH" >&2
  exit 1
fi

if [[ -z "$TEAM_ID" || "$TEAM_ID" == "not set" ]]; then
  echo "[verify] Missing TeamIdentifier for app: $APP_PATH" >&2
  exit 1
fi

if [[ -n "$EXPECTED_TEAM_ID" && "$TEAM_ID" != "$EXPECTED_TEAM_ID" ]]; then
  echo "[verify] TeamIdentifier mismatch. expected=$EXPECTED_TEAM_ID actual=$TEAM_ID" >&2
  exit 1
fi

if ! /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"; then
  echo "[verify] codesign deep verification failed" >&2
  exit 1
fi

if ! /usr/sbin/spctl --assess --type execute --verbose=4 "$APP_PATH"; then
  echo "[verify] Gatekeeper assessment failed" >&2
  exit 1
fi

echo "[verify] OK bundle_id=$BUNDLE_ID team_id=$TEAM_ID signature=$SIGNATURE"
