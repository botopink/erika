# erika — examples

> Path: `repository/erika/`
> Sibling (AGENTS): [`./AGENTS.md`](AGENTS.md) · Docs: [`./docs.md`](docs.md)
> Parent (workspace): [`../AGENTS.md`](../AGENTS.md)

All examples assume `erika` is a declared dependency
(`"dependencies": ["erika"]` in `botopink.json`).

## The fluent layer

Wrap an array in a `Query<T>` with `erika.of(...)`, then chain fluent operators.
Everything is eager and immutable — each operator returns a fresh `Query`.

```bp
import {erika} from "erika";

record Person { name: string, age: i32 }

fn main() {
    val people = [
        Person(name: "Ann", age: 30),
        Person(name: "Bob", age: 17),
        Person(name: "Cy",  age: 22),
    ];

    val adults = erika.of(people)
        .where({ p -> p.age >= 18 })
        .orderBy({ p -> p.name })
        .select({ p -> p.name })
        .toArray();

    @print(adults.join(", ")); // Ann, Cy
}
```

Aggregations, grouping, flattening and element terminals:

```bp
val total    = erika.range(1, 101).where({ n -> n % 2 == 0 }).sum({ n -> n }); // 2550
val byParity = erika.of([1, 2, 3, 4]).groupBy({ n -> n % 2 });                 // Query<Grouping<i32, i32>>
val firstBig = erika.of([1, 5, 9]).firstWhere({ n -> n > 4 });                 // ?i32 → 5
val pairs    = erika.of([1, 2, 3]).selectMany({ n -> [n, n * 10] }).toArray(); // [1, 10, 2, 20, 3, 30]
```

## The `erika "…"` query string

`erika` is also a **template function**: a SQL-subset query string is parsed at
compile time and expanded into the fluent pipeline. The grammar (keywords
lowercase) is:

```text
select <* | f1[, f2…]> from <Name> [where <cond>] [order by <field> [asc|desc]]
```

```bp
record City { name: string, pop: i32 }
val cities = [
    City(name: "Lyon",  pop: 5),
    City(name: "Paris", pop: 9),
    City(name: "Nice",  pop: 3),
];

// `select field` projects a single column → Array<string>
//
// expands (at comptime) to:
//   of(cities).where({ row -> row.pop >= 5 })
//             .orderBy({ row -> row.name })
//             .select({ row -> row.name }).toArray()
val names = erika "select name from cities where pop >= 5 order by name asc";
// → ["Lyon", "Paris"]

// `select a, b` projects an anonymous record per row → Array<record { name, pop }>
val rows = erika "select name, pop from cities where pop >= 5 order by name asc";
val labels = rows.map({ r -> r.name + ":" + r.pop.toString() });
// → ["Lyon:5", "Paris:9"]

// `select *` returns whole rows → Array<City>
val all = erika "select * from cities";

// the triple-quoted multi-line form (the `html """…"""` sibling) is authored the
// same way — newlines and tabs are normalized to spaces before tokenizing:
val bigRows = erika """
    select name, pop from cities
    where pop >= 5
    order by name asc
""";
```

The referenced collection (`cities`) is resolved against the caller's top-level
scope — the same caller-scope resolution `html` uses for its builders.

## `select` over a `var listas = [..]`

The **fluent** layer is an ordinary runtime call, so it queries any in-scope array
— `val` or `var`, records or scalars, even after a `var` is reassigned:

```bp
record Produto { nome: string, preco: i32 }

fn main() {
    var listas = [
        Produto(nome: "caderno", preco: 12),
        Produto(nome: "caneta",  preco: 3),
        Produto(nome: "mochila", preco: 80),
    ];

    // select the names of the pricier items
    val caros = erika.of(listas)
        .where({ p -> p.preco >= 12 })
        .select({ p -> p.nome })
        .toArray();                          // ["caderno", "mochila"]

    // a `var` can be reassigned, then re-queried
    listas = listas.append([Produto(nome: "lapis", preco: 2)]);
    val baratos = erika.of(listas)
        .where({ p -> p.preco < 12 })
        .orderBy({ p -> p.preco })
        .select({ p -> p.nome })
        .toArray();                          // ["lapis", "caneta"]

    // multi-field projection → an anonymous record per row
    val pares = erika.of(listas)
        .select({ p -> record { nome: p.nome, preco: p.preco } })
        .toArray();                          // [record { nome, preco }, …]
}
```

Scalars work the same way:

```bp
var nums = [1, 2, 3, 4, 5, 6];
val paresPorDez = erika.of(nums).where({ n -> n % 2 == 0 }).select({ n -> n * 10 }).toArray();
// [20, 40, 60]
```

> **`erika "…"` needs a `val`, not a `var`.** The SQL template resolves its
> collection from the caller's *comptime* scope snapshot, which only captures
> immutable `val` bindings. `erika "select … from listas"` where `listas` is a
> `var` does not resolve — use a `val` for the string form, or the fluent
> `erika.of(listas)` (above) for a `var`.

> **Runnable example.** A consumer project lives at
> [`./examples/erika-linq/`](examples/erika-linq/): it imports
> `{of, erika} from "erika"` and exercises the fluent layer **and** both the
> single-line `erika "…"` and triple-quoted `erika """…"""` SQL forms
> cross-module (`botopink test` green). The bare imported `erika` template fn now
> binds in a consumer's scope — the generic-loader-binding keystone (v0.beta.8)
> closed the old `unbound variable 'erika'` limit.

## See also

- The operator catalogue + grammar → [`./docs.md`](docs.md).
- The package contract + comptime-eval constraints → [`./AGENTS.md`](AGENTS.md).
