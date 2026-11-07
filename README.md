<div align="center">

<h1>moontoml</h1>

<p><b>TOML for MoonBit, at the edition the file was written in.</b><br>
Read a document into a <code>Json</code> tree or kind for kind, write it back, keep the
comments and order of the ones a person edits, and get a line and a column when it
refuses.</p>

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
let src = "title = \"field notes\"\nbeds = 4\n\n[soil]\nkind = \"loam\"\nph = 6.5\n"
let doc = @moontoml.loads(src[:])
assert_eq(
  @moontoml.dumps(doc),
  "title = \"field notes\"\nbeds = 4\n\n[soil]\nkind = \"loam\"\nph = 6.5\n",
)
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

## The third reading: the document, kept

A tree forgets the page it came from. `decode_doc` does not: it keeps the source, the items
in the order they were read, and the comment or blank line before each one. Change one value
in place and write the result back, and the rest of the document is byte for byte as it was.

```moonbit
let doc = @moontoml.decode_doc("beds = 4  # the ones that get sun\nsoil = \"loam\"\n")
assert_eq(doc.set(["beds"], @moontoml.Value::integer(6)), Some(true))
// the comment and the order are the source; only the value moved
assert_eq(doc.render(), "beds = 6  # the ones that get sun\nsoil = \"loam\"\n")
```

`get` reaches a value by path and `set` replaces one in place; `render` answers the document.
A path is the segments of a key, `["soil", "ph"]` being the key under a `[soil]` header. When
the path names nothing — a missing key, or a table where a value should stand — `set` answers
nothing and the document is left as it was. This is the reading for `moon.mod`, a service
config, a manifest: the diff is the one line that changed.

## The editions

The root reads TOML 1.0.0. The editions are subpackages with the same entry points, pinned to
their grammar, because the editions differ by real rules:

```moonbit
// 0.4 has no dotted keys, no hex or binary integers, no inf, and only the offset date-time.
let src = "a.b = 1\n"
let refused = try {
  let _ = @v04.loads(src[:])
  false
} catch {
  _ => true
}
assert_eq(refused, true)

// 0.5 adds dotted keys, prefixed integers, inf and nan, and the local date-time kinds.
assert_eq(@v05.loads("a.b = 1\n"[:]).stringify(), "{\"a\":{\"b\":1}}")

// 1.1 lets an inline table span lines and end with a comma.
assert_eq(
  @v110.loads("p = { x = 1,\n y = 2,\n}"[:]).stringify(),
  "{\"p\":{\"x\":1,\"y\":2}}",
)
```

| Edition | The grammar |
|:--:|---|
| `moonbitstack/moontoml` | 1.0.0 — dotted keys, prefixed integers, mixed-type arrays, one-line inline tables |
| `…/moontoml/v110` | 1.1 — inline tables that span lines with a trailing comma, `\x` and `\e` escapes, a time that may drop its seconds |
| `…/moontoml/v05` | 0.5 — dotted keys, prefixed integers, `inf`/`nan`, the local date-time kinds; arrays are one kind |
| `…/moontoml/v04` | 0.4 — no dotted keys, no prefixed integers, no `inf`/`nan`, only the offset date-time |

The same `decode`, `loads`, `encode`, `dumps`, `decode_doc` and `Value` in every one; only the
edition moves. A `Flavor::new(edition=…)` on the root reads any of them without the subpackage.

## Reading values

A `Json` is read by shape. `Object` is a table, `String` a string, and a missing key is `None`.

```moonbit
let doc = @moontoml.loads("title = \"field notes\"\nbeds = 4"[:])
guard doc is Object(root) else { abort("a document is a table") }
let title = match root.get("title") {
  Some(String(s)) => s
  _ => "?"
}
let beds = match root.get("beds") {
  Some(Number(n, ..)) => n.to_int()
  _ => 0
}
assert_eq((title, beds), ("field notes", 4))
```

## Kinds, kept

A `Value` is read by kind. A date is a `Datetime` and a string is a `String`, even when the
string is written like a date:

```moonbit
let doc = @moontoml.decode("port = 12000\nwhen = 1979-05-27\nname = \"1979-05-27\"\n")
guard doc is Table(fields) else { abort("a document is a table") }
guard fields.get("when") is Some(Datetime(m)) else { abort("a date") }
assert_eq(m.to_string(), "1979-05-27")
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
let doc = @moontoml.loads("b = 1\na = 2"[:])
assert_eq(@moontoml.dumps(doc), "b = 1\na = 2\n")
assert_eq(@moontoml.dumps(doc, sort=true), "a = 2\nb = 1\n")
```

A document read and written again keeps its values, not its layout. TOML can spell the same tree
several ways; this writer picks one.

`dumps` starts from a `Json` tree, which cannot say whether a string was a date, so it leans on
the spelling: a string that is a date-time is written as one. `encode` starts from a `Value` and
needs no such reading. `decode_doc` keeps the layout itself, the `Doc`, and writes it back as it
was.

## The interface

<table>
<tr><th>Call</th><th>Takes</th><th>Gives</th></tr>
<tr><td><code>loads</code></td><td><code>StringView</code>, <code>flavor?</code></td><td><code>Json</code>, or raises <code>Refused</code></td></tr>
<tr><td><code>load</code></td><td><code>BytesView</code>, <code>flavor?</code>, <code>bom?</code></td><td><code>Json</code>, or raises <code>Refused</code></td></tr>
<tr><td><code>dumps</code></td><td><code>Json</code>, <code>sort?</code></td><td><code>String</code></td></tr>
<tr><td><code>dump</code></td><td><code>Json</code>, <code>sort?</code></td><td><code>Bytes</code></td></tr>
<tr><td><code>decode</code></td><td><code>StringView</code>, <code>flavor?</code></td><td><code>Value</code>, or raises <code>Refused</code></td></tr>
<tr><td><code>decode_bytes</code></td><td><code>BytesView</code>, <code>flavor?</code>, <code>bom?</code></td><td><code>Value</code>, or raises <code>Refused</code></td></tr>
<tr><td><code>decode_doc</code></td><td><code>StringView</code>, <code>flavor?</code></td><td><code>Doc</code>, or raises <code>Refused</code></td></tr>
<tr><td><code>encode</code></td><td><code>Value</code>, <code>sort?</code></td><td><code>String</code></td></tr>
<tr><td><code>encode_bytes</code></td><td><code>Value</code>, <code>sort?</code></td><td><code>Bytes</code></td></tr>
</table>

The subpackages <code>v04</code>, <code>v05</code> and <code>v110</code> expose the same names pinned to their
edition, plus their own <code>decode_doc</code>.

<table>
<tr><th>Type</th><th>What it holds</th></tr>
<tr><td><code>Value</code></td><td>a value of any of the seven kinds, as the format defines them</td></tr>
<tr><td><code>Real</code></td><td>a float: the number, and the text it was written as when there was one</td></tr>
<tr><td><code>Doc</code></td><td>a document kept as it was written; <code>get</code>, <code>set</code>, <code>render</code></td></tr>
<tr><td><code>Edition</code></td><td>the grammar a document is read under: <code>V04</code>, <code>V05</code>, <code>V100</code>, <code>V110</code></td></tr>
<tr><td><code>At</code></td><td>the offset, the line and the column of a place in the source</td></tr>
<tr><td><code>Refused</code></td><td>the ten faults, each with an <code>At</code>; <code>Refused::at</code> reaches it</td></tr>
<tr><td><code>Flavor</code></td><td>what a reader has: the <code>edition</code> and a <code>depth</code></td></tr>
<tr><td><code>strict</code>, <code>depth</code></td><td>the preset flavor — 1.0.0, nesting 500 — and its limit</td></tr>
</table>

## What it reads

Everything TOML 1.0.0 defines: bare, quoted and dotted keys; `[table]` and `[[array of tables]]`
headers; the four string forms with their escapes and the line-ending backslash; integers in
decimal, hexadecimal, octal and binary with digit-grouping underscores; floats with exponents and
`inf`/`nan`; the four date-time types; arrays that span lines; and inline tables. The editions
read the same document at their own rules, so a `0.5` file is refused of a `0.4` and a `1.1`
file of a `1.0.0`, and read in full at its own.

## What it refuses

TOML's redefinition rules, which are what make a file safe to append to:

- A key defined twice.
- A table header repeated.
- A dotted key later opened by a header.
- A key added to an inline table after its brace closed.
- `[[…]]` over something that is not an array of tables.

Also a leading zero on a multi-digit integer, an underscore not between two digits of one base, a
float missing a digit on either side of its dot, a trailing comma in an inline table, a control
character anywhere but a tab or a line break, a date-time that is not spelled the way the
format spells one, and a second kind in an array at an edition before mixed ones — all of
which the editions refuse.

Every refusal carries an `At`. The ten kinds are `Unexpected`, `Truncated`, `BadEscape`,
`BadNumber`, `BadDate`, `Redefined`, `MixedArray`, `Trailing`, `TooDeep` and `BadUtf8`.

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

The reader and the writer are checked against `toml-test`, the format's own suite, at the editions
it lists — 1.0.0 and 1.1.0 — over every file each edition names:

| Suite | Edition | Documents | Passing |
|---|:--:|---|---|
| valid, read as the tree the suite expects | 1.0.0 | 205 | 205 |
| valid, written by the library and read back | 1.0.0 | 205 | 205 |
| invalid, refused | 1.0.0 | 474 | 474 |
| valid, read as the tree the suite expects | 1.1.0 | 214 | 214 |
| valid, written by the library and read back | 1.1.0 | 214 | 214 |
| invalid, refused | 1.1.0 | 467 | 467 |
| valid, read into the `Doc` and written back byte for byte | 1.0.0 | 205 | 205 |
| valid, read into the `Doc` and written back byte for byte | 1.1.0 | 214 | 214 |

Nothing is skipped, and no case is expected to fail. The 0.4 and 0.5 editions have no `toml-test`
file list of their own, so they are checked against the edition they grow from — every document
1.0.0 refuses of a 0.5, and every document 0.5 refuses of a 0.4 — plus the feature set each
introduced. The corpus is generated into the test sources by `scripts/gen_vectors.py`, which pins
the release and checks its digest, so the numbers above are the ones the tests assert on every
backend.

## Examples

| Example | What it shows |
|---|---|
| [`src/examples/basic`](https://github.com/moonbitstack/moontoml/tree/master/src/examples/basic) | read, change one value, write back — once as a tree, once as the document kept with its comments and order |
| [`src/examples/integration`](https://github.com/moonbitstack/moontoml/tree/master/src/examples/integration) | a site config read into a struct, changed, written back sorted, and a refusal reported by line |

```bash
moon run src/examples/basic
moon run src/examples/integration
```

## Licence

Apache-2.0. See [LICENSE](LICENSE).
