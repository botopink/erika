Import what you need from `erika`: the `erika` namespace (and the `erika "…"`
template) and the `Query<T>` type for annotations. The cell imports `Query` and
`of` and counts the even numbers of a list; the loader resolves `from "erika"` to
the member `modules/erika/` through the cell's path dependency.
