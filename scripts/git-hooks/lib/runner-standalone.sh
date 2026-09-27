#!/usr/bin/env bash
# runner-standalone.sh — the pre-commit gate of a botopink library.
#
# Sourced by scripts/git-hooks/pre-commit. It is the only runner: it needs
# nothing outside this repository (standalone clone, meta checkout, worktree,
# bpmp packing). Stages: staged files (no conflict markers, no snapshot
# candidate — `*.snap.new` / `*.snap.md.new` is recorded by renaming it, never
# committed), `botopink test` (per member under modules/*/ when the root
# botopink.json is a workspace — decision 75: the umbrella compiles nothing and
# `botopink test` there is a refusal — else over the package's own src/ +
# test/), `botopink build` of every example (runExamplesGate — CI calls it
# too), then every refusals/*/ case (runRefusalsGate).
#
# Fail beats warn (1.0.11-beta 00-gate, gate-i): a compiler that cannot be
# found is a failed gate, not a skipped one, and no list names an example
# that may fail — an example that does not build fails the commit.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }
pass() { echo -e "${GREEN}✓ $1${NC}"; }

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

# requireBotopink — locateBotopink, or the failed gate with the way out
# (called as `bin=$(requireBotopink)`: the path is stdout, the refusal stderr,
# and the non-zero status ends the sourcing shell under `set -e`).
requireBotopink() {
    local bin
    if ! bin=$(locateBotopink); then
        {
            echo "  botopink binary not found: set BOTOPINK_BIN to a built compiler, or build one with"
            echo "  \`zig build install\` in a botopink-lang checkout (an ancestor's repository/botopink-lang/,"
            echo "  or any checkout on \$PATH)."
            echo -e "${RED}✗ no compiler — the .bp gate cannot run, so the commit is refused${NC}"
        } >&2
        return 1
    fi
    echo "$bin"
}

runStandaloneGate() {
    local root
    root=$(git rev-parse --show-toplevel)
    cd "$root"

    # 1. staged files: no snapshot candidate, no conflict marker (regular
    #    files only — gitlinks skipped). A `*.snap.new` / `*.snap.md.new` is
    #    written by a mismatch or a missing snapshot and recorded by renaming
    #    it after it was compared with the spec's literal; the candidate itself
    #    is never committed, `.gitignore` or not (`git add -f` gets past that).
    local lt7 eq7 gt7
    lt7=$(printf '<%.0s' {1..7})
    eq7=$(printf '=%.0s' {1..7})
    gt7=$(printf '>%.0s' {1..7})
    local marker_re="${lt7} |${eq7}\$|${gt7} "
    local staged
    staged=$(git diff --cached --name-only --diff-filter=ACMR)
    if [ -n "$staged" ]; then
        local hits="" candidates=""
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            case "$f" in
                *.snap.new|*.snap.md.new) candidates="$candidates $f" ;;
            esac
            [ -f "$f" ] || continue
            if grep -nE "$marker_re" "$f" 2>/dev/null | head -1 | grep -q .; then
                hits="$hits $f"
            fi
        done <<< "$staged"
        if [ -n "$candidates" ]; then
            echo "  Snapshot candidates staged:$candidates"
            echo "  Compare each with the spec's literal and record it by renaming (mv x.snap.new x.snap); never commit the candidate."
            fail "Snapshot candidate (*.snap.new / *.snap.md.new) staged"
        fi
        if [ -n "$hits" ]; then
            echo "  Conflict markers in:$hits"
            fail "Conflict markers found in staged files"
        fi
        pass "No snapshot candidate, no conflict marker"
    fi

    # 2. botopink test.
    local bin
    if grep -q '"workspaces"' "$root/botopink.json" 2>/dev/null; then
        # A workspace: one `botopink test` per library member (modules/*/ with a
        # botopink.json), each on its own manifest target. The examples are
        # applications and are built by stage 3.
        bin=$(requireBotopink)
        local member found=""
        for member in "$root"/modules/*/; do
            [ -f "$member/botopink.json" ] || continue
            found=1
            echo -n "  Testing modules/$(basename "$member") (botopink test)... "
            if ( cd "$member" && "$bin" test ) >/dev/null 2>&1; then
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${RED}✗${NC}"
                echo
                echo "  Re-run for failure output:  ( cd $member && $bin test )"
                fail "$(basename "$member"): botopink test failed"
            fi
        done
        [ -n "$found" ] || fail "botopink.json is a workspace but no modules/*/ holds a botopink.json"
    else
        if [ -z "$(find src test 2>/dev/null -name '*.bp' ! -name '*.d.bp' | head -1)" ]; then
            echo "  (no .bp sources under src/ or test/ — nothing to test)"
            return 0
        fi
        bin=$(requireBotopink)
        echo -n "  Testing $(basename "$root") (botopink test)... "
        if ( cd "$root" && "$bin" test ) >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗${NC}"
            echo
            echo "  Re-run for failure output:  ( cd $root && $bin test )"
            fail "$(basename "$root"): botopink test failed"
        fi
    fi

    # 3. every example builds.
    runExamplesGate "$bin"

    # 4. every refusal fixture is refused with its exact message.
    runRefusalsGate "$bin"
}

# runRefusalsGate <botopink-bin>
#
# `refusals/<case>/` holds a project that must NOT compile — a compile-time
# refusal of the library (a decorator's `decl.fail`), which no `test { }` block
# can express. Each case is `botopink check`ed; it passes when the check fails
# and its output holds every line of the case's `expect.txt` (the message and
# its ` --> file:line:col` location), verbatim. A case that compiles, or that
# fails with another message, fails the gate.
runRefusalsGate() {
    local bin="$1"
    local root
    root=$(git rev-parse --show-toplevel)
    [ -d "$root/refusals" ] || return 0
    local dir rel out line bad=""
    for dir in "$root"/refusals/*/; do
        [ -f "$dir/botopink.json" ] || continue
        rel="refusals/$(basename "$dir")"
        [ -f "$dir/expect.txt" ] || fail "$rel has no expect.txt"
        echo -n "  Refusing $rel (botopink check)... "
        if out=$( cd "$dir" && "$bin" check 2>&1 ); then
            echo -e "${RED}✗${NC}"
            bad="$bad\n  $rel compiles — it must be refused"
            continue
        fi
        out=$(printf '%s\n' "$out" | sed -r 's/\x1b\[[0-9;]*m//g')
        local missing=""
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            printf '%s\n' "$out" | grep -qxF -- "$line" || missing="$missing\n    $line"
        done < "$dir/expect.txt"
        if [ -n "$missing" ]; then
            echo -e "${RED}✗${NC}"
            bad="$bad\n  $rel is refused, but without:$missing\n  re-run: ( cd $dir && $bin check )"
        else
            echo -e "${GREEN}✓${NC}"
        fi
    done
    if [ -n "$bad" ]; then
        echo -e "$bad"
        fail "$(basename "$root"): refusals gate failed"
    fi
}

# runExamplesGate <botopink-bin>
#
# Builds every `examples/*/` that has a `botopink.json` (each with its own
# manifest target, into a throwaway --out). An example that does not build
# fails the gate; there is no list of examples allowed to fail (gate-i).
runExamplesGate() {
    local bin="$1"
    local root
    root=$(git rev-parse --show-toplevel)
    local dir name rel out bad=""
    for dir in "$root"/examples/*/; do
        [ -f "$dir/botopink.json" ] || continue
        name=$(basename "$dir")
        rel="examples/$name"
        out=$(mktemp -d)
        echo -n "  Building $rel (botopink build)... "
        if ( cd "$dir" && "$bin" build --out "$out" ) >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗${NC}"
            bad="$bad\n  $rel does not build — re-run: ( cd $dir && $bin build --out \$(mktemp -d) )"
        fi
        rm -rf "$out"
    done
    if [ -n "$bad" ]; then
        echo -e "$bad"
        fail "$(basename "$root"): examples gate failed"
    fi
}
