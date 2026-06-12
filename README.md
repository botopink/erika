# erika

> C#/LINQ-style query library for botopink — a fluent, eager, immutable
> `Query<T>` over `Array<T>`, plus an `erika "…"` SQL-subset template fn.

`erika` is pure botopink: zero compiler surface, no decorators, no host
backing. Reached via `from "erika"`.

## Install

```bp
import {from, Query} from "erika";
```

## Forms

**Fluent**:

```bp
val adults = from(people)
    .where(p => p.age >= 18)
    .orderBy(p => p.name)
    .select(p => p.name)
    .toArray();
```

**SQL-subset template** (expanded at comptime to the same fluent pipeline):

```bp
val adults = erika """
    select p.name from people p
    where p.age >= 18
    order by p.name
""";
```

## Status

- ✅ Fluent `Query<T>` over `Array<T>`, eager + immutable.
- ✅ `erika "…"` template fn — comptime SQL-subset → fluent pipeline.
- ✅ Span-aware diagnostics via `@ExprCustom<Element>` overlay.

See [docs.md](docs.md) for the grammar and the loader notes.

## Docs

- [AGENTS.md](AGENTS.md) — design + the "not std" rule.
- [docs.md](docs.md) — reference: what this lib provides + the grammar.
- [examples.md](examples.md) — both forms, runnable.
- [examples/](examples/) — `erika-linq` demo.

## License

Same as the parent botopink workspace.
