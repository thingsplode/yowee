#!/bin/bash
# Usage: ./publisher.sh
#   Packages the notarized yowee.app as a DMG, publishes a GitHub release,
#   and updates the Homebrew tap formula.
#
#   Prerequisites:
#     - ./notarizer.sh has been run successfully (build/yowee.app is stapled)
#     - gh CLI authenticated (gh auth login)
#     - SSH access to thingsplode/yowee and thingsplode/homebrew-yowee
#
# After editing this file, make it executable:  chmod +x publisher.sh

set -e

# ── Config ────────────────────────────────────────────────────────────────────
REPO="$(cd "$(dirname "$0")" && pwd)"
APP="$REPO/build/yowee.app"
INFO_PLIST="$REPO/Info.plist"
GH_USER="thingsplode"
APP_REPO="$GH_USER/yowee"
TAP_REPO="$GH_USER/homebrew-yowee"
TAP_REPO_SSH="git@github.com:$TAP_REPO.git"
CASK_NAME="yowee"
# GIT_EMAIL must be set to a GitHub-verified public address to satisfy the
# email-privacy guard on push. Export it before running this script:
#   export GIT_EMAIL="you@example.com"
GIT_EMAIL="${GIT_EMAIL:-}"

# ── Summary state ─────────────────────────────────────────────────────────────
S_PREFLIGHT="skip"; D_PREFLIGHT="skipped"
S_DMG="skip";       D_DMG="skipped"
S_SHA="skip";       D_SHA="skipped"
S_RELEASE="skip";   D_RELEASE="skipped"
S_TAP="skip";       D_TAP="skipped"

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

# Prompt user with y/N confirmation. Returns 0 for yes, 1 for no.
confirm() {
    local prompt="$1"
    local reply
    read -r -p "  $prompt [y/N] " reply </dev/tty || return 1
    [[ "$reply" == "y" || "$reply" == "Y" ]]
}

# ── Cleanup ───────────────────────────────────────────────────────────────────
TMP_FILES=()
cleanup() {
    local f
    for f in "${TMP_FILES[@]}"; do
        [[ -n "$f" && -e "$f" ]] && rm -rf "$f"
    done
}
trap cleanup EXIT

mktmp() {
    local t
    t=$(mktemp)
    TMP_FILES+=("$t")
    echo "$t"
}

mktmpdir() {
    local t
    t=$(mktemp -d)
    TMP_FILES+=("$t")
    echo "$t"
}

# ── Preflight ─────────────────────────────────────────────────────────────────
step "Preflight"
PREFLIGHT_FAIL=0

# Check GIT_EMAIL
if [[ -n "$GIT_EMAIL" ]]; then
    echo "  ✓ GIT_EMAIL: $GIT_EMAIL"
else
    warn "GIT_EMAIL not set — tap commit will use git global config, which may be a private noreply address"
    warn "Set it with:  export GIT_EMAIL=\"you@example.com\""
    PREFLIGHT_FAIL=1
fi

# Check create-dmg
if command -v create-dmg &>/dev/null; then
    echo "  ✓ create-dmg available"
else
    warn "create-dmg not found. Install with:  brew install create-dmg"
    if confirm "Install now?"; then
        if brew install create-dmg; then
            echo "  ✓ create-dmg installed"
        else
            warn "brew install create-dmg failed"
            PREFLIGHT_FAIL=1
        fi
    else
        PREFLIGHT_FAIL=1
    fi
fi

# Check gh
if command -v gh &>/dev/null; then
    echo "  ✓ gh available"
else
    warn "gh not found. Install with:  brew install gh"
    if confirm "Install now?"; then
        if brew install gh; then
            echo "  ✓ gh installed"
        else
            warn "brew install gh failed"
            PREFLIGHT_FAIL=1
        fi
    else
        PREFLIGHT_FAIL=1
    fi
fi

# Check gh auth (only meaningful if gh is now installed)
if command -v gh &>/dev/null; then
    set +e
    gh auth status &>/dev/null
    GH_AUTH_EXIT=$?
    set -e
    if (( GH_AUTH_EXIT == 0 )); then
        echo "  ✓ gh authenticated"
    else
        warn "gh is not authenticated. Run:  gh auth login"
        PREFLIGHT_FAIL=1
    fi
fi

# Check Info.plist
if [[ -f "$INFO_PLIST" ]]; then
    echo "  ✓ Info.plist present"
else
    warn "Info.plist not found at $INFO_PLIST"
    PREFLIGHT_FAIL=1
fi

# Check the notarized app exists
if [[ -d "$APP" ]]; then
    echo "  ✓ build/yowee.app present"
else
    warn "build/yowee.app not found — run ./notarizer.sh first"
    PREFLIGHT_FAIL=1
fi

# Check the notarization ticket is valid
if [[ -d "$APP" ]]; then
    STAPLER_LOG=$(mktmp)
    set +e
    xcrun stapler validate "$APP" >"$STAPLER_LOG" 2>&1
    STAPLER_EXIT=$?
    set -e
    if (( STAPLER_EXIT == 0 )); then
        echo "  ✓ stapler validate passes"
    else
        warn "stapler validate failed — run ./notarizer.sh first"
        cat "$STAPLER_LOG" >&2
        PREFLIGHT_FAIL=1
    fi
fi

# Read version from Info.plist
VERSION=""
if [[ -f "$INFO_PLIST" ]]; then
    set +e
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null)
    VERSION_EXIT=$?
    set -e
    if (( VERSION_EXIT == 0 )) && [[ -n "$VERSION" ]]; then
        echo "  ✓ Version: $VERSION"
    else
        warn "Could not read CFBundleShortVersionString from $INFO_PLIST"
        PREFLIGHT_FAIL=1
        VERSION=""
    fi
fi

if (( PREFLIGHT_FAIL == 0 )); then
    S_PREFLIGHT="pass"; D_PREFLIGHT="all prerequisites ready (v$VERSION)"
else
    S_PREFLIGHT="fail"; D_PREFLIGHT="missing prerequisites (see above)"
fi

# ── Create DMG ────────────────────────────────────────────────────────────────
DMG_PATH=""
if [[ $S_PREFLIGHT == "pass" ]]; then
    step "Create DMG"
    DMG_PATH="$REPO/build/yowee-$VERSION.dmg"
    DMG_LOG=$(mktmp)
    # create-dmg refuses to overwrite an existing file
    rm -f "$DMG_PATH"
    set +e
    create-dmg \
        --volname "yowee" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "yowee.app" 175 190 \
        --hide-extension "yowee.app" \
        --app-drop-link 425 190 \
        "$DMG_PATH" \
        "$APP" \
        > "$DMG_LOG" 2>&1
    DMG_EXIT=$?
    set -e

    if (( DMG_EXIT == 0 )) && [[ -f "$DMG_PATH" ]]; then
        DMG_SIZE=$(du -h "$DMG_PATH" | awk '{print $1}')
        echo "  ✓ Created $DMG_PATH ($DMG_SIZE)"
        S_DMG="pass"; D_DMG="$DMG_SIZE → $(basename "$DMG_PATH")"
    else
        warn "create-dmg failed:"
        cat "$DMG_LOG" >&2
        S_DMG="fail"; D_DMG="create-dmg failed"
    fi
fi

# ── SHA256 ────────────────────────────────────────────────────────────────────
DMG_SHA256=""
if [[ $S_DMG == "pass" ]]; then
    step "Compute SHA256"
    set +e
    SHA_LINE=$(shasum -a 256 "$DMG_PATH" 2>/dev/null)
    SHA_EXIT=$?
    set -e
    if (( SHA_EXIT == 0 )) && [[ -n "$SHA_LINE" ]]; then
        DMG_SHA256=$(echo "$SHA_LINE" | awk '{print $1}')
        echo "  ✓ sha256: $DMG_SHA256"
        S_SHA="pass"; D_SHA="${DMG_SHA256:0:16}…"
    else
        warn "shasum failed for $DMG_PATH"
        S_SHA="fail"; D_SHA="shasum failed"
    fi
fi

# ── GitHub Release ────────────────────────────────────────────────────────────
RELEASE_URL=""
RELEASE_TAG=""
DMG_ASSET_URL=""
if [[ $S_SHA == "pass" ]]; then
    step "GitHub Release"
    RELEASE_TAG="v$VERSION"
    DMG_ASSET_URL="https://github.com/$APP_REPO/releases/download/$RELEASE_TAG/$(basename "$DMG_PATH")"

    # Probe whether the release already exists
    set +e
    EXISTING=$(gh release view "$RELEASE_TAG" --repo "$APP_REPO" --json url --jq .url 2>/dev/null)
    EXISTS_EXIT=$?
    set -e

    if (( EXISTS_EXIT == 0 )) && [[ -n "$EXISTING" ]]; then
        warn "Release $RELEASE_TAG already exists at $EXISTING — skipping (will not overwrite)"
        RELEASE_URL="$EXISTING"
        S_RELEASE="warn"; D_RELEASE="skipped — $RELEASE_TAG already exists"
    else
        REL_LOG=$(mktmp)
        set +e
        gh release create "$RELEASE_TAG" \
            --repo "$APP_REPO" \
            --title "yowee $RELEASE_TAG" \
            --notes "Release $RELEASE_TAG" \
            "$DMG_PATH" \
            > "$REL_LOG" 2>&1
        REL_EXIT=$?
        set -e

        if (( REL_EXIT == 0 )); then
            # gh release create prints the release URL on stdout
            RELEASE_URL=$(grep -E "^https://github.com/.*/releases/tag/" "$REL_LOG" | head -1 || true)
            [[ -z "$RELEASE_URL" ]] && RELEASE_URL="https://github.com/$APP_REPO/releases/tag/$RELEASE_TAG"
            echo "  ✓ Released $RELEASE_TAG"
            echo "    $RELEASE_URL"
            S_RELEASE="pass"; D_RELEASE="$RELEASE_TAG published"
        else
            warn "gh release create failed:"
            cat "$REL_LOG" >&2
            S_RELEASE="fail"; D_RELEASE="gh release create failed"
        fi
    fi
fi

# ── Update tap formula ────────────────────────────────────────────────────────
if [[ $S_RELEASE == "pass" || $S_RELEASE == "warn" ]]; then
    step "Update Homebrew tap"
    TAP_DIR=$(mktmpdir)

    # Try to clone the tap. If it doesn't exist, create it then clone.
    CLONE_LOG=$(mktmp)
    set +e
    git clone "$TAP_REPO_SSH" "$TAP_DIR" > "$CLONE_LOG" 2>&1
    CLONE_EXIT=$?
    set -e

    if (( CLONE_EXIT != 0 )); then
        warn "Tap repo clone failed — attempting to create $TAP_REPO"
        cat "$CLONE_LOG" >&2

        CREATE_LOG=$(mktmp)
        set +e
        gh repo create "$TAP_REPO" --public \
            --description "Homebrew tap for yowee" \
            > "$CREATE_LOG" 2>&1
        CREATE_EXIT=$?
        set -e

        if (( CREATE_EXIT != 0 )); then
            warn "gh repo create failed:"
            cat "$CREATE_LOG" >&2
            S_TAP="fail"; D_TAP="could not create or clone tap repo"
        else
            echo "  ✓ Created $TAP_REPO"
            # Re-clone after creation
            rm -rf "$TAP_DIR"
            TAP_DIR=$(mktmpdir)
            CLONE2_LOG=$(mktmp)
            set +e
            git clone "$TAP_REPO_SSH" "$TAP_DIR" > "$CLONE2_LOG" 2>&1
            CLONE2_EXIT=$?
            set -e
            if (( CLONE2_EXIT != 0 )); then
                warn "Re-clone failed after repo creation:"
                cat "$CLONE2_LOG" >&2
                S_TAP="fail"; D_TAP="clone failed after repo create"
            fi
        fi
    fi

    # Proceed only if we have a working clone
    if [[ -d "$TAP_DIR/.git" ]]; then
        echo "  ✓ Cloned $TAP_REPO"
        mkdir -p "$TAP_DIR/Casks"
        CASK_FILE="$TAP_DIR/Casks/$CASK_NAME.rb"

        # Heredoc with quoted delimiter — no expansion. The cask uses Ruby's
        # `#{version}` interpolation at install time, so we want literal `#{version}`
        # in the file, not shell-expanded.
        cat > "$CASK_FILE" <<EOF
cask "yowee" do
  version "$VERSION"
  sha256 "$DMG_SHA256"

  url "https://github.com/thingsplode/yowee/releases/download/v#{version}/yowee-#{version}.dmg"
  name "yowee"
  desc "Menu bar LLM pipeline — select text, press ⌥Space, get results"
  homepage "https://github.com/thingsplode/yowee"

  app "yowee.app"

  postflight do
    system_command "/usr/bin/open",
                   args: ["-a", "System Preferences",
                           "--args", "com.apple.preference.security"]
  end

  zap trash: [
    "~/.config/yowee",
  ]
end
EOF

        echo "  ✓ Wrote Casks/$CASK_NAME.rb"

        # Stage, commit, push
        TAP_LOG=$(mktmp)
        set +e
        git -C "$TAP_DIR" add "Casks/$CASK_NAME.rb" > "$TAP_LOG" 2>&1
        ADD_EXIT=$?
        set -e
        if (( ADD_EXIT != 0 )); then
            warn "git add failed:"
            cat "$TAP_LOG" >&2
            S_TAP="fail"; D_TAP="git add failed"
        fi

        # If there are no changes (e.g. re-running for the same version), skip commit
        if [[ $S_TAP != "fail" ]]; then
            set +e
            git -C "$TAP_DIR" diff --cached --quiet
            HAS_CHANGES=$?  # 1 = changes staged, 0 = nothing staged
            set -e

            if (( HAS_CHANGES == 0 )); then
                warn "No changes to commit in tap (formula already matches $VERSION)"
                S_TAP="warn"; D_TAP="no changes — already at $VERSION"
            else
                COMMIT_LOG=$(mktmp)
                set +e
                git -C "$TAP_DIR" \
                    -c user.email="$GIT_EMAIL" \
                    commit -m "yowee v$VERSION" > "$COMMIT_LOG" 2>&1
                COMMIT_EXIT=$?
                set -e
                if (( COMMIT_EXIT != 0 )); then
                    warn "git commit failed:"
                    cat "$COMMIT_LOG" >&2
                    S_TAP="fail"; D_TAP="git commit failed"
                else
                    echo "  ✓ Committed yowee v$VERSION"
                    PUSH_LOG=$(mktmp)
                    set +e
                    git -C "$TAP_DIR" push > "$PUSH_LOG" 2>&1
                    PUSH_EXIT=$?
                    set -e
                    if (( PUSH_EXIT != 0 )); then
                        warn "git push failed:"
                        cat "$PUSH_LOG" >&2
                        S_TAP="fail"; D_TAP="git push failed"
                    else
                        echo "  ✓ Pushed to $TAP_REPO"
                        S_TAP="pass"; D_TAP="formula updated to $VERSION"
                    fi
                fi
            fi
        fi
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

echo "  Publication pipeline"
echo "$SEP"
row "Preflight"     $S_PREFLIGHT "$D_PREFLIGHT"
row "Create DMG"    $S_DMG       "$D_DMG"
row "SHA256"        $S_SHA       "$D_SHA"
row "GitHub Release" $S_RELEASE  "$D_RELEASE"
row "Tap update"    $S_TAP       "$D_TAP"

echo "$DIV"

if [[ $S_TAP == "pass" || $S_TAP == "warn" ]]; then
    echo ""
    [[ -n "$DMG_PATH"     ]] && echo "  DMG:       $DMG_PATH"
    [[ -n "$DMG_SHA256"   ]] && echo "  SHA256:    $DMG_SHA256"
    [[ -n "$RELEASE_URL"  ]] && echo "  Release:   $RELEASE_URL"
    [[ -n "$DMG_ASSET_URL" ]] && echo "  Asset URL: $DMG_ASSET_URL"
    echo ""
    echo "  Install with:"
    echo "    brew install --cask $GH_USER/$CASK_NAME/$CASK_NAME"
fi

[[ $S_PREFLIGHT == "fail" \
    || $S_DMG     == "fail" \
    || $S_SHA     == "fail" \
    || $S_RELEASE == "fail" \
    || $S_TAP     == "fail" ]] && exit 1
exit 0
