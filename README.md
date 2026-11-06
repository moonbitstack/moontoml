<div align="center">

<h1>moontoml</h1>

<p><b>TOML 1.0.0 for MoonBit.</b><br>
Read a document into a <code>Json</code> tree or kind for kind, write it back, and get a line and a
column when it refuses.</p>

<p>
<a href="https://moonbitstack.github.io/moontoml/">Home</a> ·
<a href="https://moonbitstack.github.io/moontoml/guide.html">Guide</a> ·
<a href="https://moonbitstack.github.io/moontoml/api.html">API</a> ·
<a href="https://mooncakes.io/docs/moonbitstack/moontoml">mooncakes</a>
</p>

</div>

---

```bash
moon add moonbitstack/moontoml
```

A document goes in, a tree comes out. Write the tree back and the values are the same.

```moonbit
///|
fn main raise {
  let src =
    #|title = "field notes"
    #|beds = 4
    #|
    #|[soil]
    #|kind = "loam"
    #|ph = 6.5

  let doc = @moontoml.loads(src[:])
  println(@moontoml.dumps(doc))
}
```

```toml
title = "field notes"
beds = 4

[soil]
kind = "loam"
ph = 6.5
```

## Two readings

`loads` gives a `Json` tree: seven kinds of value, five of them in a form `Json` has.
`decode` gives a tree of `Value`, which keeps every distinction the format makes. The
difference is a date-time and a 64-bit integer, the two places where `Json` is narrower
than TOML.

| TOML | `loads` | `decode` | Example |
|---|---|---|---|
| string | `String` | `String(String)` | `"loam"` |
| integer | `Number` | `Integer(Int64)` | `42`, `0x2A`, `0o52`, `0b101010` |
| float | `Number` | `Float(Real)` | `1.5`, `5e+22`, `inf`, `nan` |
| boolean | `True` / `False` | `Boolean(Bool)` | `true` |
| date-time | `String` | `Datetime(Moment)` | `1979-05-27T07:32:00Z` |
| array | `Array` | `Array(Array[Value])` | `[1, 2, 3]` |
| table | `Object` | `Table(Map[String, Value])` | `{ x = 1 }` |

Both readings accept the same documents and refuse the same ones; they differ only in what
comes out.

## Reading values

A `Json` is read by shape. `Object` is a table, `String` a string, and a missing key is `None`.

```moonbit
///|
fn main raise {
  let src =
    #|title = "field notes"
    #|beds = 4
  let doc = @moontoml.loads(src[:])
  guard doc is Object(root) else { abort("a document is a table") }
  let title = match root.get("title") {
    Some(String(s)) => s
    _ => "?"
  }
  let beds = match root.get("beds") {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
  println("\{title}, \{beds} beds")
}
```

```
field notes, 4 beds
```

## Kinds, kept

A `Value` is read by kind. A date is a `Datetime` and a string is a `String`, even when the
string is written like a date:

```moonbit
///|
fn main raise {
  let doc = @moontoml.decode("port = 12000\nwhen = 1979-05-27\nname = \"1979-05-27\"\n")
  guard doc is Table(fields) else { abort("a document is a table") }
  guard fields.get("when") is Some(Datetime(m)) else { abort("a date") }
  println(m.to_string())
  println(@moontoml.encode(doc))
}
```

```
1979-05-27
port = 12000
when = 1979-05-27
name = "1979-05-27"
```

That is the whole point of the second reading: `encode` writes a `String` quoted and a
`Datetime` bare, so a value keeps the kind it had, and no guess is made from the spelling.

The four date-time kinds of the format are the four of `Moment`, which is `moondate`'s type:
an offset date-time, a local date-time, a local date and a local time. `Integer` holds all 64
bits, so a value past what a double holds exactly comes back as itself.

## Writing it back

`dumps` writes scalars at the level they are on and puts tables under their own headers. The order
is the tree's own; `sort=true` orders keys by name.

```moonbit
///|
fn main raise {
  let doc = @moontoml.loads("b = 1\na = 2\n"[:])
  println(@moontoml.dumps(doc))              // b = 1, then a = 2
  println(@moontoml.dumps(doc, sort=true))   // a = 2, then b = 1
}
```

A document read and written again keeps its values, not its layout. TOML can spell the same tree
several ways; this writer picks one.

`dumps` starts from a `Json` tree, which cannot say whether a string was a date, so it leans on
the spelling: a string that is a date-time is written as one. `encode` starts from a `Value` and
needs no such reading.

## The interface

<table>
<tr><th>Call</th><th>Takes</th><th>Gives</th></tr>
<tr><td><code>loads</code></td><td><code>StringView</code>, <code>flavor?</code></td><td><code>Json</code>, or raises <code>Refused</code></td></tr>
<tr><td><code>load</code></td><td><code>BytesView</code>, <code>flavor?</code>, <code>bom?</code></td><td><code>Json</code>, or raises <code>Refused</code></td></tr>
<tr><td><code>dumps</code></td><td><code>Json</code>, <code>sort?</code></td><td><code>String</code></td></tr>
<tr><td><code>dump</code></td><td><code>Json</code>, <code>sort?</code></td><td><code>Bytes</code></td></tr>
<tr><td><code>decode</code></td><td><code>StringView</code>, <code>flavor?</code></td><td><code>Value</code>, or raises <code>Refused</code></td></tr>
<tr><td><code>decode_bytes</code></td><td><code>BytesView</code>, <code>flavor?</code>, <code>bom?</code></td><td><code>Value</code>, or raises <code>Refused</code></td></tr>
<tr><td><code>encode</code></td><td><code>Value</code>, <code>sort?</code></td><td><code>String</code></td></tr>
<tr><td><code>encode_bytes</code></td><td><code>Value</code>, <code>sort?</code></td><td><code>Bytes</code></td></tr>
</table>

<table>
<tr><th>Type</th><th>What it holds</th></tr>
<tr><td><code>Value</code></td><td>a value of any of the seven kinds, as the format defines them</td></tr>
<tr><td><code>Real</code></td><td>a float: the number, and the text it was written as when there was one</td></tr>
<tr><td><code>At</code></td><td>the offset, the line and the column of a place in the source</td></tr>
<tr><td><code>Refused</code></td><td>the nine faults, each with an <code>At</code>; <code>Refused::at</code> reaches it</td></tr>
<tr><td><code>Flavor</code></td><td>the one limit a reader has: <code>depth</code></td></tr>
<tr><td><code>strict</code>, <code>depth</code></td><td>the preset flavor and its nesting limit, 500</td></tr>
</table>

## What it reads

Everything TOML 1.0.0 defines: bare, quoted and dotted keys; `[table]` and `[[array of tables]]`
headers; the four string forms with their escapes and the line-ending backslash; integers in
decimal, hexadecimal, octal and binary with digit-grouping underscores; floats with exponents and
`inf`/`nan`; the four date-time types; arrays that span lines; and inline tables.

## What it refuses

TOML's redefinition rules, which are what make a file safe to append to:

- A key defined twice.
- A table header repeated.
- A dotted key later opened by a header.
- A key added to an inline table after its brace closed.
- `[[…]]` over something that is not an array of tables.

Also a leading zero on a multi-digit integer, an underscore not between two digits of one base, a
float missing a digit on either side of its dot, a trailing comma in an inline table, a control
character anywhere but a tab or a line break, and a date-time that is not spelled the way the
format spells one — all of which TOML 1.0.0 forbids.

Every refusal carries an `At`. The nine kinds are `Unexpected`, `Truncated`, `BadEscape`,
`BadNumber`, `BadDate`, `Redefined`, `Trailing`, `TooDeep` and `BadUtf8`.

## Dates and integers

Two places where a `Json` tree is narrower than the format, and what each reading does about them.

**Dates become text.** `loads` reads a date-time as its RFC 3339 form, and writes it back bare
rather than quoted, so a timestamp stays a timestamp. `decode` reads it as a `Datetime`, which is
the four kinds of the format. A date that does not exist, like `1979-02-30`, is refused by both.

**Integers keep their digits.** `decode` holds an integer in 64 bits, so every value the format
allows survives exactly. `loads` has only a double, which is exact to 2^53, so the digits a number
was written as travel beside the value whenever RFC 8259 spells it the same way, and
`9007199254740993` writes back as itself. A spelling RFC 8259 does not share — `+99`, `0xff`,
`1_000`, `inf` — carries no text and is written from the value.

## Conformance

The reader and the writer are checked against `toml-test` v2.2.0, the format's own suite, over the
files it lists for TOML 1.0.0:

| Suite | Documents | Passing |
|---|---|---|
| valid, read as the tree the suite expects | 205 | 205 |
| valid, written by the library and read back | 205 | 205 |
| invalid, refused | 474 | 474 |

Nothing is skipped, and no case is expected to fail. The corpus is generated into the test sources
by `scripts/gen_vectors.py`, which pins the release and checks its digest, so the numbers above are
the ones the tests assert on every backend.

## Examples

| Example | What it shows |
|---|---|
| [`src/examples/basic`](https://github.com/moonbitstack/moontoml/tree/master/src/examples/basic) | the four steps: load, read, edit, dump |
| [`src/examples/integration`](https://github.com/moonbitstack/moontoml/tree/master/src/examples/integration) | a site config read into a struct, changed, written back sorted, and a refusal reported by line |

```bash
moon run src/examples/basic
moon run src/examples/integration
```

## Licence

Apache-2.0. See [LICENSE](LICENSE).
