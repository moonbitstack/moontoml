<div align="center">

<h1>moontoml</h1>

<p><b>TOML 1.0.0 for MoonBit.</b><br>
Read a document into a <code>Json</code> tree, write it back, and get a line and a column when it refuses.</p>

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

## What a document becomes

TOML has seven kinds of value, and each one has a place in a `Json` tree:

<table>
<tr><th>TOML</th><th>Json</th><th>Example</th></tr>
<tr><td>string</td><td><code>String</code></td><td><code>"loam"</code></td></tr>
<tr><td>integer</td><td><code>Number</code></td><td><code>42</code>, <code>0x2A</code>, <code>0o52</code>, <code>0b101010</code></td></tr>
<tr><td>float</td><td><code>Number</code></td><td><code>1.5</code>, <code>5e+22</code>, <code>inf</code>, <code>nan</code></td></tr>
<tr><td>boolean</td><td><code>True</code> / <code>False</code></td><td><code>true</code></td></tr>
<tr><td>date-time</td><td><code>String</code></td><td><code>1979-05-27T07:32:00Z</code></td></tr>
<tr><td>array</td><td><code>Array</code></td><td><code>[1, 2, 3]</code></td></tr>
<tr><td>table</td><td><code>Object</code></td><td><code>{ x = 1 }</code></td></tr>
</table>

A date comes out as the RFC 3339 form, not the text it went in as: `2026-03-01 09:30:00Z`
becomes `2026-03-01T09:30:00Z`. A date the calendar does not have is refused.

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

## Writing it back

`dumps` writes scalars at the level they are on and puts tables under their own headers. The order
is the tree's own; `sort=true` orders keys by name.

```moonbit
let doc = @moontoml.loads("b = 1\na = 2\n"[:])
println(@moontoml.dumps(doc))              // b = 1
                                          // a = 2
println(@moontoml.dumps(doc, sort=true))   // a = 2
                                          // b = 1
```

A document read and written again keeps its values, not its layout. TOML can spell the same tree
several ways; this writer picks one.

## The interface

<table>
<tr><th>Call</th><th>Takes</th><th>Gives</th></tr>
<tr><td><code>loads</code></td><td><code>StringView</code></td><td><code>Json</code>, or raises <code>Refused</code></td></tr>
<tr><td><code>load</code></td><td><code>BytesView</code>, <code>flavor?</code>, <code>bom?</code></td><td><code>Json</code>, or raises <code>Refused</code></td></tr>
<tr><td><code>dumps</code></td><td><code>Json</code>, <code>sort?</code></td><td><code>String</code></td></tr>
<tr><td><code>dump</code></td><td><code>Json</code>, <code>sort?</code></td><td><code>Bytes</code></td></tr>
</table>

<table>
<tr><th>Type</th><th>What it holds</th></tr>
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

Also a leading zero on a multi-digit integer, an underscore not between two digits, a float missing
a digit on either side of its dot, and a trailing comma in an inline table — all of which TOML 1.0.0
forbids.

Every refusal carries an `At`. The nine kinds are `Unexpected`, `Truncated`, `BadEscape`,
`BadNumber`, `BadDate`, `Redefined`, `Trailing`, `TooDeep` and `BadUtf8`.

## Dates and integers

Two places where a `Json` tree is narrower than the format, and what is done about each.

**Dates become text.** TOML has four date-time types and a tree of `Json` nodes has none. They are
read as their RFC 3339 form, and written back bare rather than quoted, so a timestamp stays a
timestamp and not a string. A date that does not exist, like `1979-02-30`, is refused.

**Integers keep their digits.** A `Json` number is a double, which is exact only to 2^53. The digits
a number was written as travel beside the value whenever RFC 8259 spells it the same way, so
`9007199254740993` writes back as itself. A spelling RFC 8259 does not share — `+99`, `0xff`,
`1_000`, `inf` — carries no text and is written from the value.

## Examples

| Example | What it shows |
|---|---|
| [`examples/basic`](https://github.com/moonbitstack/moontoml/tree/master/examples/basic) | the four steps: load, read, edit, dump |
| [`examples/integration`](https://github.com/moonbitstack/moontoml/tree/master/examples/integration) | a site config read into a struct, changed, written back sorted, and a refusal reported by line |

```bash
moon run examples/basic
moon run examples/integration
```

## Licence

Apache-2.0. See [LICENSE](LICENSE).
