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
///
/// A `Json` tree says "string" for what may have been a date-time, so this leans on
/// the spelling: a string that is a date-time is written as one. `encode` writes a
/// `Value` and needs no such guess.
pub fn dumps(value : Json, sort~ : Bool = false) -> String {
  encode(value_of_json(value), sort~)
}

///|
/// The same, as UTF-8 bytes.
pub fn dump(value : Json, sort~ : Bool = false) -> Bytes {
  @utf8.encode(dumps(value, sort~)[:])
}

///|
/// Write a tree of `Value` as a TOML document.
///
/// Each value keeps the kind it has: a `String` is quoted even when it reads like a
/// date, an `Integer` is written as the 64 bits it holds, and a `Datetime` is
/// written bare, because turning it into a quoted string would change what it is.
pub fn encode(value : Value, sort~ : Bool = false) -> String {
  let out = StringBuilder()
  match value {
    Table(fields) => ignore(table(out, fields, [], sort, false))
    _ =>
      // A document is a table; anything else is written as the one key a caller
      // can read back.
      ignore(table(out, { "value": value }, [], sort, false))
  }
  out.to_string()
}

///|
/// The same, as UTF-8 bytes.
pub fn encode_bytes(value : Value, sort~ : Bool = false) -> Bytes {
  @utf8.encode(encode(value, sort~)[:])
}

///|
/// One table's scalars, then its sub-tables under their own headers.
///
/// Answers whether anything has been written, which is what puts a blank line
/// between a header and what came before it, but not at the top of the document.
fn table(
  out : StringBuilder,
  fields : Map[String, Value],
  path : Array[String],
  sort : Bool,
  started : Bool,
) -> Bool {
  let names = fields.keys().collect()
  if sort {
    names.sort()
  }
  let mut has = started
  // Scalars first: a key written after a header would belong to that header.
  for name in names {
    let held = fields.get(name).unwrap()
    if !is_table(held) && !is_table_array(held) {
      write_key(out, name)
      out.write_string(" = ")
      write_value(out, held)
      out.write_char('\n')
      has = true
    }
  }
  for name in names {
    let held = fields.get(name).unwrap()
    let here = path + [name]
    match held {
      Table(inner) => {
        if has {
          out.write_char('\n')
        }
        out.write_char('[')
        write_path(out, here)
        out.write_string("]\n")
        has = table(out, inner, here, sort, true)
      }
      Array(items) =>
        if is_table_array(held) {
          for item in items {
            match item {
              Table(inner) => {
                if has {
                  out.write_char('\n')
                }
                out.write_string("[[")
                write_path(out, here)
                out.write_string("]]\n")
                has = table(out, inner, here, sort, true)
              }
              _ => ()
            }
          }
        }
      _ => ()
    }
  }
  has
}

///|
/// Whether a value is written under a header of its own.
fn is_table(v : Value) -> Bool {
  v is Table(_)
}

///|
/// Whether a value is an array every element of which is a table, which is the
/// only shape `[[…]]` can spell.
fn is_table_array(v : Value) -> Bool {
  match v {
    Array(items) => {
      if items.length() == 0 {
        return false
      }
      for item in items {
        if !(item is Table(_)) {
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
fn write_value(out : StringBuilder, value : Value) -> Unit {
  match value {
    String(s) => write_string(out, s)
    Integer(n) => out.write_string(n.to_string())
    Float(real) =>
      match real.repr {
        // The text a number was read from is kept, so a float writes back as it
        // came in.
        Some(text) => out.write_string(text)
        None => write_double(out, real.value)
      }
    Boolean(b) => out.write_string(if b { "true" } else { "false" })
    Datetime(m) => out.write_string(m.to_string())
    Array(items) => {
      out.write_char('[')
      for i = 0; i < items.length(); i = i + 1 {
        if i > 0 {
          out.write_string(", ")
        }
        write_value(out, items[i])
      }
      out.write_char(']')
    }
    Table(fields) => {
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
        write_value(out, fields.get(names[i]).unwrap())
      }
      out.write_string(" }")
    }
  }
}

///|
/// A float as TOML writes it.
///
/// A whole float still needs to read back as one, so it keeps a fractional part:
/// `12000.0`, not `12000`, which would be an integer.
fn write_double(out : StringBuilder, n : Double) -> Unit {
  if n.is_nan() {
    out.write_string("nan")
  } else if n.is_inf() {
    out.write_string(if n > 0.0 { "inf" } else { "-inf" })
  } else {
    let text = n.to_string()
    out.write_string(text)
    if !has_exponent(text) && index_of(text, 0x2e) < 0 {
      out.write_string(".0")
    }
  }
}

///|
fn has_exponent(text : String) -> Bool {
  for i = 0; i < text.length(); i = i + 1 {
    let c = text[i].to_int()
    if c == 0x65 || c == 0x45 {
      return true
    }
  }
  false
}

///|
/// A string in the form that reads back as itself.
fn write_string(out : StringBuilder, s : String) -> Unit {
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
/// Whether a string is one of the date-times this module reads, and so is written
/// back as one when it arrives as a `Json` string.
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
