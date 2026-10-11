#!/usr/bin/env bash
# gate.sh — the gate of a botopink library repository, one entry.
#
# One text in every library repository (the meta repository's `hook-integrity`
# workflow compares the bytes, CI check 4). It runs the shared
# scripts/git-hooks/lib/runner-standalone.sh — and, through it, the repository's
# own scripts/git-hooks/repository-stages.sh when it tracks one — and names no
# library. It knows no job pool and no lock (decisions 468, 469): the machine's
# scheduler, when there is one, is the meta repository's `scripts/gate.sh`, which
# only hands this script a number of jobs.
#
# Usage:
#   scripts/gate.sh [--staged] [--no-conformance] [--jobs <N>]
#
#   --staged          also run stage 1 over `git diff --cached` (no snapshot
#                     candidate, no conflict marker staged) — the hook's.
#   --no-conformance  skip the conformance stage (`botopink cell check
#                     conformance/`) and say so; every other stage runs. The
#                     commit hook runs it so (decision 470); a front's
#                     Conformance step and CI (a push to `feat`, decision 477)
#                     run the gate WITH conformance. Not a gate verdict.
#   --jobs <N>        the total of jobs the test and example pools may use;
#                     default the machine's (one per CPU, bounded by memory).
#
# Exit 0 when every stage passed; 1 otherwise.
set -euo pipefail

case "${1:-}" in
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
esac

# shellcheck source=git-hooks/lib/runner-standalone.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/git-hooks/lib/runner-standalone.sh"
runStandaloneGate "$@"
