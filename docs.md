# erika — C#/LINQ-style queries

> Path: `repository/erika/`
> Sibling (AGENTS): [`./AGENTS.md`](AGENTS.md)
> Examples: [`./examples.md`](examples.md)
> Parent (workspace): [`../AGENTS.md`](../AGENTS.md)
> Spec: [`../../tasks/v0.beta.7/specs/erika.md`](../../tasks/v0.beta.7/specs/erika.md)

`erika` is botopink's answer to C#'s **LINQ**: a fluent query vocabulary over
`Array<T>`, plus a SQL-subset `erika "…"` template. It is **opt-in** — reached via
`from "erika"`, never auto-loaded into the type environment — and **pure
botopink**: the whole library is `src/erika.bp`, with zero compiler surface.

## Loading

erika is resolved by the generic external-lib loader. Declare it as a dependency
and import what you need:

```jsonc
// botopink.json
{ "name": "myapp", "target": "commonJS", "src": "src/",
  "dependencies": ["erika"] }
```

```bp
import {erika} from "erika";   // the `erika` namespace + the `erika "…"` template
import {Query} from "erika";   // the Query<T> type (for annotations)
```

The loader walks up from `cwd` and, at each ancestor, considers these roots
(nearest-first): `repository/botopink-lang/libs`, `repository/`, and a legacy
flat `libs/`. The first root holding `erika/botopink.json` wins (in this
workspace that's `repository/erika/`); it compiles `src/erika.bp` as the
`erika/erika` package module. There is no embed and no per-lib registry — the
compiler core never names erika.

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
- **`select a, b`** → an anonymous structural `record { a: …, b: … }` per row.
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

> Cross-module `erika "…"` after `import {erika} from "erika"` now resolves — the
> generic-loader-binding keystone (v0.beta.8) binds the bare imported template fn.
> A runnable consumer lives at [`./examples/erika-linq/`](examples/erika-linq/).

## See also

- Runnable examples → [`./examples.md`](examples.md).
- The package contract + comptime-eval constraints → [`./AGENTS.md`](AGENTS.md).
- Full language reference → [`../botopink-lang/docs.md`](../botopink-lang/docs.md).
