#!/bin/bash
# Usage: ./build_run.sh [--fast] [--no-test] [--no-launch]
#   --fast       skip static analysis and coverage (local quick iteration)
#   --no-test    skip unit tests
#   --no-launch  build only, don't open the app

set -e

REPO="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Desktop/yowee.app"
DERIVED="$HOME/Library/Developer/Xcode/DerivedData/yowee-build"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
XCBUILD="DEVELOPER_DIR=$DEVELOPER_DIR xcodebuild -scheme yowee -destination platform=macOS,arch=arm64 -derivedDataPath $DERIVED"

FAST=0; SKIP_TEST=0; SKIP_LAUNCH=0
for arg in "$@"; do
    case $arg in
        --fast)      FAST=1 ;;
        --no-test)   SKIP_TEST=1 ;;
        --no-launch) SKIP_LAUNCH=1 ;;
    esac
done

# ── Summary state ─────────────────────────────────────────────────────────────
# Dependencies
S_BREW="skip";      D_BREW="skipped"
S_SWIFTLINT="skip"; D_SWIFTLINT="skipped"
S_SWIFTFMT="skip";  D_SWIFTFMT="skipped"
S_PERIPHERY="skip"; D_PERIPHERY="skipped"
S_OLLAMA="skip";    D_OLLAMA="skipped"
# Analysis
S_LINT="skip";      D_LINT="skipped"
S_FORMAT="skip";    D_FORMAT="skipped"
S_TEST="skip";      D_TEST="skipped"
S_ANALYZE="skip";   D_ANALYZE="skipped"
S_DEAD="skip";      D_DEAD="skipped"
S_BUILD="skip";     D_BUILD="skipped"
S_COVERAGE="skip";  D_COVERAGE="skipped"

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

# gcount PATTERN FILE — always outputs a plain integer; never "0\n0".
# grep -c exits 1 on zero matches but still prints "0"; the || true prevents
# set -e from aborting while leaving the captured value intact.
gcount() { local n; n=$(grep -c "$@" 2>/dev/null) || n=0; echo "$n"; }

# check_dep NAME VER_CMD BREW_PKG
#   Checks if a CLI tool is installed. Offers `brew install BREW_PKG` if not.
#   Sets globals LAST_STATUS and LAST_DETAIL.
LAST_STATUS=""; LAST_DETAIL=""
check_dep() {
    local name="$1" ver_cmd="$2" brew_pkg="$3"
    # Extract the binary name (first word) and test with command -v so the
    # result isn't masked by a trailing `| head -1` which always exits 0.
    local binary ver
    binary=$(echo "$ver_cmd" | awk '{print $1}')
    _try_dep() {
        command -v "$binary" &>/dev/null && ver=$(eval "$ver_cmd" 2>/dev/null | head -1) && [[ -n "$ver" ]]
    }
    if _try_dep; then
        printf "  ✓ %-18s %s\n" "$name" "$ver"
        LAST_STATUS="pass"; LAST_DETAIL="$ver"
    else
        printf "  ? %-18s not installed\n" "$name"
        if [[ -n "$brew_pkg" ]]; then
            read -r -p "    brew install $brew_pkg? [Y/n] " reply
            if [[ "${reply:-Y}" =~ ^[Yy]$ ]]; then
                brew install $brew_pkg
                if _try_dep; then
                    printf "  ✓ %-18s %s\n" "$name" "$ver"
                    LAST_STATUS="pass"; LAST_DETAIL="$ver"
                else
                    warn "$name install failed"
                    LAST_STATUS="fail"; LAST_DETAIL="install failed"
                fi
            else
                LAST_STATUS="miss"; LAST_DETAIL="not installed"
            fi
        else
            LAST_STATUS="miss"; LAST_DETAIL="not installed  →  install manually"
        fi
    fi
}

# check_service NAME INSTALLED_CMD HEALTH_URL BREW_PKG START_CMD
#   Checks if a service is installed and reachable. Offers to install/start.
#   Sets globals LAST_STATUS and LAST_DETAIL.
check_service() {
    local name="$1" installed_cmd="$2" health_url="$3" brew_pkg="$4" start_cmd="$5"
    if ! eval "$installed_cmd" &>/dev/null; then
        printf "  ? %-18s not installed\n" "$name"
        read -r -p "    brew install $brew_pkg? [Y/n] " reply
        if [[ "${reply:-Y}" =~ ^[Yy]$ ]]; then
            brew install "$brew_pkg"
        else
            LAST_STATUS="miss"; LAST_DETAIL="not installed"
            return
        fi
    fi
    local ver
    ver=$(eval "$installed_cmd" 2>/dev/null | head -1 || echo "")
    if curl -sf "$health_url" &>/dev/null; then
        local extra=""
        # For Ollama: show model count
        if [[ "$health_url" == *"api/tags"* ]]; then
            extra=$(curl -sf "$health_url" 2>/dev/null \
                | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('models',[])), 'models')" 2>/dev/null || true)
            [[ -n "$extra" ]] && extra=" ($extra)"
        fi
        printf "  ✓ %-18s %s — running%s\n" "$name" "$ver" "$extra"
        LAST_STATUS="pass"; LAST_DETAIL="$ver — running$extra"
    else
        printf "  ○ %-18s %s — not running\n" "$name" "$ver"
        read -r -p "    Start $name now? [Y/n] " reply
        if [[ "${reply:-Y}" =~ ^[Yy]$ ]]; then
            eval "$start_cmd"
            sleep 1
            if curl -sf "$health_url" &>/dev/null; then
                printf "  ✓ %-18s started\n" "$name"
                LAST_STATUS="pass"; LAST_DETAIL="$ver — started"
            else
                warn "$name did not respond after start"
                LAST_STATUS="warn"; LAST_DETAIL="$ver — start may have failed"
            fi
        else
            LAST_STATUS="warn"; LAST_DETAIL="$ver — not running (Ollama pipeline steps will fail)"
        fi
    fi
}

# run_xcodebuild ARGS
#   Streams filtered xcodebuild output. Detects the DVTDownloads plugin
#   mismatch, offers the one-time fix, retries once.
#   Sets global XCODE_LOG (caller must rm).
XCODE_LOG=""
run_xcodebuild() {
    XCODE_LOG=$(mktemp)
    local exit_code=0
    eval "$XCBUILD $* 2>&1" | tee "$XCODE_LOG" | grep -E "error:|warning:|BUILD " || true
    if ! grep -q "SUCCEEDED" "$XCODE_LOG"; then
        exit_code=1
        if grep -q "runFirstLaunch" "$XCODE_LOG"; then
            warn "Xcode plugins out of sync (DVTDownloads mismatch)."
            echo "  Fix: sudo xcodebuild -runFirstLaunch"
            read -r -p "  Run it now? (requires sudo) [Y/n] " reply
            if [[ "${reply:-Y}" =~ ^[Yy]$ ]]; then
                sudo xcodebuild -runFirstLaunch
                echo "  → Retrying…"
                rm -f "$XCODE_LOG"; XCODE_LOG=$(mktemp); exit_code=0
                eval "$XCBUILD $* 2>&1" | tee "$XCODE_LOG" | grep -E "error:|warning:|BUILD " || true
                grep -q "SUCCEEDED" "$XCODE_LOG" || exit_code=1
            fi
        fi
        if [[ $exit_code -ne 0 ]]; then
            warn "Step failed. Full log:"
            cat "$XCODE_LOG" >&2
        fi
    fi
    return $exit_code
}

# ── Preflight: Xcode plugin health ───────────────────────────────────────────
step "Preflight"
if DEVELOPER_DIR=$DEVELOPER_DIR xcodebuild -version 2>&1 | grep -q "runFirstLaunch"; then
    warn "Xcode plugins are out of sync."
    read -r -p "  Run 'sudo xcodebuild -runFirstLaunch' now? [Y/n] " reply
    [[ "${reply:-Y}" =~ ^[Yy]$ ]] && sudo xcodebuild -runFirstLaunch
fi
echo "  Xcode: $(DEVELOPER_DIR=$DEVELOPER_DIR xcodebuild -version 2>/dev/null | head -1)"

# ── Dependencies & services ───────────────────────────────────────────────────
step "Dependencies & services"

check_dep "Homebrew" "brew --version" ""
S_BREW=$LAST_STATUS; D_BREW=$LAST_DETAIL

check_dep "SwiftLint" "swiftlint version" "swiftlint"
S_SWIFTLINT=$LAST_STATUS; D_SWIFTLINT=$LAST_DETAIL

check_dep "SwiftFormat" "swiftformat --version" "swiftformat"
S_SWIFTFMT=$LAST_STATUS; D_SWIFTFMT=$LAST_DETAIL

check_dep "Periphery" "periphery version" "peripheryapp/periphery/periphery"
S_PERIPHERY=$LAST_STATUS; D_PERIPHERY=$LAST_DETAIL

check_service "Ollama" \
    "command -v ollama" \
    "http://localhost:11434/api/tags" \
    "ollama" \
    "brew services start ollama"
S_OLLAMA=$LAST_STATUS; D_OLLAMA=$LAST_DETAIL

# ── SwiftLint ─────────────────────────────────────────────────────────────────
step "SwiftLint"
if command -v swiftlint &>/dev/null; then
    LINT_OUT=$(mktemp)
    swiftlint lint --quiet --config "$REPO/.swiftlint.yml" 2>/dev/null \
        > "$LINT_OUT" || swiftlint lint --quiet > "$LINT_OUT" 2>/dev/null || true
    ERRORS=$(gcount ": error:"   "$LINT_OUT")
    WARNS=$(gcount  ": warning:" "$LINT_OUT")
    [[ $(wc -l < "$LINT_OUT") -gt 0 ]] && cat "$LINT_OUT"
    rm -f "$LINT_OUT"
    if   [[ $ERRORS -gt 0 ]]; then S_LINT="fail"; D_LINT="$ERRORS errors, $WARNS warnings"
    elif [[ $WARNS  -gt 0 ]]; then S_LINT="warn"; D_LINT="0 errors, $WARNS warnings"
    else                            S_LINT="pass"; D_LINT="0 issues"
    fi
else
    echo "  skipped (not installed)"
    S_LINT="skip"; D_LINT="not installed"
fi

# ── SwiftFormat ───────────────────────────────────────────────────────────────
step "SwiftFormat"
if command -v swiftformat &>/dev/null; then
    FORMAT_OUT=$(mktemp)
    swiftformat --lint "$REPO/Sources" 2>&1 | tee "$FORMAT_OUT" || true
    REFORMAT=$(gcount "would reformat" "$FORMAT_OUT")
    rm -f "$FORMAT_OUT"
    if [[ $REFORMAT -gt 0 ]]; then S_FORMAT="warn"; D_FORMAT="$REFORMAT file(s) need formatting  →  swiftformat Sources"
    else                            S_FORMAT="pass"; D_FORMAT="all files clean"
    fi
else
    echo "  skipped (not installed)"
    S_FORMAT="skip"; D_FORMAT="not installed"
fi

# ── Unit tests ────────────────────────────────────────────────────────────────
step "Unit tests"
if [[ $SKIP_TEST -eq 0 ]]; then
    cd "$REPO"
    TEST_OUT=$(mktemp)
    swift run TestRunner 2>&1 | tee "$TEST_OUT"
    SUMMARY_LINE=$(grep "Test run with" "$TEST_OUT" | tail -1)
    TOTAL_T=$(echo "$SUMMARY_LINE" | grep -oE '[0-9]+ tests'  | grep -oE '[0-9]+' || echo "?")
    SUITES=$(echo  "$SUMMARY_LINE" | grep -oE '[0-9]+ suites' | grep -oE '[0-9]+' || echo "?")
    FAILED=$(gcount " failed" "$TEST_OUT")
    rm -f "$TEST_OUT"
    if [[ $FAILED -gt 0 ]]; then S_TEST="fail"; D_TEST="$FAILED failed"
    else                          S_TEST="pass"; D_TEST="$TOTAL_T tests passed  ($SUITES suites)"
    fi
else
    echo "  skipped (--no-test)"
    S_TEST="skip"; D_TEST="--no-test"
fi

# ── Static analysis ───────────────────────────────────────────────────────────
step "Static analysis  (xcodebuild analyze)"
if [[ $FAST -eq 0 ]]; then
    if run_xcodebuild "analyze"; then
        ANA_ERRORS=$(gcount "error:"   "$XCODE_LOG")
        ANA_WARNS=$(gcount  "warning:" "$XCODE_LOG")
        rm -f "$XCODE_LOG"
        if   [[ $ANA_ERRORS -gt 0 ]]; then S_ANALYZE="fail"; D_ANALYZE="$ANA_ERRORS errors, $ANA_WARNS warnings"
        elif [[ $ANA_WARNS  -gt 0 ]]; then S_ANALYZE="warn"; D_ANALYZE="0 errors, $ANA_WARNS warnings"
        else                                S_ANALYZE="pass"; D_ANALYZE="0 issues"
        fi
    else
        rm -f "$XCODE_LOG"
        S_ANALYZE="fail"; D_ANALYZE="analysis step failed"
    fi
else
    echo "  skipped (--fast)"
    S_ANALYZE="skip"; D_ANALYZE="--fast"
fi

# ── Periphery (dead code) ─────────────────────────────────────────────────────
step "Periphery  (dead code)"
if [[ $FAST -eq 0 ]]; then
    if command -v periphery &>/dev/null; then
        PERI_OUT=$(mktemp)
        periphery scan 2>&1 | tee "$PERI_OUT" || true
        UNUSED=$(gcount -E "warning:|error:" "$PERI_OUT")
        rm -f "$PERI_OUT"
        if [[ $UNUSED -gt 0 ]]; then S_DEAD="warn"; D_DEAD="$UNUSED unused declaration(s)"
        else                          S_DEAD="pass"; D_DEAD="no unused declarations"
        fi
    else
        echo "  skipped (not installed)"
        S_DEAD="skip"; D_DEAD="not installed"
    fi
else
    echo "  skipped (--fast)"
    S_DEAD="skip"; D_DEAD="--fast"
fi

# ── Build ─────────────────────────────────────────────────────────────────────
step "Build"
if run_xcodebuild "build"; then
    rm -f "$XCODE_LOG"
    S_BUILD="pass"; D_BUILD="succeeded"
else
    rm -f "$XCODE_LOG"
    S_BUILD="fail"; D_BUILD="FAILED"
fi

# ── Test coverage ─────────────────────────────────────────────────────────────
step "Test coverage"
if [[ $FAST -eq 0 ]]; then
    RESULT_BUNDLE="/tmp/yowee-coverage.xcresult"
    rm -rf "$RESULT_BUNDLE"
    if run_xcodebuild "test -enableCodeCoverage YES -resultBundlePath $RESULT_BUNDLE"; then
        rm -f "$XCODE_LOG"
        COV_REPORT=$(xcrun xccov view --report "$RESULT_BUNDLE" 2>/dev/null || true)
        echo ""
        echo "  Files below 100% (lowest first):"
        echo "$COV_REPORT" \
            | grep -E "\.swift\s+[0-9]" | grep -v "100\.00%" \
            | awk '{printf "    %-55s %s\n", $1, $(NF-1)}' \
            | sort -t'%' -k1 -n | head -20
        # Top-level line is "YoweeTests  92.43% (N/M)" — percentage is $(NF-1)
        TOTAL_COV=$(echo "$COV_REPORT" | grep -E "^YoweeTests\s" | awk '{print $(NF-1)}' || true)
        LOWEST_FILE=$(echo "$COV_REPORT" \
            | grep -E "\.swift\s+[0-9]" | grep -v "100\.00%" \
            | awk '{print $(NF-1), $1}' | sort -n | head -1 | awk '{print $2}' \
            | xargs basename 2>/dev/null || true)
        LOWEST_PCT=$(echo "$COV_REPORT" \
            | grep -E "\.swift\s+[0-9]" | grep -v "100\.00%" \
            | awk '{print $(NF-1)}' | sort -n | head -1 || true)
        if [[ -n "$TOTAL_COV" ]]; then
            S_COVERAGE="pass"; D_COVERAGE="$TOTAL_COV overall"
            [[ -n "$LOWEST_FILE" ]] && D_COVERAGE="$TOTAL_COV overall  (lowest: $LOWEST_FILE $LOWEST_PCT)"
        else
            S_COVERAGE="warn"; D_COVERAGE="could not parse coverage report"
        fi
    else
        # Extract failed test names before discarding the log
        FAILED_TESTS=$(grep -E "failed|✗" "$XCODE_LOG" 2>/dev/null \
            | grep -v "BUILD\|Executed\|testing" \
            | sed 's/.*Test Case.*\[\(.*\)\].*/  \1/' \
            | sed 's/.*✗ Test \(.*\) failed.*/  \1/' \
            | grep -v "^$" | head -10 || true)
        FAIL_COUNT=$(gcount -E "Test Case.*failed|✗ Test.*failed" "$XCODE_LOG")
        rm -f "$XCODE_LOG"
        if [[ -n "$FAILED_TESTS" ]]; then
            echo ""
            echo "  Failed tests:"
            echo "$FAILED_TESTS"
            D_COVERAGE="$FAIL_COUNT test(s) failed"
        else
            D_COVERAGE="test run failed (see log above)"
        fi
        S_COVERAGE="fail"
    fi
else
    echo "  skipped (--fast)"
    S_COVERAGE="skip"; D_COVERAGE="--fast"
fi

# ── Assemble + sign ───────────────────────────────────────────────────────────
if [[ $S_BUILD == "pass" ]]; then
    step "Assemble + sign"
    BINARY="$DERIVED/Build/Products/Debug/yowee"
    pkill -f "yowee.app/Contents/MacOS/yowee" 2>/dev/null || true
    sleep 0.3
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp "$BINARY" "$APP/Contents/MacOS/yowee"
    cp "$REPO/Info.plist" "$APP/Contents/Info.plist"
    codesign --force --deep --sign - "$APP"
    echo "  Signed: $APP"
fi

# ── Launch ────────────────────────────────────────────────────────────────────
if [[ $SKIP_LAUNCH -eq 0 && $S_BUILD == "pass" ]]; then
    step "Launch"
    open "$APP"
fi

# ── Summary table ─────────────────────────────────────────────────────────────
DIV="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SEP="  ────────────────────────────────────────────────────────────────────────"
row() { printf "  %-22s %s  %s\n" "$1" "$(icon $2)" "$3"; }

echo ""
echo "$DIV"
printf "  %-22s %-4s %s\n" "Step" "" "Details"
echo "$DIV"

echo "  Dependencies & services"
echo "$SEP"
row "Homebrew"       $S_BREW      "$D_BREW"
row "SwiftLint"      $S_SWIFTLINT "$D_SWIFTLINT"
row "SwiftFormat"    $S_SWIFTFMT  "$D_SWIFTFMT"
row "Periphery"      $S_PERIPHERY "$D_PERIPHERY"
row "Ollama"         $S_OLLAMA    "$D_OLLAMA"

echo ""
echo "  Analysis"
echo "$SEP"
row "SwiftLint"      $S_LINT     "$D_LINT"
row "SwiftFormat"    $S_FORMAT   "$D_FORMAT"
row "Unit tests"     $S_TEST     "$D_TEST"
row "Static analysis" $S_ANALYZE "$D_ANALYZE"
row "Periphery"      $S_DEAD     "$D_DEAD"
row "Build"          $S_BUILD    "$D_BUILD"
row "Coverage"       $S_COVERAGE "$D_COVERAGE"

echo "$DIV"

# Hard-fail on build, test, or analysis errors (warnings are non-blocking)
[[ $S_BUILD == "fail" || $S_TEST == "fail" || $S_ANALYZE == "fail" ]] && exit 1
exit 0
