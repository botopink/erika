`from "erika"` reaches the library off disk in three ways, all generic: a bare value `of(xs)`, the
bare template fn `erika "…"` (expanded at comptime to the fluent layer), and the namespace member
`erika.of(…)` (resolved through the library's namespace object). The cell prints the answer of each:
the cities of at least five thousand by name, the same through the query string, and the squares of
the even numbers of a list.
