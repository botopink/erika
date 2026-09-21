# `repro/` — minimal reproductions handed back to botopink-lang

Each subdirectory is a **self-contained botopink package that contains no erika
at all**, written to hand a compiler defect back to the front that owns it with a
measurement instead of a description. They are not workspace members: the root
`botopink.json` globs `modules/*` and `examples/*`, so neither the pre-commit
gate nor `botopink-lib-test` builds or runs anything here. Run one by hand, from
its own directory.

A directory is deleted in the commit that lands the compiler fix.

---

## `erlang-imported-method-name/` — owner `00 · 02-erlang`

**A method name declared by TWO records of an imported module is resolved by the
NAME alone, so the call goes into the wrong record's module and reads the wrong
field offset off the right record's tuple.**

Measured 2026-09-21 against `botopink-lang` feat `c1c0f71c` (newer than
`fcc0244b`, the field-axis fix of this same shape).

```sh
cd repro/erlang-imported-method-name
botopink test --target commonJS   # 1/1 (owning module) + 2/2 (consumer) — green
botopink test --target erlang     # 1/1 (owning module) + 1 passed, 1 failed
```

```text
FAIL across a module boundary a Query keeps its own toArray  ({error,badarg})
```

`botopink build --target erlang` exits **0** — it transpiles and never invokes
`erlc`, so a build is not a check on this backend. The failure is a run-time
`badarg`, not a compile error: `erlc` is clean.

### The real stacktrace

The test runner prints the assertion line. The error itself, taken by exporting
the generated functions and calling one directly:

```erlang
{erlang, element,
         [3, {erika@erika__t__query, [<<"Ann">>, <<"Cy">>]}],
         [{error_info, #{module => erl_erts_errors}}]},
{erika@erika__t__grouping, toArray, 1, [{file, "erika@erika__t__grouping.erl"}, {line, 8}]},
{main, adultNames, 0, ...}
```

`Grouping.toArray/1` is `element(3, Self)`; it was handed a `Query` tuple, which
has two elements. Every one of the eight red cells of `examples/erika-linq` has
exactly this frame.

### What is emitted

`src/shapes.bp` declares `Query<T>` (payload at field 1) and `Grouping<K, V>`
(payload at field 2), each with a `toArray`. `src/main.bp` declares the same
collision LOCALLY, under the name `unwrap`. Both calls sit in the same emitted
file, side by side:

| call site | receiver's record | emitted erlang | result |
|---|---|---|---|
| local collision (`Bag`/`Bucket`) | `Bag` | `main__t__bag:unwrap({main__t__bag, […]})` | correct |
| imported collision (`Query`/`Grouping`) | `Query` | `shapes__t__grouping:toArray(shapes:'of'([…]))` | `badarg` |

Reordering the declarations does not change the answer: with `Grouping` written
first the call still goes to `shapes__t__grouping`. The receiver's type is not
consulted at all — the cross-module export index's hash iteration order is.

### Where it is

`modules/compiler-core/src/codegen/erlang.zig`. Inference leaves the receiver
untyped here (the chain crosses a module boundary through a generic `fn`), so the
`.type_` lowering never fires and the call falls through to the name-keyed
fallbacks at the end of the method-call lowering. Two of them, one disciplined
and one not:

- **Local types — correct.** `putMethodOwner` keys `method_owners` by
  `name/arity` and its own doc comment states the rule: *"A second type claiming
  the same `name/arity` clears the entry — the receiver's tag is what decides
  then."* The entry becomes `null`, and the name stops deciding.
- **Imported types — the defect.** `collectImportedTypes` fills `imported_fns`
  with `for (info.methods) |m| { const gop = try self.imported_fns.getOrPut(m);
  if (!gop.found_existing) gop.value_ptr.* = owner; }` — keyed by the method
  **name only**, no arity, and **first writer wins with no dissent check**.
  `importedFnOwner` then hands that owner straight to `b.remote(owner, …)`.

So the two axes of the same question are answered by two different rules, and
only the local one counts the dissent.

### This is the method twin of `fcc0244b`, already fixed on the field axis

`fcc0244b` ("a record read positionally has to BE a record") closed exactly this
question for **fields**: *"'The one record declaring this field' is counted over
the PROGRAM, not over the file (`uniqueRecordWithField`) … one dissenting
declaration sends the read to `'__bp_field'/2`, which asks the value's own tag."*

That fix is live in this binary and visibly working — in the same generated file,
`row.pop` (declared once) lowers to `element(3, Row)` while `row.name` (declared
by two records) lowers to `'__bp_field'(Row, name)`. The **method** axis never got
the same treatment.

### The fix shape, measured

`'__bp_field'/2`'s escape hatch already exists for methods: a record's methods live
in the record's own module (policy 3) and the value carries that module as its tag,
so the method twin is one line —

```erlang
'__bp_method0'(M, V) -> apply(element(1, V), M, [V]).
```

Patching the nine `erika@erika__t__grouping:toArray(` call sites of
`examples/erika-linq`'s generated `main.erl` to that form and running the escript
gives **9 passed, 0 failed**, with the example's source untouched. So the ledger
count for `erika-linq erlang` becomes **0** when this lands, not merely smaller.

### Why erika cannot work around it

`Query.toArray` and `Grouping.toArray` are both `pub` surface: `toArray` is the
terminal of the fluent chain AND the way a `groupBy` bucket is read
(`modules/erika/src/erika.bp`, cell `erika groupBy partitions by key`:
`odds.toArray()`). Renaming either one is an API break invented to route around a
compiler defect — and it is measurably the whole of the failure: renaming
`Grouping.toArray` to `toArrayXX` takes `examples/erika-linq --target erlang`
from 1 passed / 8 failed to **9 passed, 0 failed** in one edit. That measurement
is the diagnosis, not a patch: it is not committed, and the example is untouched.
