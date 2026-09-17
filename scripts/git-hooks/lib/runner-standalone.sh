#!/usr/bin/env bash
# runner-standalone.sh — the pre-commit gate of a botopink library.
#
# Sourced by scripts/git-hooks/pre-commit. It is the only runner: it needs
# nothing outside this repository (standalone clone, meta checkout, worktree,
# bpmp packing). Stages: conflict markers in staged files, `botopink test`,
# then `botopink build` of every example (runExamplesGate — CI calls it too).
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

    # 3. every example builds, unless listed as known broken.
    runExamplesGate "$bin"
}

# runExamplesGate <botopink-bin>
#
# Builds every `examples/*/` that has a `botopink.json` (each with its own
# manifest target, into a throwaway --out). `scripts/known-broken-examples.txt`
# lists the examples allowed to fail — one `examples/<name>  <reason>` per
# line, `#` comments. The list cannot rot: a listed example that builds, or a
# listed path that no longer exists, fails the gate too.
runExamplesGate() {
    local bin="$1"
    local root
    root=$(git rev-parse --show-toplevel)
    local list="$root/scripts/known-broken-examples.txt"
    local known=""
    if [ -f "$list" ]; then
        # awk, not `grep -v | awk`: a list of only comments or blank lines has
        # no entry, and grep's "no match" exit 1 would abort under pipefail.
        # An unreadable list still fails (awk exits non-zero).
        known=$(awk '!/^[[:space:]]*(#|$)/ {print $1}' "$list")
    fi
    local k
    for k in $known; do
        [ -f "$root/$k/botopink.json" ] || fail "$list names $k, which has no botopink.json — delete its line"
    done
    local dir name rel out bad=""
    for dir in "$root"/examples/*/; do
        [ -f "$dir/botopink.json" ] || continue
        name=$(basename "$dir")
        rel="examples/$name"
        out=$(mktemp -d)
        echo -n "  Building $rel (botopink build)... "
        if ( cd "$dir" && "$bin" build --out "$out" ) >/dev/null 2>&1; then
            if printf '%s\n' "$known" | grep -qx "$rel"; then
                echo -e "${RED}✗${NC}"
                bad="$bad\n  $rel builds but is listed in scripts/known-broken-examples.txt — delete its line"
            else
                echo -e "${GREEN}✓${NC}"
            fi
        else
            if printf '%s\n' "$known" | grep -qx "$rel"; then
                echo -e "${YELLOW}known broken${NC}"
            else
                echo -e "${RED}✗${NC}"
                bad="$bad\n  $rel does not build — re-run: ( cd $dir && $bin build --out \$(mktemp -d) )"
            fi
        fi
        rm -rf "$out"
    done
    if [ -n "$bad" ]; then
        echo -e "$bad"
        fail "$(basename "$root"): examples gate failed"
    fi
}
