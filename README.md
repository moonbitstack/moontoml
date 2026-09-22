# moontoml

TOML 1.0.0, read and written as the `Json` tree every other reader in this family
produces. It is the format MoonBit's own `moon.mod` and `moon.pkg` are written in.

```moonbit
let config = @moontoml.loads(
  #|name = "moonbitstack/moontoml"
  #|version = "0.1.0"
  #|keywords = [ "toml", "config" ]
  #|
  #|[import]
  #|"moonbitstack/moondate" = "0.1.0"
)

@moontoml.dumps(config)     // back to TOML, tables under their own headers
```

## What it reads

Everything TOML 1.0.0 defines: bare, quoted and dotted keys; `[table]` and
`[[array of tables]]` headers; the four string forms with their escapes and the
line-ending backslash; integers in decimal, hexadecimal, octal and binary with
digit-grouping underscores; floats with exponents and `inf`/`nan`; the four
date-time types; arrays that span lines; and inline tables.

## The two places the tree is narrower than the format

**Date-times become their normalised text.** TOML has four date-time types and JSON
has none. They are read through [`moondate`](https://github.com/moonbitstack/moondate),
so `1979-02-30` is refused rather than kept as a string, and what lands in the tree
is the RFC 3339 form — `1979-05-27T07:32:00Z`. The writer writes them back bare
rather than quoted, so a document round-trips as a date and not as a string. A
caller that must tell a date from a string spelling one needs the values, not the
tree; that is what a richer model would be for.

**Integers are a `Double`, but their text survives.** A `Json` number is a double,
which is exact only to 2^53. The digits a number was written as are carried
alongside it when JSON spells it the same way, so `9007199254740993` writes back as
itself even though arithmetic on it would not be exact. A spelling JSON does not
share — `+99`, `0xff`, `1_000`, `inf` — carries no text and is written from the
value.

## What it refuses

TOML's redefinition rules, which are what make a file safe to append to. A key
defined twice, a header repeated, a dotted key later opened by a header, a key
added to an inline table after its brace closed, `[[…]]` over something that is not
an array of tables. Each raises `Refused` with a line and column.

Also a leading zero on a multi-digit integer, an underscore not between two digits,
a float missing a digit on either side of its dot, and a trailing comma in an
inline table — all of which TOML 1.0.0 forbids and some parsers tolerate.

## Configuration

```moonbit
@moontoml.loads(src, flavor=@moontoml.Flavor::new(depth=64))
@moontoml.load(bytes, bom=false)
```

`depth` is 500, the same as this family's JSON and YAML. `bom` skips a leading
byte-order mark; TOML says a file has none, so `bom=false` holds it to that.

There is no knob for a repeated key. §1 makes redefinition an error rather than a
policy, so offering to ignore it would be offering to read something that is not a
TOML document.

## What is not here

TOML 0.4, 0.5 and the 1.1 preview, which differ in real ways — 0.4 has no dotted
keys, 0.5 added the time types and hexadecimal, 1.0.0 tightened the table rules.
They are planned as packages beside this one, so choosing a version is choosing a
package.

Comment preservation. A document read and written again keeps its values, not its
layout: TOML can spell the same tree several ways and this writer picks one.

## Install

```bash
moon add moonbitstack/moontoml
```

## Licence

Apache-2.0. See [LICENSE](LICENSE).
