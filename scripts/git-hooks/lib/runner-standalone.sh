#!/usr/bin/env bash
# runner-standalone.sh — pre-commit gate for a standalone clone of this .bp lib.
#
# Self-contained mirror of botopink/projects'
# scripts/git-hooks/lib/runners/bp-lib.sh — it has to run without the meta
# workspace nearby (lib's own CI, partial checkout, bpmp packing).
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }
pass() { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }

locateBotopink() {
    if [ -n "${BOTOPINK_BIN:-}" ] && [ -x "$BOTOPINK_BIN" ]; then
        echo "$BOTOPINK_BIN"; return 0
    fi
    local cur; cur=$(pwd)
    while [ "$cur" != "/" ]; do
        local cand="$cur/repository/botopink-lang/zig-out/bin/botopink"
        [ -x "$cand" ] && { echo "$cand"; return 0; }
        cand="$cur/zig-out/bin/botopink"
        [ -x "$cand" ] && [ -f "$cur/build.zig" ] && { echo "$cand"; return 0; }
        cur=$(dirname "$cur")
    done
    command -v botopink >/dev/null 2>&1 && { command -v botopink; return 0; }
    return 1
}

runStandaloneGate() {
    local root
    root=$(git rev-parse --show-toplevel)
    cd "$root"

    # 1. conflict markers in staged files (regular files only — gitlinks skipped).
    local lt7 eq7 gt7
    lt7=$(printf '<%.0s' {1..7})
    eq7=$(printf '=%.0s' {1..7})
    gt7=$(printf '>%.0s' {1..7})
    local marker_re="${lt7} |${eq7}\$|${gt7} "
    local staged
    staged=$(git diff --cached --name-only --diff-filter=ACM)
    if [ -n "$staged" ]; then
        local hits=""
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            [ -f "$f" ] || continue
            if grep -nE "$marker_re" "$f" 2>/dev/null | head -1 | grep -q .; then
                hits="$hits $f"
            fi
        done <<< "$staged"
        if [ -n "$hits" ]; then
            echo "  Conflict markers in:$hits"
            fail "Conflict markers found in staged files"
        fi
        pass "No conflict markers"
    fi

    # 2. botopink test.
    if [ -z "$(find src test 2>/dev/null -name '*.bp' ! -name '*.d.bp' | head -1)" ]; then
        echo "  (no .bp sources under src/ or test/ — nothing to test)"
        return 0
    fi
    local bin
    if ! bin=$(locateBotopink); then
        warn "botopink binary not found (env BOTOPINK_BIN, ancestor zig-out/bin, or \$PATH) — skipping .bp gate"
        return 0
    fi
    echo -n "  Testing $(basename "$root") (botopink test)... "
    if ( cd "$root" && "$bin" test ) >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        echo
        echo "  Re-run for failure output:  ( cd $root && $bin test )"
        fail "$(basename "$root"): botopink test failed"
    fi
}
