#!/bin/bash
# Usage: ./notarizer.sh
#   Builds, signs, notarizes, and staples yowee.app for distribution.
#
#   Required env vars (see error message below if any are missing):
#     NOTARIZE_TEAM_ID   — 10-character Apple Developer team ID
#     NOTARIZE_APPLE_ID  — Apple ID email address
#     NOTARIZE_PASSWORD  — app-specific password from appleid.apple.com

set -e

# ── Required environment variables ────────────────────────────────────────────
missing=()
[[ -z "$NOTARIZE_TEAM_ID"  ]] && missing+=("NOTARIZE_TEAM_ID")
[[ -z "$NOTARIZE_APPLE_ID" ]] && missing+=("NOTARIZE_APPLE_ID")
[[ -z "$NOTARIZE_PASSWORD" ]] && missing+=("NOTARIZE_PASSWORD")

if [[ ${#missing[@]} -gt 0 ]]; then
    cat >&2 <<'EOF'
Error: missing required environment variables:

  NOTARIZE_TEAM_ID    your 10-character Apple Developer team ID
  NOTARIZE_APPLE_ID   your Apple ID email address
  NOTARIZE_PASSWORD   app-specific password from appleid.apple.com

Export them before running this script:

  export NOTARIZE_TEAM_ID="XXXXXXXXXX"
  export NOTARIZE_APPLE_ID="you@example.com"
  export NOTARIZE_PASSWORD="xxxx-xxxx-xxxx-xxxx"
EOF
    exit 1
fi

# ── Config ────────────────────────────────────────────────────────────────────
REPO="$(cd "$(dirname "$0")" && pwd)"
SCHEME="yowee"
DERIVED="$REPO/build/derived"
BINARY="$DERIVED/Build/Products/Release/yowee"
APP="$REPO/build/yowee.app"
ZIP_PATH="$REPO/build/yowee-notarize.zip"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
XCBUILD="DEVELOPER_DIR=$DEVELOPER_DIR xcodebuild -scheme $SCHEME -destination platform=macOS,arch=arm64 -derivedDataPath $DERIVED -configuration Release"

# ── Summary state ─────────────────────────────────────────────────────────────
S_PREFLIGHT="skip"; D_PREFLIGHT="skipped"
S_BUILD="skip";     D_BUILD="skipped"
S_ASSEMBLE="skip";  D_ASSEMBLE="skipped"
S_SIGN="skip";      D_SIGN="skipped"
S_ZIP="skip";       D_ZIP="skipped"
S_NOTARIZE="skip";  D_NOTARIZE="skipped"
S_STAPLE="skip";    D_STAPLE="skipped"
S_VERIFY="skip";    D_VERIFY="skipped"

# ── Helpers ───────────────────────────────────────────────────────────────────
warn() { echo "  ⚠ $*" >&2; }
step() { echo ""; echo "── $* "; }

icon() {
    case $1 in
        pass) echo "✓" ;; warn) echo "⚠" ;;
        fail) echo "✗" ;; skip) echo "○" ;;
        miss) echo "?" ;; *)    echo " " ;;
    esac
}

# ── Cleanup ───────────────────────────────────────────────────────────────────
TMP_FILES=()
cleanup() {
    local f
    for f in "${TMP_FILES[@]}"; do
        [[ -n "$f" && -e "$f" ]] && rm -f "$f"
    done
}
trap cleanup EXIT

mktmp() {
    local t
    t=$(mktemp)
    TMP_FILES+=("$t")
    echo "$t"
}

# ── Preflight ─────────────────────────────────────────────────────────────────
step "Preflight"
PREFLIGHT_FAIL=0

IDENTITY_OUT=$(mktmp)
security find-identity -v -p codesigning > "$IDENTITY_OUT" 2>/dev/null || true
CERT_LINE=$(grep "Developer ID Application.*$NOTARIZE_TEAM_ID" "$IDENTITY_OUT" | head -1 || true)
if [[ -n "$CERT_LINE" ]]; then
    echo "  ✓ Developer ID cert found for team $NOTARIZE_TEAM_ID"
    echo "    $(echo "$CERT_LINE" | sed 's/^[[:space:]]*//')"
    # Extract full identity string for signing (e.g. "Developer ID Application: Name (TEAM)")
    SIGN_IDENTITY=$(echo "$CERT_LINE" | sed -E 's/.*"(.+)".*/\1/')
else
    warn "No 'Developer ID Application' certificate found for team $NOTARIZE_TEAM_ID"
    warn "Install it via Xcode → Settings → Accounts, or download from developer.apple.com"
    PREFLIGHT_FAIL=1
    SIGN_IDENTITY=""
fi

if xcrun --find notarytool &>/dev/null; then
    echo "  ✓ xcrun notarytool available"
else
    warn "xcrun notarytool not found — Xcode 13 or newer is required"
    PREFLIGHT_FAIL=1
fi

if [[ -f "$REPO/Info.plist" ]]; then
    echo "  ✓ Info.plist present"
else
    warn "Info.plist not found at $REPO/Info.plist"
    PREFLIGHT_FAIL=1
fi

if [[ $PREFLIGHT_FAIL -eq 0 ]]; then
    S_PREFLIGHT="pass"; D_PREFLIGHT="cert + notarytool ready"
else
    S_PREFLIGHT="fail"; D_PREFLIGHT="missing prerequisites (see above)"
fi

# ── Build ─────────────────────────────────────────────────────────────────────
if [[ $S_PREFLIGHT == "pass" ]]; then
    step "Build  (Release, Developer ID signed)"
    BUILD_LOG=$(mktmp)
    # CODE_SIGN_IDENTITY uses the full cert name so xcodebuild picks the right cert.
    # --options runtime enables the hardened runtime required for notarization.
    if eval "$XCBUILD build \
            CODE_SIGN_IDENTITY=\"$SIGN_IDENTITY\" \
            CODE_SIGN_STYLE=Manual \
            DEVELOPMENT_TEAM=\"$NOTARIZE_TEAM_ID\" \
            OTHER_CODE_SIGN_FLAGS=\"--timestamp --options runtime\"" \
            > "$BUILD_LOG" 2>&1; then
        echo "  ✓ Build succeeded  →  $BINARY"
        S_BUILD="pass"; D_BUILD="succeeded"
    else
        warn "Build failed. Full log:"
        cat "$BUILD_LOG" >&2
        S_BUILD="fail"; D_BUILD="xcodebuild build failed"
    fi
fi

# ── Assemble .app ─────────────────────────────────────────────────────────────
if [[ $S_BUILD == "pass" ]]; then
    step "Assemble .app"
    ICON_SRC="$REPO/Sources/yowee/Assets.xcassets/AppIcon.appiconset/mike.icns"
    # Assemble into a temp dir then rename atomically so an interrupt can't
    # leave a half-deleted bundle that silently blocks the next run.
    APP_TMP="${APP}.tmp"
    rm -rf "$APP_TMP"
    mkdir -p "$APP_TMP/Contents/MacOS" "$APP_TMP/Contents/Resources"
    cp "$BINARY"          "$APP_TMP/Contents/MacOS/yowee"
    cp "$REPO/Info.plist" "$APP_TMP/Contents/Info.plist"
    if [[ -f "$ICON_SRC" ]]; then
        cp "$ICON_SRC" "$APP_TMP/Contents/Resources/mike.icns"
        echo "  ✓ Copied app icon"
    else
        warn "Icon not found at $ICON_SRC — app will have no icon"
    fi
    rm -rf "$APP"
    mv "$APP_TMP" "$APP"
    echo "  ✓ Assembled $APP"
    S_ASSEMBLE="pass"; D_ASSEMBLE="bundle created"
fi

# ── Sign ──────────────────────────────────────────────────────────────────────
if [[ $S_ASSEMBLE == "pass" ]]; then
    step "Sign  (Developer ID + hardened runtime)"
    SIGN_LOG=$(mktmp)
    # --timestamp    embeds a secure timestamp (required by notary service)
    # --options runtime  enables hardened runtime (required by notary service)
    # --force        replaces any existing ad-hoc signature from xcodebuild
    if codesign \
            --force \
            --deep \
            --sign "$SIGN_IDENTITY" \
            --timestamp \
            --options runtime \
            "$APP" > "$SIGN_LOG" 2>&1; then
        AUTHORITY=$(codesign -dv "$APP" 2>&1 | grep "Authority=Developer ID" | head -1 || true)
        echo "  ✓ Signed"
        [[ -n "$AUTHORITY" ]] && echo "    $AUTHORITY"
        S_SIGN="pass"; D_SIGN="Developer ID + hardened runtime"
    else
        warn "codesign failed:"
        cat "$SIGN_LOG" >&2
        S_SIGN="fail"; D_SIGN="codesign failed"
    fi
fi

# ── Zip ───────────────────────────────────────────────────────────────────────
if [[ $S_SIGN == "pass" ]]; then
    step "Zip"
    rm -f "$ZIP_PATH"
    # ditto preserves macOS metadata and resource forks — required by notary service.
    if ditto -c -k --keepParent "$APP" "$ZIP_PATH" 2>/dev/null; then
        ZIP_SIZE=$(du -h "$ZIP_PATH" | awk '{print $1}')
        echo "  ✓ Created $ZIP_PATH ($ZIP_SIZE)"
        S_ZIP="pass"; D_ZIP="$ZIP_SIZE"
    else
        warn "ditto failed to create $ZIP_PATH"
        S_ZIP="fail"; D_ZIP="ditto failed"
    fi
fi

# ── Notarize ──────────────────────────────────────────────────────────────────
if [[ $S_ZIP == "pass" ]]; then
    step "Notarize  (submitting to Apple — may take a few minutes)"
    NOTARY_LOG=$(mktmp)
    set +e
    xcrun notarytool submit "$ZIP_PATH" \
        --apple-id "$NOTARIZE_APPLE_ID" \
        --password "$NOTARIZE_PASSWORD" \
        --team-id "$NOTARIZE_TEAM_ID" \
        --wait > "$NOTARY_LOG" 2>&1
    NOTARY_EXIT=$?
    set -e

    sed "s/$NOTARIZE_PASSWORD/****/g" "$NOTARY_LOG" || cat "$NOTARY_LOG"

    SUBMISSION_ID=$(grep -E "^[[:space:]]*id:" "$NOTARY_LOG" | head -1 | awk '{print $2}' || true)
    NOTARY_STATUS=$(grep -E "^[[:space:]]*status:" "$NOTARY_LOG" | tail -1 | awk '{print $2}' || true)

    if [[ $NOTARY_EXIT -eq 0 && "$NOTARY_STATUS" == "Accepted" ]]; then
        echo "  ✓ Notarization Accepted  (submission $SUBMISSION_ID)"
        S_NOTARIZE="pass"; D_NOTARIZE="Accepted ($SUBMISSION_ID)"
    else
        warn "Notarization failed: status=${NOTARY_STATUS:-unknown}  exit=$NOTARY_EXIT"
        if [[ -n "$SUBMISSION_ID" ]]; then
            echo ""
            echo "── Notary log for submission $SUBMISSION_ID ──"
            xcrun notarytool log "$SUBMISSION_ID" \
                --apple-id "$NOTARIZE_APPLE_ID" \
                --password "$NOTARIZE_PASSWORD" \
                --team-id "$NOTARIZE_TEAM_ID" 2>&1 \
                | sed "s/$NOTARIZE_PASSWORD/****/g" || true
        fi
        S_NOTARIZE="fail"; D_NOTARIZE="status=${NOTARY_STATUS:-unknown}"
    fi
fi

# ── Staple ────────────────────────────────────────────────────────────────────
if [[ $S_NOTARIZE == "pass" ]]; then
    step "Staple"
    STAPLE_LOG=$(mktmp)
    if xcrun stapler staple "$APP" > "$STAPLE_LOG" 2>&1; then
        echo "  ✓ Ticket stapled to $APP"
        S_STAPLE="pass"; D_STAPLE="ticket attached"
    else
        warn "stapler staple failed:"
        cat "$STAPLE_LOG" >&2
        S_STAPLE="fail"; D_STAPLE="stapler failed"
    fi
fi

# ── Verify ────────────────────────────────────────────────────────────────────
if [[ $S_STAPLE == "pass" ]]; then
    step "Verify"
    VERIFY_FAIL=0

    VAL_LOG=$(mktmp)
    if xcrun stapler validate "$APP" > "$VAL_LOG" 2>&1; then
        echo "  ✓ stapler validate"
    else
        warn "stapler validate failed:"
        cat "$VAL_LOG" >&2
        VERIFY_FAIL=1
    fi

    SPCTL_LOG=$(mktmp)
    if spctl --assess --type open --context context:primary-signature --verbose "$APP" > "$SPCTL_LOG" 2>&1; then
        echo "  ✓ spctl assess"
        cat "$SPCTL_LOG"
    else
        warn "spctl --assess failed:"
        cat "$SPCTL_LOG" >&2
        VERIFY_FAIL=1
    fi

    if [[ $VERIFY_FAIL -eq 0 ]]; then
        S_VERIFY="pass"; D_VERIFY="stapler + spctl OK"
    else
        S_VERIFY="fail"; D_VERIFY="verification failed (see above)"
    fi
fi

# ── Summary table ─────────────────────────────────────────────────────────────
DIV="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SEP="  ────────────────────────────────────────────────────────────────────────"
row() { printf "  %-22s %s  %s\n" "$1" "$(icon $2)" "$3"; }

echo ""
echo "$DIV"
printf "  %-22s %-4s %s\n" "Step" "" "Details"
echo "$DIV"

echo "  Notarization pipeline"
echo "$SEP"
row "Preflight"  $S_PREFLIGHT "$D_PREFLIGHT"
row "Build"      $S_BUILD     "$D_BUILD"
row "Assemble"   $S_ASSEMBLE  "$D_ASSEMBLE"
row "Sign"       $S_SIGN      "$D_SIGN"
row "Zip"        $S_ZIP       "$D_ZIP"
row "Notarize"   $S_NOTARIZE  "$D_NOTARIZE"
row "Staple"     $S_STAPLE    "$D_STAPLE"
row "Verify"     $S_VERIFY    "$D_VERIFY"

echo "$DIV"

if [[ $S_VERIFY == "pass" ]]; then
    echo ""
    echo "  Notarized app: $APP"
fi

[[ $S_PREFLIGHT == "fail" \
    || $S_BUILD     == "fail" \
    || $S_ASSEMBLE  == "fail" \
    || $S_SIGN      == "fail" \
    || $S_NOTARIZE  == "fail" \
    || $S_STAPLE    == "fail" ]] && exit 1
exit 0
