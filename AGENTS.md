# erika

> Path: `repository/erika/`
> Parent (workspace): [`../AGENTS.md`](../AGENTS.md) · Sibling (core): [`../botopink-lang/AGENTS.md`](../botopink-lang/AGENTS.md)
> Docs: [`./docs.md`](docs.md) · Examples: [`./examples.md`](examples.md)
> Spec: [`../../tasks/v0.beta.7/specs/erika.md`](../../tasks/v0.beta.7/specs/erika.md)

A **C#/LINQ-style query library** for botopink — a fluent, eager, immutable
`record Query<T>` over `Array<T>`, plus an `erika "…"` SQL-subset **template fn**
that expands (at comptime) to the same fluent pipeline. It is **pure botopink**:
zero compiler surface, no decorators, no host backing. erika is the proof that
the generic `from "<lib>"` loader works for an ordinary (non-framework) external
package, exactly as `rakun` is the proof for a decorator-driven one.

**Not std.** erika shipped *inside* `std` in v0.beta.6 only to dodge the per-lib
import machinery rakun then needed. v0.beta.7 replaced that with one generic
loader, so erika graduated to its own package: it is reached **only** through
`import {…} from "erika"` — no `std_pkg_files` entry, no `@embedFile`, no
`modules/compiler-core` mention (the lib-agnostic gate in `build.zig` covers
`erika` too).

## Tree

```text
erika/
├── AGENTS.md          ← you are here
├── docs.md            ← what this lib provides + the grammar + loading notes
├── examples.md        ← both forms (fluent + `erika "…"`), runnable
├── botopink.json      ← package metadata (files: ["root.bp", "erika.bp"])
└── src/
    ├── root.bp        ← module-tree root: `pub default mod erika;` (public +
                         DEFAULT surface — the `import erika` handle)
    └── erika.bp       ← the whole lib: `record Query<T>` + `Grouping<K,V>` +
                         constructors + the `pub default fn erika` template fn
                         (lexer + parser + dual lowering) + in-file tests
```

## Module tree (`root.bp`) + the package handle

`src/root.bp` is the explicit module-tree root: `pub default mod erika;` declares
the single public module AND marks it the package's DEFAULT module (the
`import erika` handle), so the package builds from the tree, not a deprecated
blind `src/` scan. A consumer reaches the named items via `import {…} from "erika"`
(the generic `from "<lib>"` loader), and binds the SQL DSL with `import erika`
(package-default-dsl): the handle `erika` resolves to the package's
`pub default fn erika`, so a bare `erika "…"` tagged call expands through the
ordinary template path. (The driver keys the alias by the *handle*, not the fn
name, so a handler need not share the lib's name; this lib keeps the name `erika`
so the generic-loader namespace form `erika.of(…)` still resolves through it.)
Both `root.bp` and `erika.bp` are listed in `botopink.json` `files` — the
`pub default mod` declaration only reaches consumers if its module ships.

## Design at a glance

- **`record Query<T> { items: Array<T> }`** — every operator returns a *new*
  `Query<U>` over a freshly materialized array (eager + immutable, like `sets`).
  Terminals return scalars, `?T`, or `Array<T>`.
- **Constructors** are top-level `pub fn` (`of`/`range`/`repeat`/`empty`). `from`
  is the import keyword and cannot name a function, so the wrapper is `of`.
- **No arity overloading** (on commonJS the later of two same-named methods
  replaces the earlier one — still true at `feat`), so the
  predicate variants are spelled out: `count`/`countWhere`, `first`/`firstWhere`,
  `any`/`anyWhere`.
- **`erika "…"`** is a template fn returning **`@ExprCustom<T>`**: it captures a
  SQL-subset string as `@Expr<string>` and runs a real three-stage front-end at
  comptime — ① a char-by-char **lexer** (`q.text()` → `Token[]`, every token
  span-aware), ② a recursive-descent-style **parser** (tokens → a `SelectStmt`
  value; the `where` clause is split into `or`-of-`and`-of-comparison groups so
  the `or < and < comparison` precedence is structural), then ③/④ **dual lowering**
  of the *same* parse. Grammar:
  `select <* | f1[, f2…]> from <Name> [where <cond>] [order by <field> [asc|desc]]`.
  The single-line `erika "…"` and triple-quoted multi-line `erika """ … """` forms
  are equivalent — the lexer treats newlines/tabs as ordinary token boundaries, so
  layout is free (the `html """…"""` sibling).
- **Lowering ③ → `@Expr<T>` (the executable pipeline).** Walks the `SelectStmt`
  into unqualified fluent source
  (`of(Name).where({row -> …}).orderBy(…).select(…).toArray()`) and splices it via
  `q.build(...)`. Behaviour is **byte-for-byte the same** as the pre-refactor
  scanner (single-field projection unwraps, multi-field → `record {…}`, `*` →
  `toArray()`, `=`→`==`, `<>`→`!=`, `and`→`&&`, `'x'`→`"x"`), so runtime/codegen
  across all backends is unchanged and the in-file + `examples/erika-linq`
  tests stay green.
- **Lowering ④ → `CustomNode` for tooling (sublanguage-lsp).** Walks the same
  tokens into a generic reference tree: keywords → `keyword`, idents
  (projected fields / source / columns) → `property`, string/number literals →
  `string`/`number`, comparison/logical ops (`= <> < <= > >= and or`) →
  `operator`. The source node carries `ref` (the `q.lookup` binding) so the LSP
  resolves hover/go-to-def to its declaration. Spans are byte offsets into
  `q.text()`, assigned by the lexer (no `indexOf`/`cursor` recovery any more). An
  unknown collection — or a malformed condition (a dangling operator) — aborts
  with `q.failAt(span, …)` ranged at the offending token, not the whole template.

## Conventions

- **Pure `.bp`, zero core surface.** The only compiler dependency is the
  *generic* loader; erika adds no Zig and is named nowhere in `compiler-core`.
- **Imported, never prelude.** Reached via `from "erika"` — the CLI's generic
  loader ([`../botopink-lang/modules/compiler-cli/src/cli/libs.zig`](../botopink-lang/modules/compiler-cli/src/cli/libs.zig))
  resolves `dependencies: ["erika"]` to `repository/erika/src/erika.bp` as the
  `erika/erika` package module via the multi-root walk. No per-lib registry,
  no embed.
- **Tests live here.** `test { … }` blocks inside `src/erika.bp`, run by
  `botopink test` from this directory — not in the compiler's Zig suites. The
  cross-module consumer story lives in [`./examples/erika-linq/`](examples/erika-linq/)
  (`botopink test` green there too).
- Keep this file, `docs.md`, `examples.md`, and the spec in sync in the same
  change that touches the lib.

## Comptime-eval constraint (why the `erika "…"` parser is written the way it is)

The `erika "…"` body runs at comptime in the **persistent Erlang runtime** — the
only comptime evaluator (`../botopink-lang/modules/compiler-core/src/comptime/`
`template_eval.zig` → `runtime/persistent_erl.zig`). `template_eval.zig` lowers
**only the template fn itself** with `codegen/erlang.zig` `emitComptimeModule`
(untyped: the body carries no inferred types), appends the host glue, writes
`.botopinkbuild/tmp/template/template_<hash>.erl`, and the persistent `erl`
server compiles and runs its `main/0`. Every rule below was re-checked against a
compiler built from botopink-lang `feat` at the comptime-dispatch merge (1.0.2-beta),
and the loop rule again after the `String.split("")` fix (1.0.4-beta);
each one names the constraint that still justifies it.

What the body may call:

- **The capture's host functions** — `q.text()`, `q.parts()`, `q.source()`,
  `q.context()`, `q.bindings()`, `q.lookup(name)` (a binding map or `undefined`),
  `q.build(code)`, `q.custom(tree, code)`, `q.fail(msg)`, `q.failAt(span, msg)`,
  plus `@compilerError`/`@expr`/`@code` — and the host records `Span`,
  `CustomNode`, `Binding`, `Source`, `Context`, whose constructors build maps.
- **Primitive methods on strings and arrays** — `split`, `join`, `slice`,
  `trim`, `map`, `filter`, `append`, `contains`, `indexOf`, `at`, `length()`, …
  Each call lowers to a `'__bp_prim_<method>'` shim that dispatches on the
  receiver's runtime kind (`is_binary`/`is_list`/…), so any method a primitive
  type declares works. `s.length()`, `s.len` and `xs.length` all work; `+`
  lowers to `'__bp_add'` (binary concat or arithmetic). A method no primitive
  and no host function answers is a located error ("the template `erika` calls
  `.m(…)` … at line:col").
- **`.at(i)` returns the element, or `null` past the end** — positional access
  needs no counter loop. There is **no `@Option` in the body**: `.at(i).unwrapOr(…)`
  is the "no primitive type provides `.unwrapOr`" error. "Optional" `where` /
  `order` clauses are therefore 0-length-list sentinels.
- **A two-parameter `loop` that reassigns outer `var`s** — `loop (xs) { x, i ->
  acc = … }` lowers to `lists:foldl` over `lists:enumerate(0, Xs)` and threads
  every reassigned variable out, with or without an explicit `, 0..` range, like
  the one-parameter form (item 7b, fixed in `codegen/erlang.zig` in 1.0.4-beta).
  `buildCmp` (`loop (cmpToks) { ct, idx -> }`) and the lexer
  (`loop (chars) { ch, i -> }`) rely on it. A mutation through a method in a
  closure (`out.push(x)` inside `forEach`) threads out too.

What it may not:

- **No sibling declarations.** Only the template fn is lowered, so a call to
  another top-level fn is `undefined_function`, a top-level `val` is
  `unbound_var`, and a named `record Token {…}` constructor is
  `undefined_function 'Token'/1`. The lexer/parser/lowering are therefore
  **inlined** in one fn body (helpers are local closures, `val f = { … }`, which
  may call each other), and the private SQL "AST" is **anonymous `record { … }`**
  values — Erlang maps, fields read with `maps:get/2`.

Three language-wide parser quirks (not comptime-specific — they fail the same way in
an ordinary fn):

- **No comments inside a closure/loop body** (`{ x -> … }`) — they parse as an
  unexpected token; keep comments at fn-body level.
- A top-level binary boolean **directly inside an `if (…)` condition fails to
  parse** (e.g. `if (a && b)`: unexpected token `&&`). Extract the compound to a
  `val` first, then `if (theVal)`.
- **`(expr).method()` fails to parse** — a parenthesized expression followed by a
  method call (unexpected token `.`). Bind it to a `val` first
  (`val padded = sql + " "; padded.split("")`).

Shapes the body keeps that no longer have a constraint behind them (safe to
simplify, not required):

- `s.split("").length` for a string's length (`sqlLen`) — `s.length()` works.
- Ending a lambda with a `val` instead of a bare `if … else …` (`cmpCode` /
  `operandCode`) — a closure whose last statement is an `if`-expression returns
  its value.
- The lexer's **single** `toks.append` site (the `pending` flush) — appending
  anonymous records from three separate branchy sites type-checks and evaluates.

The erlang-codegen gotchas listed in `../botopink-lang/libs/std/AGENTS.md`
(`+` on strings → `badarith`; `out.push(x)` inside `forEach` discarded) reproduce
neither in the comptime body nor, in their simple forms (`a + "!"`, `out.push(x)`
in `forEach`), in a typed erlang-target fn at `feat`; erika needs no workaround
for them.

## Status

- **Fluent layer** — complete; all ops covered by tests.
- **`selectMany` (flatMap)** — **landed.** Selector typed `fn(item: T) -> Array<U>`;
  unblocked by `fn() -> T[]` in a function-type parameter (gap **G3**, landed in `feat`).
- **Multi-field projection** (`select a, b`) — **landed.** Two-or-more fields project
  an anonymous structural `record { a: row.a, b: row.b }` per row; unblocked by
  anonymous record types (gap **G2**, landed in `feat`). A single field projects
  the bare column; `*` returns whole rows. Commas may be attached (`a, b`) or
  spaced (`a , b`) — the lexer treats each as its own token regardless.
- **Real lexer + parser + dual lowering** (`erika-query-ast`, v0.beta.11) —
  **landed.** The old `split`/`join` + `mode` scanner is replaced by a char-by-char
  lexer (`Token[]` with real spans), a parser producing a `SelectStmt` value (the
  `where` clause an `or`-of-`and`-of-comparison tree, so precedence is structural),
  and two lowerings off the same parse: ③ the executable `@Expr<T>` pipeline
  (behaviour identical to before) and ④ the `CustomNode` reference tree. New tests
  cover `and`/`or`/precedence/`<>` (`where precedence is or over and over
  comparison`, …); `q.failAt` at the offending token is implemented but not
  asserted in a `.bp` test (a malformed query would abort that module's compile) —
  the generic failAt-at-span path is covered by the sublanguage-lsp Zig fixtures.
- **Cross-module `erika "…"` (package handle)** — **landed (v0.beta.8, package
  binding v0.beta.14).** A consumer binds the package with `import erika, {of}
  from "erika"`: `erika` is the package handle (`ImportDecl.package`) and resolves
  to the package's `pub default fn query` (`package-default-dsl`), so
  `erika "select …"` (and the triple-quoted multi-line form) expand in a consumer
  module, resolving the collection in the caller's comptime scope. The driver
  (`comptime.zig`) aliases the handler under the handle and `resolveImports` binds
  it — generic, not erika-aware. (Before v0.beta.14 the consumer named the fn
  directly, `import {erika} from "erika"`, relying on a `pub fn erika` whose name
  matched the lib; that name-matching `pub fn` is now dropped.) Exercised by
  [`./examples/erika-linq/`](examples/erika-linq/) and
  [`../botopink-lang/examples/generic-loader-binding/`](../botopink-lang/examples/generic-loader-binding/).
  Still zero core surface here: the binding is generic loader work, not erika-aware.

### Recorded gaps

- **`erika "…"` resolves only `val` collections, not `var`.** The template reads
  the caller's *comptime* scope snapshot, which captures immutable `val` bindings
  only, so `erika "select … from listas"` where `listas` is a `var` does not
  resolve. The **fluent** form (`of(listas)` / `erika.of(listas)`) is an ordinary
  runtime call and queries any `var` or `val` array (covered by the
  `select over a var listas …` tests). Making the string form see `var`s is
  comptime scope-snapshot work in core — out of scope here.
- **Runtime-string form** (`var s = "select …"; erika s`) — pending.
  Needs a generic compiler mechanism (the call site captures a comptime
  scope-snapshot for a runtime `string` view, and the template body re-runs
  on that runtime payload). No erika-specific code in core. Deferred to a
  follow-up.
- **`average`** takes an `f64` selector (no `i32 → f64` cast exists); `range` /
  `repeat` build their arrays by **recursion** (the `Array.range`/`Array.repeat`
  producers aren't lowered by the commonJS backend).
- **Hole-span fidelity in `${…}` form.** A holed template's lex span tracks the
  *flattened* SQL (placeholder identifier inlined), so tokens that follow a hole
  are reported at offsets shifted by the placeholder length, not the original
  `${…}` byte position. The `q.custom` reference tree is still well-formed; LSP
  hover/go-to-def on tokens that precede every hole is exact. v1 acceptable.

## CI

Two workflows under `.github/workflows/`:

| Workflow      | Trigger                  | What                                                                |
| ------------- | ------------------------ | ------------------------------------------------------------------- |
| `test.yml`    | push / PR (feat/master/main) | Matrix `{ubuntu-22.04, macos-14, windows-2022} × {commonJS, erlang, beam}` (windows = commonJS-only — `escript` ships cleanly only on linux + macos). Bootstrap path: check out this lib + botopink-lang, `rsync self/ → botopink-lang/repository/erika/`, then `zig build install && zig build test-libs -- --lib erika --target <t>`. `BOTOPINK_LANG_REF` repo variable pins a specific botopink-lang ref (default `feat`). |
| `tag.yml`    | push to feat/master/main | Reads `version` from `botopink.json`. **feat** → moving `<version>-feat` tag (force-pushed on every push). **master/main** → immutable `<version>` tag (no-op on the same SHA; hard error if the version was not bumped). Uses the built-in `github.token`. |

## Tagging — "release is a manifest change"

`bpmp install erika` resolves through the tags `tag.yml` produces. To
publish a new stable release:

1. Bump `version` in `botopink.json` to the new SemVer.
2. Push to `master` (or `main`). The workflow creates the immutable tag.

If you push to `master` without bumping `version` and the previous
`<version>` tag already exists on a different SHA, the workflow fails
loudly with a "bump version in botopink.json to publish a new release"
message. This is intentional — it forces every release to be visible in
the manifest history.

To preview unreleased work, set `requires.erika = "feat"` in the
consuming project's `botopink.json` and run `bpmp sync` — bpmp will
resolve to the moving `<version>-feat` tag.

## See also

- The spec (intent, steps, test scenarios) → [`../../tasks/v0.beta.7/specs/erika.md`](../../tasks/v0.beta.7/specs/erika.md).
- The generic loader erika is a client of → [`../botopink-lang/modules/compiler-cli/src/cli/libs.zig`](../botopink-lang/modules/compiler-cli/src/cli/AGENTS.md).
- The decorator-driven sibling client → [`../rakun/AGENTS.md`](../rakun/AGENTS.md).

## Local gate

`scripts/git-hooks/pre-commit` is the tracked pre-commit gate. It is
self-contained: it sources `scripts/git-hooks/lib/runner-standalone.sh`
from this repository and reaches nothing outside it, so a standalone
clone, a checkout inside the botopink meta workspace and a worktree run
the same gate. Install it once per clone:

```sh
git config core.hooksPath scripts/git-hooks
```

`core.hooksPath` is per clone and applies to every worktree of it. The
gate checks staged files for conflict markers, then runs `botopink test`
over `src/` + `test/`. The compiler binary is located via (in order)
`$BOTOPINK_BIN`, the nearest ancestor
`repository/botopink-lang/zig-out/bin/botopink`, then `$PATH`. If none
resolve, the gate prints a yellow warning and exits 0 — CI runs the full
suite and catches any regression there. Never commit with `--no-verify`;
fix the red instead.

After `botopink test`, the gate builds every `examples/*/` that has a
`botopink.json` (`runExamplesGate`, each with its own manifest target,
into a throwaway `--out`); CI runs the same function once per workflow.
`scripts/known-broken-examples.txt` lists the examples allowed to fail —
`examples/<name>  <reason>` per line — and cannot rot: a listed example
that builds, or a listed path that no longer exists, fails the gate too.
When a fix makes an example build, delete its line in the same commit.
`examples/erika-linq` builds; nothing is listed.
