Import what you need from `query`: the `query` namespace (and the `query "…"`
template) and the `Query<T>` type for annotations. The cell imports `Query` and
`of` and counts the even numbers of a list; the loader resolves `from "query"` to
the member `modules/query/` through the cell's path dependency.
