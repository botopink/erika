# erika · CHANGELOG

## Unreleased

- CI: the `erlang` rows are hard cells (`allow_fail: false`) — the suite passes
  31/31 on erlang.

- The examples gate no longer aborts silently on a `scripts/known-broken-examples.txt`
  holding only comments or blank lines: the runner reads the list with `awk`, whose
  "no entry" is not a failure under `set -euo pipefail`.

- **MIT license.** `LICENSE` (`Copyright (c) 2026 Eric Fillipe and botopink
  contributors`) backs the README's License section, which now points at it.

- The gate builds the examples: after `botopink test`, the pre-commit hook
  and CI run `botopink build` in every `examples/*/` with a `botopink.json`;
  `scripts/known-broken-examples.txt` lists the ones allowed to fail, and a
  listed example that builds fails the gate.
- The pre-commit hook is self-contained: the dead delegation to a meta
  workspace runner is gone, and `AGENTS.md` documents the install
  (`git config core.hooksPath scripts/git-hooks`) instead of a
  `scripts/install-hooks.sh` that exists in no repository.
- Promoted from workspace subdir to standalone repository under
  `botopink/erika`. Tracked from `botopink/projects` as a git submodule on the
  `feat` branch.

## 0.0.1 — v0.beta.8

- `erika "…"` template fn — comptime SQL-subset → fluent pipeline.
- Real lexer + parser + dual lowering in the template body (single append site).
- Span-aware LSP overlay via `@ExprCustom<Element>` (custom tokens, diagnostics,
  hover, go-to-def).
- Cross-module `erika "…"` + multi-line `"""..."""` form.

## 0.0.0 — v0.beta.7

- Graduated out of `std` to its own package; reached only via `from "erika"`
  (the generic loader carries it across the workspace boundary).
- Fluent `Query<T>` over `Array<T>`: `where`, `select`, `orderBy`, `groupBy`,
  `take`, `skip`, …
