# erika — C#/LINQ-style queries

> Path: `repository/erika/`
> Sibling (AGENTS): [`./AGENTS.md`](AGENTS.md)
> Examples: [`./examples.md`](examples.md)
> Parent (workspace): [`../AGENTS.md`](../AGENTS.md)
> Front: [`../../specs/1.0.10-beta/00-compiler-carry-over/09-ecosystem-residuals/README.md`](../../specs/1.0.10-beta/00-compiler-carry-over/09-ecosystem-residuals/README.md)

`erika` is botopink's answer to C#'s **LINQ**: a fluent query vocabulary over
`Array<T>`, plus a SQL-subset `erika "…"` template. It is **opt-in** — reached via
`from "erika"`, never auto-loaded into the type environment — and **pure
botopink**: the whole library is `modules/erika/src/erika.bp`, with zero compiler surface.

## Loading

`repository/erika/` is a **workspace** (`"workspaces": ["modules/*", "examples/*"]`); the library
is its member `modules/erika/`, and `from "erika"` resolves to that member, never to the umbrella.
Declare it as a dependency and import what you need:

```jsonc
// botopink.json — `dependencies` is the object form, one source per entry
{ "name": "myapp", "target": "commonJS", "src": "src/",
  "dependencies": { "erika": { "git": "https://github.com/botopink/erika.git", "branch": "feat" } } }
```

```jsonc
// …or, for a sibling member of erika's own workspace:
{ "dependencies": { "erika": { "workspace": true } } }
```

```bp
import {erika} from "erika";   // the `erika` namespace + the `erika "…"` template
import {Query} from "erika";   // the Query<T> type (for annotations)
```

The loader walks up from `cwd` and, at each ancestor, considers these roots (nearest-first): the
ancestor itself when its `botopink.json` is a workspace, `repository/botopink-lang/libs`,
`repository/`, a legacy flat `libs/`, then `.botopinkbuild/deps/`. A root contributes every
immediate child holding a `botopink.json` **and every member of a workspace found there, named by
its own manifest** — so `repository/` contributes `erika` (the member `repository/erika/modules/erika/`)
and `erika-linq`, and never the umbrella. The member's `files` — `root.bp` and `erika.bp` — are the
only modules a consumer sees. There is no embed and no per-lib registry — the compiler core never
names erika.

## The fluent layer — `Query<T>`

Wrap an array with `erika.of(...)`, then chain. Every operator returns a fresh
`Query` (eager, immutable); terminals return a scalar, `?T`, or `Array<T>`.

| Group | Operators |
|---|---|
| **Constructors** | `of(xs)`, `empty()`, `range(start, stop)`, `repeat(value, times)` |
| **Materialize / size** | `toArray`, `toList`, `count`, `isEmpty` |
| **Restriction / projection** | `where(pred)`, `select(fn)`, `selectMany(fn → Array<U>)` |
| **Partition / order** | `take(n)`, `skip(n)`, `takeWhile`, `skipWhile`, `reverse`, `orderBy(keyFn)`, `orderByDescending(keyFn)` |
| **Set / group / join** | `distinct`, `distinctBy`, `concat`, `union`, `intersect`, `except`, `groupBy(keyFn)` → `Query<Grouping<K,T>>`, `zip(other, combine)` |
| **Aggregate (terminal)** | `countWhere`, `sum`, `average`, `min`, `max`, `aggregate(seed, step)` |
| **Element (terminal)** | `first`, `firstWhere`, `last`, `single`, `elementAt` → `?T` |
| **Quantifier (terminal)** | `any`, `anyWhere`, `all`, `contains` |

`selectMany` flattens: the per-item selector returns an `Array<U>` and the
results are concatenated into one `Query<U>`.

## The `erika "…"` query string

`erika` is also a **template function**: a SQL-subset string is parsed at comptime
and expanded into the fluent pipeline. Keywords are lowercase. Grammar:

```text
select <* | f1[, f2…]> from <Name> [where <cond>] [order by <field> [asc|desc]]
```

- **`select *`** → the whole rows (`Array<Row>`).
- **`select field`** → that column (`Array<FieldType>`).
- **`select a, b`** → a tuple `#(a, b)` per row, labeled by the column names; read it
  with `val #(a, b) = row`.
  Commas may be attached (`a, b`) or spaced (`a , b`).
- **`where <cond>`** — comparisons over a field and a literal/field
  (`== != < <= > >=`; `=` reads as `==`, `<>` as `!=`; `and`/`or`). String
  literals use single quotes (`name = 'Paris'`); bare digits are numbers.
- **`order by <field> [asc|desc]`** — stable sort by the projected key.

The referenced collection is resolved against the caller's top-level scope. The
expansion emits **unqualified** fluent source
(`of(Name).where(…).orderBy(…).select(…).toArray()`), so it resolves wherever
`of` / the collection are in scope. The query may be written single-line
(`erika "…"`) or triple-quoted multi-line (`erika """ … """`) — the lexer scans
character-by-character and treats newlines and tabs as ordinary token boundaries,
so the two forms parse identically.

### Front-end (lexer → parser → dual lowering)

`erika "…"` runs a real three-stage front-end at comptime — no string
`split`/`join` scanning:

1. **lexer** — a char-by-char scanner turns the query into a `Token[]`, each token
   carrying a `Span` (byte offsets into the source string).
2. **parser** — buckets the tokens into a `SelectStmt`-shaped value; the `where`
   clause is parsed into `or`-groups of `and`-groups of comparisons, so the
   `or < and < comparison` precedence is structural.
3. **dual lowering** — the same parse is lowered twice: into the executable fluent
   `@Expr<T>` pipeline (spliced via `q.build`), and into a generic `CustomNode`
   reference tree (for the language server). The two halves are returned together
   as `@ExprCustom<T>` via `q.custom(tree, code)`; the source node carries its
   `q.lookup` binding as `ref` so hover / go-to-definition resolve to the
   collection's declaration. A malformed query aborts with `q.failAt(span, …)`
   ranged at the offending token, not the whole template.

## Known gaps

- **Interpolated queries** (`erika "… where age >= ${min}"`) — not built yet.
- **`erika "…"` resolves only `val` collections, not `var`** — the template reads
  the caller's comptime scope snapshot, which captures immutable `val` bindings
  only. The fluent `of(listas)` / `erika.of(listas)` form queries any `var`/`val`.

> Cross-module `erika "…"` resolves through the package-handle binding — a
> consumer writes `import erika, {of} from "erika"`, and the `erika` handle
> binds the package's `pub default fn` (`package-default-dsl`, v0.beta.14;
> the underlying bare-imported template-fn binding landed earlier in
> v0.beta.8 via the generic-loader-binding keystone). A runnable consumer
> lives at [`./examples/erika-linq/`](examples/erika-linq/).

## See also

- Runnable examples → [`./examples.md`](examples.md).
- The package contract + comptime-eval constraints → [`./AGENTS.md`](AGENTS.md).
- Full language reference → [`../botopink-lang/docs.md`](../botopink-lang/docs.md).
