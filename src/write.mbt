// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Write a `Json` tree as a TOML document.
///
/// Tables go under their own headers and scalars stay at the level they are on, so
/// the output reads like a configuration file someone wrote rather than one a
/// program emitted. An array of tables is written as `[[…]]` when every one of its
/// elements is a table, and inline otherwise, which is the only honest choice: TOML
/// has no way to spell an array mixing tables with scalars across headers.
///
/// `sort` orders keys by name; off, they keep the order the tree has. A document
/// read by this module and written again carries the same values, but not
/// necessarily the same layout — TOML can spell the same tree several ways.
pub fn dumps(value : Json, sort~ : Bool = false) -> String {
  let out = StringBuilder()
  match value {
    Object(fields) => table(out, fields, [], sort)
    _ =>
      // A document is a table; anything else is written as the one key a caller
      // can read back.
      table(out, { "value": value }, [], sort)
  }
  out.to_string()
}

///|
/// The same, as UTF-8 bytes.
pub fn dump(value : Json, sort~ : Bool = false) -> Bytes {
  @utf8.encode(dumps(value, sort~)[:])
}

///|
/// One table's scalars, then its sub-tables under their own headers.
fn table(
  out : StringBuilder,
  fields : Map[String, Json],
  path : Array[String],
  sort : Bool,
) -> Unit {
  let names = fields.keys().collect()
  if sort {
    names.sort()
  }
  // Scalars first: a key written after a header would belong to that header.
  for name in names {
    let held = fields.get(name).unwrap()
    if !is_table(held) && !is_table_array(held) {
      write_key(out, name)
      out.write_string(" = ")
      write_inline(out, held)
      out.write_char('\n')
    }
  }
  for name in names {
    let held = fields.get(name).unwrap()
    let here = path + [name]
    match held {
      Object(inner) => {
        if out.to_string().length() > 0 {
          out.write_char('\n')
        }
        out.write_char('[')
        write_path(out, here)
        out.write_string("]\n")
        table(out, inner, here, sort)
      }
      Array(items) =>
        if is_table_array(held) {
          for item in items {
            match item {
              Object(inner) => {
                if out.to_string().length() > 0 {
                  out.write_char('\n')
                }
                out.write_string("[[")
                write_path(out, here)
                out.write_string("]]\n")
                table(out, inner, here, sort)
              }
              _ => ()
            }
          }
        }
      _ => ()
    }
  }
}

///|
/// Whether a value is written under a header of its own.
fn is_table(v : Json) -> Bool {
  v is Object(_)
}

///|
/// Whether a value is an array every element of which is a table, which is the
/// only shape `[[…]]` can spell.
fn is_table_array(v : Json) -> Bool {
  match v {
    Array(items) => {
      if items.length() == 0 {
        return false
      }
      for item in items {
        if !(item is Object(_)) {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
/// A dotted path, each segment quoted only if it has to be.
fn write_path(out : StringBuilder, path : Array[String]) -> Unit {
  for i = 0; i < path.length(); i = i + 1 {
    if i > 0 {
      out.write_char('.')
    }
    write_key(out, path[i])
  }
}

///|
/// A key bare when it can be, quoted when it cannot.
fn write_key(out : StringBuilder, name : String) -> Unit {
  if bare(name) {
    out.write_string(name)
  } else {
    quoted(out, name)
  }
}

///|
/// Whether a key may be written without quotes: letters, digits, underscore and
/// dash, and not empty (§Keys).
fn bare(name : String) -> Bool {
  if name.length() == 0 {
    return false
  }
  for i = 0; i < name.length(); i = i + 1 {
    let c = name[i].to_int()
    let ok = (c >= 0x41 && c <= 0x5a) ||
      (c >= 0x61 && c <= 0x7a) ||
      (c >= 0x30 && c <= 0x39) ||
      c == 0x5f ||
      c == 0x2d
    if !ok {
      return false
    }
  }
  true
}

///|
/// A value on one line: a scalar, an array, or an inline table.
fn write_inline(out : StringBuilder, value : Json) -> Unit {
  match value {
    Null =>
      // TOML has no null. A caller that needs one spells it, which is what every
      // encoder in reach does, and an empty string is the least surprising.
      out.write_string("\"\"")
    True => out.write_string("true")
    False => out.write_string("false")
    Number(n, repr~) =>
      match repr {
        // The text a number was read from is kept, so a value past what a Double
        // holds exactly writes back as the digits it came in as.
        Some(text) => out.write_string(text)
        None => write_number(out, n)
      }
    String(s) => write_string(out, s)
    Array(items) => {
      out.write_char('[')
      for i = 0; i < items.length(); i = i + 1 {
        if i > 0 {
          out.write_string(", ")
        }
        write_inline(out, items[i])
      }
      out.write_char(']')
    }
    Object(fields) => {
      out.write_char('{')
      let names = fields.keys().collect()
      for i = 0; i < names.length(); i = i + 1 {
        if i > 0 {
          out.write_string(", ")
        } else {
          out.write_char(' ')
        }
        write_key(out, names[i])
        out.write_string(" = ")
        write_inline(out, fields.get(names[i]).unwrap())
      }
      out.write_string(" }")
    }
  }
}

///|
/// A number as TOML writes it: a whole value with no fractional part, so a port is
/// `12000` rather than `12000.0`.
fn write_number(out : StringBuilder, n : Double) -> Unit {
  if n.is_nan() {
    out.write_string("nan")
  } else if n.is_inf() {
    out.write_string(if n > 0.0 { "inf" } else { "-inf" })
  } else if n == n.floor() && n.abs() < 1.0e15 {
    out.write_string(n.to_int64().to_string())
  } else {
    out.write_string(n.to_string())
  }
}

///|
/// A string in the form that reads back as itself.
///
/// A date-time that came in as one is written bare, because that is what it is:
/// this module reads TOML's four date-time types into their normalised text, so
/// quoting it on the way out would turn a timestamp into a string.
fn write_string(out : StringBuilder, s : String) -> Unit {
  if is_moment(s) {
    out.write_string(s)
    return
  }
  // A string with a line break in it goes in a multi-line literal when it can,
  // which is how a key or a script stays readable.
  if index_of(s, 0x0a) >= 0 &&
    index_of(s, 0x27) < 0 &&
    index_of(s, 0x5c) < 0 &&
    !has_control(s) {
    out.write_string("'''\n")
    out.write_string(s)
    out.write_string("'''")
    return
  }
  quoted(out, s)
}

///|
/// Whether a string is one of the date-times this module reads, and so should be
/// written back as one.
fn is_moment(s : String) -> Bool {
  if !dateish(s) {
    return false
  }
  try {
    let _ = @moondate.parse(s[:])
    true
  } catch {
    _ => false
  }
}

///|
fn has_control(s : String) -> Bool {
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int()
    if (c < 0x20 && c != 0x0a && c != 0x09) || c == 0x7f {
      return true
    }
  }
  false
}

///|
/// A basic string with the escapes TOML defines.
fn quoted(out : StringBuilder, s : String) -> Unit {
  out.write_char('"')
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int()
    match c {
      0x22 => out.write_string("\\\"")
      0x5c => out.write_string("\\\\")
      0x0a => out.write_string("\\n")
      0x0d => out.write_string("\\r")
      0x09 => out.write_string("\\t")
      0x08 => out.write_string("\\b")
      0x0c => out.write_string("\\f")
      _ =>
        if c < 0x20 || c == 0x7f {
          out.write_string("\\u")
          for shift in [12, 8, 4, 0] {
            out.write_char(
              "0123456789abcdef"[(c >> shift) & 0xf].unsafe_to_char(),
            )
          }
        } else {
          out.write_char(s[i].unsafe_to_char())
        }
    }
  }
  out.write_char('"')
}
