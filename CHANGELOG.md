# erika · CHANGELOG

## Unreleased

- **The 8 red erlang cells of `examples/erika-linq` are diagnosed and handed back**
  (botopink-lang `00 · 02-erlang`). Measured 2026-09-21 against botopink-lang feat
  `c1c0f71c`: `botopink test --target erlang` in the example is 1 passed / 8 failed,
  every one `{error, badarg}` — not `{error, undef}`, as the packaging note below
  recorded before anyone read the stack. The real frame is
  `erlang:element(3, {erika@erika__t__query, […]})` inside
  `erika@erika__t__grouping:toArray/1`: a method name declared by TWO records of an
  imported module (`Query.toArray` and `Grouping.toArray`) is resolved by the NAME
  alone, so the call enters the wrong record's module and reads its field offset off
  the right record's tuple. The backend already counts dissent for a local collision
  and, since `fcc0244b`, for a field collision — this is the same defect on the
  imported-method axis. Two measurements pin it: removing the name collision gives
  9/9, and dispatching on the receiver's own tag
  (`apply(element(1, V), toArray, [V])`) gives 9/9. **Neither is committed** — a
  library workaround for a compiler defect is not a fix. New
  [`repro/erlang-imported-method-name/`](repro/erlang-imported-method-name/) hands it
  back: a self-contained package with no erika in it, carrying the local collision as
  a green control beside the imported one. `modules/erika` stays 31/31 on both
  targets; `examples/erika-linq` stays 9/9 on commonJS and its `targets` array is
  unchanged.

- **erika is a workspace** (1.0.10-beta front `02-packaging` step 2, decisions 75 and 76). The
  root `botopink.json` declares members and is never a package — no `src`, `entry`, `files` or
  `dependencies`, and `botopink build/check/run/test` there is the located refusal that names the
  members (`erika, erika-linq`). The library moved to the member `modules/erika/`
  (`git mv src modules/erika/src`, no source edited): `name erika`, `entry root.bp`,
  `target commonJS`, `files ["root.bp", "erika.bp"]`. `from "erika"` resolves to that member — a
  library root contributes a workspace's members by manifest name, so the umbrella answers no
  import. `examples/erika-linq` is the member `erika-linq` (`entry main.bp`,
  `targets ["commonJS"]`) and depends on the core with `{ "erika": { "workspace": true } }`
  instead of the git form. The workspace declares no `targets`, so a member runs on every target
  the runner is asked for, as before. `scripts/git-hooks/lib/runner-standalone.sh` runs one
  `botopink test` per `modules/*` member when the root manifest carries `"workspaces"`.
  Measured unchanged across the move: `modules/erika` 31/31 on commonJS and 31/31 on erlang,
  `examples/erika-linq` 9/9 and building; `botopink format --check` still reports the same two
  files (`modules/erika/src/erika.bp`, `examples/erika-linq/src/main.bp`) — pre-existing.
  `examples/erika-linq` on the erlang target is red (1 passed / 8 failed), which
  is why the example restricts its `targets` to `["commonJS"]`; it is the cross-module erlang
  codegen red that predates this front. (Recorded here as `{error, undef}`; the measured shape
  is `{error, badarg}` — diagnosed in the entry above.)

- **The 1.0.3 surface** (botopink-lang front 12): `Query`/`Grouping` and the test fixtures are
  `type`s; every `record { … }` literal is a tuple. `select a, b` projects `#(a, b)` per row
  (the selector binds locals named after the columns, so the labels are the column names) and
  consumers destructure rows (`val #(a, b) = r`). The SQL template's private tokens,
  fields and comparisons are tuples read positionally (the body is evaluated untyped). commonJS
  and erlang 31/31, `examples/erika-linq` 9/9 with its output unchanged; the sources are not
  reformatted — `botopink format` currently drops the package handle of
  `import erika, {of}` and the `;` after a one-statement `if` in a loop body.
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
