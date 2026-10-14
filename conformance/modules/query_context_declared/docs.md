query names no persistence library. It declares what the SQL target needs —
`QueryColumn`, `QueryTable` (the meta an entity records) and the `QueryContext<E>`
behavior (`run<T>(self, sql, params)`) — and a persistence library implements and
records them. The cell builds a `QueryTable` from query's declared types; `E` of
`QueryContext` is the implementor's own error, so query names no library's.
