---
name: moontoml
description: "TOML for MoonBit at the edition the file was written in (0.4, 0.5, 1.0.0, 1.1) — read a document and write it back as a Json tree, kind for kind, or as the document kept with its comments and order. Use when a task reads or writes a TOML file: a moon.mod, a config for a service, a file a person edits by hand. Covers both readings, the fidelity document, the editions, the four date-time kinds, 64-bit integers, and the error that says which line is wrong."
---

# moontoml

One package, at the edition the file was written in. A document goes in, a tree
comes out; write the tree back and the values are the same, and write the document
back and the comments and order are the same too. Every entry point that reads
raises `Refused` with a position instead of returning a flag.

## Install

```bash
moon add moonbitstack/moontoml
```

```moonbit
import {
  "moonbitstack/moontoml",
}
```

## Read a document, and write it back

`loads` answers a `Json` tree, which is the shape to use when the rest of the
program already works on `Json`. `dumps` writes it back.

```moonbit
let doc = @moontoml.loads("port = 12000\n[db]\nhost = \"localhost\"\n"[:])
guard doc is Object(root) else { abort("a document is a table") }
let port = match root.get("port") {
  Some(Number(n, ..)) => n.to_int()
  _ => 0
}
let again = @moontoml.dumps(doc)          // the same values, this writer's layout
```

`load` and `dump` are the same pair over bytes, and skip a byte-order mark unless
`bom=false`.

## Keep the kinds

A `Json` tree has one number and no date-time, so a date arrives as text and a
large integer as a double. `decode` answers a `Value` instead, and `encode` writes
it back without guessing:

```moonbit
let doc = @moontoml.decode("port = 12000\nwhen = 1979-05-27\nname = \"1979-05-27\"\n")
guard doc is Table(fields) else { abort("a document is a table") }
guard fields.get("when") is Some(Datetime(m)) else { abort("a date") }
let day = m.to_string()                    // 1979-05-27
let again = @moontoml.encode(doc)
// port = 12000
// when = 1979-05-27
// name = "1979-05-27"
```

`Datetime` holds `moondate`'s `Moment`, one of four kinds: an offset date-time, a
local date-time, a local date, a local time. `Integer` holds `Int64`, so every
value the format allows survives. Building a tree by hand means building `Value`:
`Integer`, `Float(Real::new(1.5))`, `String`, `Boolean`, `Datetime`, `Array`,
`Table`.

## Keep the document

`loads` and `decode` forget the page they read. `decode_doc` keeps it, for the file
a person edits: change a value in place and write the result back, and the rest of
the document is the source byte for byte.

```moonbit
let doc = @moontoml.decode_doc("beds = 4  # the ones that get sun\nsoil = \"loam\"\n")
let moved = doc.set(["beds"], @moontoml.Value::integer(6))   // Some(true)
assert_eq(doc.render(), "beds = 6  # the ones that get sun\nsoil = \"loam\"\n")
```

`get` reaches a value by path — `["soil", "ph"]` is the key under a `[soil]`
header — and `set` replaces one in place, answering whether it moved. When the path
names nothing, `set` answers nothing and the document is left as it was. `render`
answers the document.

## The editions

The root reads TOML 1.0.0. The editions are subpackages with the same entry points,
pinned to their grammar: `moonbitstack/moontoml/v04`, `…/v05` and `…/v110`. A `0.5`
file is refused of a `0.4` (dotted keys, `0xff`, `inf`, local dates are 0.5 and
later) and read in full at its own; a `1.1` file of its newlines-in-inline-tables,
`\x`/`\e` escapes and seconds-less time is read at `v110` and refused of `1.0.0`.

```moonbit
assert_eq(@v110.loads("p = { x = 1,\n y = 2,\n}"[:]).stringify(), "{\"p\":{\"x\":1,\"y\":2}}")
let v04 = @moontoml.Flavor::new(edition=@moontoml.V04)
let refused = try {
  let _ = @moontoml.loads("a.b = 1\n"[:], flavor=v04)
  false
} catch {
  _ => true
}
assert_eq(refused, true)
```

`Flavor::new(edition=…)` on the root reads any edition without the subpackage; the
subpackage is the form that pins the grammar where it is read.

## Report what is wrong

```moonbit
let outcome = try {
  let _ = @moontoml.loads("a = 1\nb = @\n"[:])
  "read"
} catch {
  e => e.to_string()
}
// 2:5: not a number
```

`Refused::at` gives the offset, line and column without matching the ten variants;
`Show`, and so `to_string`, prints the position and the fault. The variants are `Unexpected`, `Truncated`, `BadEscape`,
`BadNumber`, `BadDate`, `Redefined`, `MixedArray`, `Trailing`, `TooDeep`, `BadUtf8`.

## Things that catch people out

- Redefinition is an error, not a policy. A key defined twice, a repeated header, a
  dotted key later opened by a header, a key added to a closed inline table — all
  refused, and there is no knob to accept them, because the format does not.
- `dumps` reads the spelling: a string that is a date-time becomes one in the
  output. Use `encode` when a string that looks like a date has to stay a string.
- `loads` and `dumps` keep the digits of a number only when JSON spells it the same
  way, so `0xff` and `1_000` come back written from their value; `decode` keeps the
  value itself.
- A document is a table. `encode` of anything else writes it under the one key
  `value`, so that it can be read back.
- Nesting stops at 500 levels. `Flavor::new(depth=64)` or
  `{ ..@moontoml.strict, depth: 64 }` raises or lowers it.
- A file is UTF-8 and has no byte-order mark, but `bom=true` is the default because
  editors on Windows write one anyway.
- An array is one kind of value until 1.0.0; a second kind is a `MixedArray`
  refusal at `v04` and `v05`, and a value from 1.0.0 on.
- `decode_doc` keeps the document, not a copy of its values: `get` and `set` reach
  the same tree, and a `set` that names nothing — a missing key, or a table where a
  value should stand — leaves the document as it was and answers nothing.
