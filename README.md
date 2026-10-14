# query

[![CI](https://github.com/botopink/query/actions/workflows/test.yml/badge.svg?branch=feat)](https://github.com/botopink/query/actions/workflows/test.yml)

> C#/LINQ-style query library for botopink — a fluent, eager, immutable
> `Query<T>` over `Array<T>`, plus an `query "…"` SQL-subset template fn.

`query` is pure botopink: zero compiler surface, no decorators, no host
backing. Reached via `from "query"`.

## Install

```json
"dependencies": { "query": { "git": "https://github.com/botopink/query.git", "branch": "feat" } }
```

```bp
import query, {of, Query} from "query";
```

`query` is the package handle (binds the `query "…"` template). `of`
constructs a `Query<T>` over an `Array<T>` — `from` is the import keyword
and cannot name a function, so the wrapper is spelled `of`.

## Layout

`repository/query/botopink.json` is a **workspace** (`"workspaces": ["modules/*", "examples/*"]`,
decision 75 of 1.0.10-beta): it compiles nothing and ships nothing. The library is the member
[`modules/query/`](modules/query/) — `from "query"` resolves to it — beside the test-helper member
[`modules/query-test/`](modules/query-test/) (empty until a front fills it) and the runnable example
[`examples/query-linq/`](examples/query-linq/), which depends on the core with
`{ "query": { "workspace": true } }`. `botopink test` runs inside a member, never at the root.

## Forms

**Fluent**:

```bp
val adults = of(people)
    .where({ p -> p.age >= 18 })
    .orderBy({ p -> p.name })
    .select({ p -> p.name })
    .toArray();
```

**SQL-subset template** (expanded at comptime to the same fluent pipeline):

```bp
val adults = query """
    select p.name from people p
    where p.age >= 18
    order by p.name
""";
```

## Status

- ✅ Fluent `Query<T>` over `Array<T>`, eager + immutable.
- ✅ `query "…"` template fn — comptime SQL-subset → fluent pipeline.
- ✅ Span-aware diagnostics via `@ExprCustom<Element>` overlay.

See [conformance/docs.md](conformance/docs.md) for the grammar and the loader notes.

## Docs

- [AGENTS.md](AGENTS.md) — design + the "not std" rule.
- [conformance/docs.md](conformance/docs.md) — reference: what this lib provides + the grammar.
- [examples.md](examples.md) — both forms, runnable.
- [examples/](examples/) — `query-linq` demo.

## License

MIT — see [`LICENSE`](LICENSE). Same license as the rest of the botopink workspace.
