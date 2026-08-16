#!/bin/bash
#
# Installs the bundled FFmpegKit macOS frameworks into
# ./Frameworks. Run from the pod root (the plugin's `macos/` directory) — the
# podspec's prepare_command does exactly that.
#
# Same robustness contract as setup_ios.sh (see issue #88):
#   * Atomic install — ./Frameworks is only populated after a fully successful
#     extraction + sanity check, so a failure never leaves a broken
#     half-populated directory behind (which is what made the next `pod install`
#     skip setup and produce a confusing "header not found" build error).
#
set -euo pipefail

VERSION="8.1.2"
VARIANT="audio"
ARCHIVE_NAME="ffmpeg-kit-macos-${VARIANT}-${VERSION}.zip"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLED_ARCHIVE="${SCRIPT_DIR}/../macos/prebuilt/${ARCHIVE_NAME}"
BUNDLED_SHA256="415a871b964a8c3c12a4d0e7e02a30cf877380b29624cbc4f533590d3f4b9a25"

FRAMEWORKS="ffmpegkit libavcodec libavdevice libavfilter libavformat libavutil libswresample libswscale"

fail() {
  {
    echo ""
    echo "======================================================================"
    echo "[ffmpeg_kit_flutter] ERROR: could not set up the macOS frameworks."
    echo "  $1"
    echo ""
    echo "Bundled archive:"
    echo "  $BUNDLED_ARCHIVE"
    echo "Restore the plugin's macos/prebuilt directory, then run pod install again."
    echo "======================================================================"
  } >&2
  exit 1
}

sign_frameworks() {
  local BASE="$1"

  # The upstream zip contains AppleDouble sidecar files (._Resources,
  # ._Headers, etc.). They are not framework resources and make codesign reject
  # the bundle with "unsealed contents present in the root directory".
  find "$BASE" -type f \( -name '._*' -o -name '.DS_Store' \) -delete

  for FW in $FRAMEWORKS; do
    local PATH_TO_FRAMEWORK="${BASE}/${FW}.framework"
    [ -d "$PATH_TO_FRAMEWORK" ] || return 1
    codesign --force --sign - --timestamp=none "$PATH_TO_FRAMEWORK" || return 1
    codesign --verify --strict "$PATH_TO_FRAMEWORK" || return 1
  done
}

command -v codesign >/dev/null 2>&1 || fail "The codesign tool is unavailable."

# Self-healing / idempotent. Re-sign an existing installation because tools
# such as bitcode_strip invalidate any signature shipped in the archive.
if [ -d "Frameworks/ffmpegkit.framework" ]; then
  echo "[ffmpeg_kit_flutter] Signing existing macOS frameworks..."
  sign_frameworks "Frameworks" || fail "Existing frameworks are incomplete or could not be signed."
  echo "[ffmpeg_kit_flutter] macOS frameworks already present and valid."
  exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/ffmpegkit-macos.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

[ -f "$BUNDLED_ARCHIVE" ] || fail "The bundled archive is missing."
[ -s "$BUNDLED_ARCHIVE" ] || fail "The bundled archive is empty."
ACTUAL_SHA256="$(shasum -a 256 "$BUNDLED_ARCHIVE" | awk '{print $1}')"
[ "$ACTUAL_SHA256" = "$BUNDLED_SHA256" ] || \
  fail "Archive checksum mismatch (expected $BUNDLED_SHA256, got $ACTUAL_SHA256)."

echo "[ffmpeg_kit_flutter] Preparing bundled macOS frameworks ($VARIANT $VERSION)..."
cp "$BUNDLED_ARCHIVE" "$WORK/frameworks.zip"

if ! unzip -tq "$WORK/frameworks.zip" >/dev/null 2>&1; then
  fail "The bundled archive is not a valid zip."
fi

mkdir -p "$WORK/extract"
unzip -oq "$WORK/frameworks.zip" -d "$WORK/extract"
rm -rf "$WORK/extract/__MACOSX"

# Verify all expected frameworks are present.
for FW in $FRAMEWORKS; do
  [ -d "$WORK/extract/${FW}.framework" ] || \
    fail "The archive is missing ${FW}.framework — it may be corrupt or the wrong build."
done

# Delete bitcode from all frameworks (required for App Store submission).
for FW in $FRAMEWORKS; do
  BIN="$WORK/extract/${FW}.framework/${FW}"
  [ -f "$BIN" ] && xcrun bitcode_strip -r "$BIN" -o "$BIN"
done

# macOS signs the outer app even for a local release build. Its nested dynamic
# frameworks must therefore carry at least an ad-hoc signature. A distribution
# build can replace this signature with its configured identity during embed.
echo "[ffmpeg_kit_flutter] Signing macOS frameworks..."
sign_frameworks "$WORK/extract" || fail "Failed to ad-hoc sign the macOS frameworks."

# --- Atomic install ---
rm -rf Frameworks
mkdir -p Frameworks
for FW in $FRAMEWORKS; do
  mv "$WORK/extract/${FW}.framework" "Frameworks/${FW}.framework"
done

echo "[ffmpeg_kit_flutter] macOS frameworks installed successfully."
