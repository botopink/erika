# erika

> Path: `repository/erika/`
> Parent (workspace): [`../AGENTS.md`](../AGENTS.md) · Sibling (core): [`../botopink-lang/AGENTS.md`](../botopink-lang/AGENTS.md)
> Docs: [`./docs.md`](docs.md) · Examples: [`./examples.md`](examples.md)
> Front: [`../../specs/1.0.10-beta/00-compiler-carry-over/09-ecosystem-residuals/README.md`](../../specs/1.0.10-beta/00-compiler-carry-over/09-ecosystem-residuals/README.md)
> (the front that owns this tree in 1.0.10-beta; the v0.beta.7 spec it was born from is gone)

A **C#/LINQ-style query library** for botopink — a fluent, eager, immutable
`type Query<T>` over `Array<T>`, plus an `erika "…"` SQL-subset **template fn**
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

The repository is a **workspace** (decision 75 of 1.0.10-beta): the root `botopink.json` declares
members and is never a package — no `src`, `files`, `entry` or `dependencies`, and `botopink
build/check/run/test` there is the located refusal `botopink.json is a workspace, not a package —
run this command inside one of its members: erika, erika-linq`. Every `modules/*/` and
`examples/*/` holding a `botopink.json` is a member, named by its own manifest. The **core is the
member `modules/erika/`**; `from "erika"` resolves to it, never to the umbrella.

```text
erika/
├── AGENTS.md          ← you are here
├── docs.md            ← what this lib provides + the grammar + loading notes
├── examples.md        ← both forms (fluent + `erika "…"`), runnable
├── botopink.json      ← WORKSPACE: name erika · version · description ·
│                        workspaces ["modules/*", "examples/*"]. No `targets`: a member
│                        runs on every target the runner is asked for (erika is green on
│                        commonJS and erlang, and `botopink test` has no beam backend).
│                        Nothing is importable from it.
├── modules/
│   └── erika/         ← THE CORE — what `from "erika"` gives a consumer
│       ├── botopink.json  name erika · src src/ · entry root.bp · target commonJS ·
│       │                    files ["root.bp", "erika.bp"] · no dependencies
│       └── src/
│           ├── root.bp    ← module-tree root: `pub default mod erika;` (public +
│           │                DEFAULT surface — the `import erika` handle)
│           └── erika.bp   ← the whole lib: `type Query<T>` + `Grouping<K,V>` +
│                            constructors + the `pub default fn erika` template fn
│                            (lexer + parser + dual lowering) + in-file tests
├── examples/
│   └── erika-linq/    ← member `erika-linq` (an application: entry main.bp, target
│                        commonJS, targets ["commonJS"], depends on the core with
│                        { "erika": { "workspace": true } })
└── scripts/git-hooks/ ← the pre-commit gate (§ Local gate): `botopink test` per
                         `modules/*` member, `botopink build` per example
```

There is no `modules/erika-test/` yet: the `<lib>-test` member of `02-packaging` § 5 waits on
`01-std`'s `std/testing/asserts` and `std/testing/snapshots` (front 02 step 4).

## Module tree (`root.bp`) + the package handle

`modules/erika/src/root.bp` is the explicit module-tree root: `pub default mod erika;` declares
the single public module AND marks it the package's DEFAULT module (the
`import erika` handle), so the package builds from the tree, not a deprecated
blind `src/` scan. A consumer reaches the named items via `import {…} from "erika"`
(the generic `from "<lib>"` loader), and binds the SQL DSL with `import erika`
(package-default-dsl): the handle `erika` resolves to the package's
`pub default fn erika`, so a bare `erika "…"` tagged call expands through the
ordinary template path. (The driver keys the alias by the *handle*, not the fn
name, so a handler need not share the lib's name; this lib keeps the name `erika`
so the generic-loader namespace form `erika.of(…)` still resolves through it.)
Both `root.bp` and `erika.bp` are listed in `modules/erika/botopink.json` `files` — the
`pub default mod` declaration only reaches consumers if its module ships, and a workspace
member that is a library and lists no `files` is `✗ ships nothing`.

## Design at a glance

- **`type Query<T>(items: Array<T>)`** — every operator returns a *new*
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
  scanner (single-field projection unwraps, multi-field → a tuple `#(a, b)`, `*` →
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
  resolves `"dependencies": { "erika": { … } }` to the workspace member
  `repository/erika/modules/erika/`, shipping `src/erika.bp` as the `erika/erika`
  package module. A root contributes every member of a workspace found there,
  **named by its manifest**, so the umbrella never answers the name. No per-lib
  registry, no embed.
- **Tests live here.** `test { … }` blocks inside `modules/erika/src/erika.bp`, run by
  `botopink test` from `modules/erika/` — not in the compiler's Zig suites. The
  cross-module consumer story lives in [`./examples/erika-linq/`](examples/erika-linq/)
  (`botopink test` green there too).
- **Every empty array literal is born with its element type** — `var out:
  Array<T> = [];`, never `var out = [];`. botopink-lang decision 8 §1.4 decides
  a type argument only where the value is born, so the bare form declares
  `unknown[]`: a warning today and an error once front 06's checker lands.
  Inside the `erika "…"` template body the element type is the tuple the body
  documents at `modules/erika/src/erika.bp:375` — a token is `#(string, string, Span)`, a
  projected field `#(string, Span)`, a comparison the seven-element tuple
  `buildCmp` answers.
- Keep this file, `docs.md`, `examples.md`, and the spec in sync in the same
  change that touches the lib.

## Formatting

`botopink format --check` is run per member, and the two answer differently on purpose:

- **`modules/erika`** — exit 0 at botopink-lang `f58fd392`. The sources were formatted once at
  decision 61's layout and again after `00 · C-12` landed the method-chain rule (a chain that does
  not fit in 80 columns puts every call on its own line, `+4`; a hand-broken chain that fits is
  joined). Each pass was verified before it was committed: the word-and-literal token stream of
  `erika.bp` is identical before and after, the pass is idempotent, the cell stays 31/31 on both
  targets, and `examples/erika-linq`'s emitted output is `diff -r` byte-identical on commonJS and
  erlang. Re-run `format` here after every formatter construct the compiler lands; commit the
  output only when those four measurements hold again.
- **`examples/erika-linq/src/main.bp` is left as written** and its `format --check` is red by
  design. The formatter re-attaches a trailing comment on an array-literal element
  (`Box(label: "sq", w: 4, h: 4),   // w == h, h > 2`) to the line **below** the element, where a
  reader takes it for the next element's — information lost, not layout changed. That is a
  formatter trivia row (front `00 · 16-formatter`, the "Handed over by 09" table), registered there;
  do not format the file until it round-trips, and do not rewrite the comments to dodge it.

## Erlang output at the current module-atom shape

The example's `--target erlang` output at `f58fd392` is one module per `type` under C-01's policy
3 — `out/erl/erika@erika__t__query.erl`, `erika@erika__t__grouping.erl`, `main__t__person.erl`, …
— and `botopink run --target erlang` in `examples/erika-linq` prints the same six lines the
commonJS run prints (the `erlc` warnings about unused `array_range/2` / `array_repeat/2` are the
compiler's, not erika's). Decision 109 respells that atom as `erika@erika@@Query` (the `@@`
boundary, the declaration's case kept) when front `00 · 13-module-identity` lands it; nothing in
this tree names the atom, so the change is invisible here, but both erlang cells (31 + 9) and the
example's `run` are re-measured after it — front 09 step 4.

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
- **A `for` that reassigns outer `var`s** — `for (xs) { x -> acc = … }` lowers
  to `lists:foldl` and threads every reassigned variable out. `for` binds the
  item only (decision 105 has no index binder), so `buildCmp`
  (`for (cmpToks) { ct -> }`) and the lexer (`for (chars) { ch -> }`) count the
  position in a `var` of their own. A mutation through a method in a
  closure (`out.push(x)` inside `forEach`) threads out too.

What it may not:

- **No sibling declarations.** Only the template fn is lowered, so a call to
  another top-level fn is `undefined_function`, a top-level `val` is
  `unbound_var`, and a named `type Token(…)` constructor is
  `undefined_function 'Token'/1`. The lexer/parser/lowering are therefore
  **inlined** in one fn body (helpers are local closures, `val f = { … }`, which
  may call each other), and the private SQL "AST" is **tuples** built by local
  closures (`mkTok`, `mkField`, `mkCmp`) and **read positionally** (`t.0`, `cmp.3`):
  the body is evaluated untyped, where a tuple label (`t.kind`) cannot be resolved to
  its index, so it would lower to `maps:get/2` on a tuple (`badmap`).

Shapes the body keeps that no longer have a constraint behind them (safe to
simplify, not required):

- The three parser quirks this file used to list — a `//` comment inside a
  closure or loop body, a binary boolean directly inside an `if (…)` condition
  (`if (a && b)`), and a parenthesized expression followed by a method call
  (`(a + b).split("")`) — **all parse, check and run at botopink-lang
  `f58fd392`** (measured 2026-09-25 with one scratch project holding the three
  shapes: `check` exit 0, `run` prints `1` / `a,b` / `2`). The body still
  extracts compound conditions to a `val` (`val padded = sql + " ";
  padded.split("")`) and keeps comments at fn-body level; both are habits now,
  not requirements.
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
  a tuple per row: the generated selector binds each column to a local named after it
  (`val a = row.a; val b = row.b; #(a, b)`), so the tuple's labels are the column names
  (gap **G2**, 1.0.3 surface). A consumer lambda reads a row by destructuring
  (`val #(a, b) = r`): a tuple label on a lambda parameter (`r.a`) is not resolved yet
  (botopink-lang 06 N24). A single field projects
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

- **`examples/erika-linq` was red on erlang — a botopink-lang defect, not erika's** —
  **fixed** in botopink-lang `2e6bb4ac` (`00 · 02-erlang`). Re-measured 2026-09-21 with
  this library untouched: `botopink test --target erlang` in the example goes from
  **1 passed / 8 failed**, every one `{error, badarg}`, to **9 passed / 0 failed**;
  commonJS was and stays 9/0.

  **The shape, kept because it outlives the defect.** A method name declared by TWO
  records of an *imported* module used to be resolved by the name alone. `Query<T>` and
  `Grouping<K, V>` both declare `toArray`, so every `.toArray()` a consumer wrote was
  emitted as `erika@erika__t__grouping:toArray/1` — `element(3, Self)` applied to a
  `Query` tuple of size 2. The erlang backend already counted dissent for a LOCAL
  collision (`putMethodOwner` clears the entry when a second type claims `name/arity`)
  and, since `fcc0244b`, for a FIELD collision (`uniqueRecordWithField` →
  `'__bp_field'/2`, which asks the value's own tag); the IMPORTED-method map
  (`imported_fns`, `importedFnOwner`) was keyed by the name only, with no arity and no
  dissent check. It is now counted over the program by `name/arity` like the other two,
  and one dissenting declaration sends the call through `'__bp_method'/3`, the method
  twin of `'__bp_field'/2`. Two `pub` methods sharing a name across two records of one
  imported module is ordinary surface here — `toArray` is the fluent terminal AND how a
  `groupBy` bucket is read (`odds.toArray()`) — so a divergence of this shape is worth
  measuring on both targets before it is read as erika's.

  The example's `targets` still reads `["commonJS"]`; botopink-lang's
  `scripts/restricted-targets.txt` now measures that restriction at **0**
  (`erika-linq erlang 0`), and lifting it is a separate decision.

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
| `test.yml`    | push / PR (feat/master/main) | Matrix `{ubuntu-22.04, macos-14, windows-2022} × {commonJS, erlang, beam}` (windows = commonJS-only — `escript` ships cleanly only on linux + macos). Bootstrap path: check out this lib + botopink-lang, `rsync self/ → botopink-lang/repository/erika/`, then `zig build install && zig build test-libs -- --lib erika --target <t>`. `--lib erika` now names the **member** `modules/erika/` (a root contributes a workspace's members by manifest name), so the umbrella has no row. The `erlang` rows are hard cells (no `allow_fail`; 31/31 on erlang). `BOTOPINK_LANG_REF` repo variable pins a specific botopink-lang ref (default `feat`). |
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

- The front that owns this tree (its steps, gate and open rows) →
  [`../../specs/1.0.10-beta/00-compiler-carry-over/09-ecosystem-residuals/README.md`](../../specs/1.0.10-beta/00-compiler-carry-over/09-ecosystem-residuals/README.md).
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
gate checks staged files for conflict markers, then — because the root
`botopink.json` carries `"workspaces"` — runs one `botopink test` inside
every `modules/*/` member on its own manifest target (the umbrella
compiles nothing, so testing it would be the workspace refusal). The
examples are applications and are built by the next stage.
The compiler binary is located via (in order)
`$BOTOPINK_BIN`, the nearest ancestor
`repository/botopink-lang/zig-out/bin/botopink`, then `$PATH`. If none
resolve, the gate prints a yellow warning and exits 0 — CI runs the full
suite and catches any regression there. Never commit with `--no-verify`;
fix the red instead.

After `botopink test`, the gate builds every `examples/*/` that has a
`botopink.json` (`runExamplesGate`, each with its own manifest target,
into a throwaway `--out`); CI runs the same function once per workflow.
The compiler-side twin of this gate is `zig build test-libs -- --lib erika --target <t>` (and
`--lib erika-linq` for the example's cell), run from `repository/botopink-lang/`. **From a
`.tasks/<name>/` worktree of the meta repository it refuses**: the runner walks up every
ancestor's `repository/` and finds this library twice — the worktree's copy and the main
checkout's — and a name that two libraries declare is a located refusal, not a pick (*"erika" is
declared by two libraries … rename one of them*; decision 67, no flag lifts it). Run the runner
binary from a directory outside the checkout with the worktree as the only root instead:
`botopink-lib-test --bin <worktree>/repository/botopink-lang/zig-out/bin/botopink --lib-root
<worktree>/repository --lib erika --target <t> --include-unsupported` — the same cell, one root.

`scripts/known-broken-examples.txt` lists the examples allowed to fail —
`examples/<name>  <reason>` per line — and cannot rot: a listed example
that builds, or a listed path that no longer exists, fails the gate too.
When a fix makes an example build, delete its line in the same commit. The list may be absent,
empty or hold only `#` comments — each means no example is allowed to fail.
`examples/erika-linq` builds; nothing is listed.
