#!/usr/bin/env bash
# runner-standalone.sh — the pre-commit gate of a botopink library.
#
# Sourced by scripts/git-hooks/pre-commit. It is the only runner and it is one
# text in every library repository (the meta repository's `hook-integrity`
# workflow compares the bytes): it needs nothing outside the repository it sits
# in — standalone clone, meta checkout, worktree, bpmp packing — and it names
# no library. What differs between repositories is what their trees hold, never
# this file.
#
# Stages, in order:
#
#   1. staged files  no snapshot candidate (`*.snap.new` / `*.snap.md.new` — a
#                    mismatch writes one, it is recorded by renaming it, never
#                    committed) and no conflict marker;
#   2. the compiler  found, or the gate fails saying how to provide one;
#   3. repository    `scripts/git-hooks/repository-stages.sh`, when the
#      stages        repository tracks one: the checks only this repository has;
#   4. tests         `botopink test --target <t>` in every workspace member, on
#                    every target the member's manifest declares;
#   5. examples      `botopink build --target <t>` of every `examples/*/`, on
#                    every target its manifest declares;
#   6. refusals      every `refusals/*/` project is refused by `botopink check`
#                    with the lines of its `expect.txt`, when the repository has
#                    a `refusals/` directory.
#
# Fail beats warn (decision 67; 1.0.11-beta 00-gate, gate-i): nothing here
# skips. No flag, environment variable or list turns a stage off or names a
# member, target or example that may fail. A stage is absent only structurally
# — no `refusals/` directory, no `repository-stages.sh`, no `examples/` — and a
# cell is absent only because the manifest does not declare the target.
# Stages 1–3 stop the gate at the first red (they are cheap and everything
# after them depends on them); stages 4–6 all run, every red is listed, and the
# gate fails at the end — one run tells the whole truth.
#
# The functions `requireBotopink`, `runRepositoryStagesGate`, `runTestsGate`,
# `runExamplesGate` and `runRefusalsGate` are also what CI and
# `scripts/check-refusals.sh` call: they report their reds and return non-zero.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }
pass() { echo -e "${GREEN}✓ $1${NC}"; }

# The repository this runner belongs to — three directories above this file —
# and the runner's own path. Assigned here, on every source: never read from
# the environment, and independent of the caller's working directory.
gate_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
gate_runner="$gate_root/scripts/git-hooks/lib/runner-standalone.sh"

# locateBotopink — the compiler's path on stdout, or status 1.
#
# `$BOTOPINK_BIN` when it is set (and then nothing else: a `BOTOPINK_BIN` that
# is not an executable is a miss, never a reason to pick another compiler);
# else the compiler of the ENCLOSING checkout — the nearest ancestor holding
# `repository/botopink-lang/` (its `zig-out/bin/botopink` or nothing: the walk
# stops there, so a worktree nested under another checkout never borrows that
# checkout's binary); else a botopink-lang checkout's own `zig-out`; else
# `$PATH`.
locateBotopink() {
    if [ -n "${BOTOPINK_BIN:-}" ]; then
        [ -f "$BOTOPINK_BIN" ] && [ -x "$BOTOPINK_BIN" ] || return 1
        echo "$BOTOPINK_BIN"; return 0
    fi
    local cur="$gate_root" cand
    while [ "$cur" != "/" ]; do
        if [ -d "$cur/repository/botopink-lang" ]; then
            cand="$cur/repository/botopink-lang/zig-out/bin/botopink"
            if [ -x "$cand" ]; then echo "$cand"; return 0; fi
            break
        fi
        cand="$cur/zig-out/bin/botopink"
        if [ -x "$cand" ] && [ -f "$cur/build.zig" ]; then echo "$cand"; return 0; fi
        cur=$(dirname "$cur")
    done
    if command -v botopink >/dev/null 2>&1; then command -v botopink; return 0; fi
    return 1
}

# requireBotopink — locateBotopink, or the refusal with the way out. Called as
# `bin=$(requireBotopink) || exit 1`: the path is stdout, the refusal stderr.
# Never a warning: a gate that skips its `.bp` stages gates nothing.
requireBotopink() {
    local bin
    if bin=$(locateBotopink); then
        echo "$bin"; return 0
    fi
    {
        if [ -n "${BOTOPINK_BIN:-}" ]; then
            echo "  BOTOPINK_BIN is set to '$BOTOPINK_BIN', which is not an executable file."
        fi
        echo "  botopink compiler not found. Either"
        echo "    - build one: \`zig build install\` in the botopink-lang checkout (the enclosing"
        echo "      checkout's repository/botopink-lang/, so its zig-out/bin/botopink exists), or"
        echo "    - point at one: export BOTOPINK_BIN=/path/to/botopink, or put \`botopink\` on \$PATH."
        echo -e "${RED}✗ no compiler — the .bp gate cannot run, so the gate fails${NC}"
    } >&2
    return 1
}

# manifestList <botopink.json> <key> — the entries of the manifest's `<key>`
# string array, one per line; nothing when the manifest has no such key.
manifestList() {
    [ -f "$1" ] || return 0
    tr -d '\n\r' < "$1" \
        | sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' \
        | tr -d '" ' | tr ',' '\n' | sed '/^$/d'
}

# manifestTargets <botopink.json> — the targets a member declares, one per
# line. The lib-test runner's reading, so the hook runs exactly the cells CI
# runs: the member's `targets` list when it has one (a member may only restrict
# its workspace's), else the workspace's `targets`, else every target
# `botopink test` runs (commonJS and erlang). A manifest's `target` — the
# default of a bare `botopink build` — is not a restriction and is not read.
manifestTargets() {
    local listed
    listed=$(manifestList "$1" targets)
    if [ -z "$listed" ]; then
        listed=$(manifestList "$gate_root/botopink.json" targets)
    fi
    if [ -z "$listed" ]; then
        listed=$(printf 'commonJS\nerlang')
    fi
    echo "$listed"
}

# workspaceMembers — the directories `botopink test` runs in, one per line:
# every directory the root manifest's `workspaces` patterns expand to that
# holds a `botopink.json` (modules, examples, starters — whatever the workspace
# declares; the umbrella itself compiles nothing, decision 75), or the root
# itself when the root manifest is a plain package with `.bp` sources.
workspaceMembers() {
    local manifest="$gate_root/botopink.json" pattern dir
    if grep -q '"workspaces"' "$manifest" 2>/dev/null; then
        for pattern in $(manifestList "$manifest" workspaces); do
            # $pattern is unquoted on purpose: `modules/*` is a glob.
            for dir in "$gate_root"/$pattern/; do
                if [ -f "${dir}botopink.json" ]; then echo "${dir%/}"; fi
            done
        done
    elif [ -n "$(cd "$gate_root" && find src test -name '*.bp' ! -name '*.d.bp' 2>/dev/null | head -1)" ]; then
        echo "$gate_root"
    fi
}

# stripColours — stdin to stdout without ANSI colour sequences (the escape byte
# is spelled through printf: BSD sed reads no `\x1b`).
stripColours() {
    sed -E "s/$(printf '\033')\[[0-9;]*m//g"
}

# testTally <log> — the verdict line of a `botopink test` log.
testTally() {
    stripColours < "$1" | grep -E '^total: |^no test blocks found' | tail -1 || true
}

# runStagedFilesGate — stage 1. A `*.snap.new` / `*.snap.md.new` is written by
# a snapshot mismatch or a missing snapshot and is recorded by renaming it
# after it was compared with the spec's literal; the candidate itself is never
# committed, `.gitignore` or not (`git add -f` gets past that). Conflict
# markers are read in regular files only — gitlinks are skipped.
runStagedFilesGate() {
    local lt7 eq7 gt7
    lt7=$(printf '<%.0s' {1..7})
    eq7=$(printf '=%.0s' {1..7})
    gt7=$(printf '>%.0s' {1..7})
    local marker_re="${lt7} |${eq7}\$|${gt7} "
    local staged f hits="" candidates=""
    staged=$(git -C "$gate_root" diff --cached --name-only --diff-filter=ACMR)
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in
            *.snap.new|*.snap.md.new) candidates="$candidates $f" ;;
        esac
        [ -f "$gate_root/$f" ] || continue
        if grep -qE "$marker_re" "$gate_root/$f" 2>/dev/null; then
            hits="$hits $f"
        fi
    done <<< "$staged"
    if [ -n "$candidates" ]; then
        echo "  Snapshot candidates staged:$candidates"
        echo "  Compare each with the spec's literal and record it by renaming (mv x.snap.new x.snap); never commit the candidate."
        echo -e "${RED}✗ Snapshot candidate (*.snap.new / *.snap.md.new) staged${NC}"
        return 1
    fi
    if [ -n "$hits" ]; then
        echo "  Conflict markers in:$hits"
        echo -e "${RED}✗ Conflict markers found in staged files${NC}"
        return 1
    fi
    pass "No snapshot candidate, no conflict marker"
}

# runRepositoryStagesGate — stage 3, the one extension point.
#
# `scripts/git-hooks/repository-stages.sh`, when the repository tracks it, is
# the checks only that repository has (a grep over its own sources, a lint of
# its own layout). It can only ADD a red, never remove a stage: it runs in a
# child bash process, so nothing it defines, sets, traps or changes directory
# to exists in the shell that runs the shared stages, and the one thing that
# comes back is its exit status — non-zero fails the gate, zero means "go on"
# and every shared stage then runs exactly as it would without the file. The
# child sources this runner first, so `fail`, `pass`, `gate_root` and
# `$BOTOPINK_BIN` are there for it to use.
runRepositoryStagesGate() {
    local file="$gate_root/scripts/git-hooks/repository-stages.sh"
    [ -f "$file" ] || return 0
    if ( cd "$gate_root" && exec "$BASH" -euo pipefail -c '. "$1"; . "$2"' repository-stages "$gate_runner" "$file" ) </dev/null; then
        return 0
    fi
    echo -e "${RED}✗ $(basename "$gate_root"): repository stages failed (scripts/git-hooks/repository-stages.sh)${NC}"
    return 1
}

# runTestsGate <botopink-bin> [<target>]
#
# Stage 4: `botopink test --target <t>` in every workspace member on every
# target its manifest declares — or, with `<target>`, on that one target for
# the members that declare it. A member with no `test` block is still compiled
# (`botopink test` compiles it and reports `no test blocks found`). Every cell
# runs; the reds are listed with the tail of their output and the gate fails.
runTestsGate() {
    local bin="$1" only="${2:-}"
    local members member rel target log tally cells=0 bad=""
    members=$(workspaceMembers)
    if [ -z "$members" ]; then
        if grep -q '"workspaces"' "$gate_root/botopink.json" 2>/dev/null; then
            echo -e "${RED}✗ botopink.json is a workspace but none of its patterns holds a botopink.json${NC}"
            return 1
        fi
        echo "  (no .bp sources under src/ or test/ — nothing to test)"
        return 0
    fi
    log=$(mktemp)
    while IFS= read -r member <&3; do
        rel="${member#"$gate_root"}"; rel="${rel#/}"; rel="${rel:-.}"
        for target in $(manifestTargets "$member/botopink.json"); do
            [ -z "$only" ] || [ "$target" = "$only" ] || continue
            cells=$((cells + 1))
            echo -n "  Testing $rel · $target (botopink test)... "
            if ( cd "$member" && "$bin" test --target "$target" ) >"$log" 2>&1 </dev/null; then
                tally=$(testTally "$log")
                echo -e "${GREEN}✓${NC} ${tally}"
            else
                tally=$(testTally "$log")
                echo -e "${RED}✗${NC} ${tally}"
                stripColours < "$log" | tail -n 30 | sed 's/^/      /'
                bad="$bad\n  $rel · $target fails — re-run: ( cd $member && $bin test --target $target )"
            fi
        done
    done 3<<< "$members"
    rm -f "$log"
    if [ -n "$bad" ]; then
        echo -e "$bad"
        echo -e "${RED}✗ $(basename "$gate_root"): tests gate failed${NC}"
        return 1
    fi
    pass "tests: $cells cell(s) — every member on ${only:-every declared target}"
}

# runExamplesGate <botopink-bin> [<target>]
#
# Stage 5: builds every `examples/*/` that has a `botopink.json` on every
# target its manifest declares (into a throwaway --out) — or, with `<target>`,
# on that one target for the examples that declare it (a CI row builds its
# own). An example that does not build fails the gate; there is no list of
# examples allowed to fail.
runExamplesGate() {
    local bin="$1" only="${2:-}"
    local dir rel out target builds=0 bad=""
    for dir in "$gate_root"/examples/*/; do
        [ -f "${dir}botopink.json" ] || continue
        dir="${dir%/}"
        rel="examples/$(basename "$dir")"
        for target in $(manifestTargets "$dir/botopink.json"); do
            [ -z "$only" ] || [ "$target" = "$only" ] || continue
            builds=$((builds + 1))
            out=$(mktemp -d)
            echo -n "  Building $rel · $target (botopink build)... "
            if ( cd "$dir" && "$bin" build --target "$target" --out "$out" ) >/dev/null 2>&1 </dev/null; then
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${RED}✗${NC}"
                bad="$bad\n  $rel · $target does not build — re-run: ( cd $dir && $bin build --target $target --out \$(mktemp -d) )"
            fi
            rm -rf "$out"
        done
    done
    if [ -n "$bad" ]; then
        echo -e "$bad"
        echo -e "${RED}✗ $(basename "$gate_root"): examples gate failed${NC}"
        return 1
    fi
    pass "examples: $builds build(s) — every example on ${only:-every declared target}"
}

# runRefusalsGate <botopink-bin>
#
# Stage 6: `refusals/<case>/` holds a project that must NOT compile — a
# compile-time refusal of the library (a decorator's `decl.fail`), which no
# `test { }` block can express. Each case is `botopink check`ed; it passes when
# the check fails and its output holds every line of the case's `expect.txt`
# (the message and its ` --> file:line:col` location), verbatim. A case that
# compiles, that fails with another message, or that has no `expect.txt` fails
# the gate. The stage exists when the directory does.
runRefusalsGate() {
    local bin="$1"
    [ -d "$gate_root/refusals" ] || return 0
    local dir rel out line missing cases=0 bad=""
    for dir in "$gate_root"/refusals/*/; do
        [ -f "${dir}botopink.json" ] || continue
        dir="${dir%/}"
        rel="refusals/$(basename "$dir")"
        cases=$((cases + 1))
        echo -n "  Refusing $rel (botopink check)... "
        if [ ! -f "$dir/expect.txt" ]; then
            echo -e "${RED}✗${NC}"
            bad="$bad\n  $rel has no expect.txt"
            continue
        fi
        if out=$( cd "$dir" && "$bin" check 2>&1 </dev/null ); then
            echo -e "${RED}✗${NC}"
            bad="$bad\n  $rel compiles — it must be refused"
            continue
        fi
        out=$(printf '%s\n' "$out" | stripColours)
        missing=""
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            # `grep … >/dev/null`, not `grep -q`: an early exit under `pipefail`
            # would turn a found line into a missing one.
            printf '%s\n' "$out" | grep -xF -- "$line" >/dev/null || missing="$missing\n    $line"
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
        echo -e "${RED}✗ $(basename "$gate_root"): refusals gate failed${NC}"
        return 1
    fi
    pass "refusals: $cases case(s) refused with their exact message"
}

# runStandaloneGate — the pre-commit gate: the six stages above.
runStandaloneGate() {
    cd "$gate_root"
    SECONDS=0

    # 1. staged files.
    runStagedFilesGate || exit 1

    # 2. the compiler. Absent is a failure, never a skipped gate. It is
    #    exported: a suite that builds fixtures compiles them with the compiler
    #    that runs it.
    local bin
    bin=$(requireBotopink) || exit 1
    export BOTOPINK_BIN="$bin"
    pass "Compiler: $bin"

    # 3. the repository's own stages.
    runRepositoryStagesGate || exit 1

    # 4–6. every cell, every example, every refusal — all run, then the verdict.
    local red=""
    runTestsGate "$bin" || red="$red tests"
    runExamplesGate "$bin" || red="$red examples"
    runRefusalsGate "$bin" || red="$red refusals"
    if [ -n "$red" ]; then
        fail "$(basename "$gate_root"): pre-commit gate failed —$red (${SECONDS}s)"
    fi
    pass "$(basename "$gate_root"): pre-commit gate passed (${SECONDS}s)"
}
