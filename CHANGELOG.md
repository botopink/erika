# erika · CHANGELOG

## Unreleased

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
