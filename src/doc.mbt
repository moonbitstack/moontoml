// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A document that remembers how it was written.
///
/// The other entry points read a TOML document into a tree and forget the page it
/// came from. This one keeps the page: the source text, the items in the order
/// they were read, each with the bytes it occupied, and the tree they denote.
/// Change one value in place and write the result back, and the rest of the
/// document is byte for byte as it was — the comments, the blank lines, the order,
/// and the spelling of every value but the one that moved.
///
/// This is the reading for a file a person edits by hand — `moon.mod`, a service
/// config, a manifest — where the diff should be the one line that changed.
#derive(Debug)
pub(all) struct Doc {
  // The document as its bytes were read.
  src : String
  // The items, in the order the document holds them.
  mut items : Array[Item]
  // The tree the items point into.
  root : Value
}

///|
pub extend Doc with Debug::{to_repr}

///|
/// Read a document into a `Doc`, which keeps it as it was written.
///
/// `flavor` names the edition, the same as the other entry points. A document the
/// edition refuses is refused the same way `decode` refuses it.
pub fn Doc::decode(
  src : StringView,
  flavor~ : Flavor = strict,
) -> Doc raise Refused {
  check_text(src)
  let reader = Reader::new(src, flavor)
  reader.recording = true
  let root = reader.document()
  guard root is Table(_) else { abort("a document is a table") }
  { src: src.to_owned(), items: reader.rec_items, root, }
}

///|
/// The tree the document denotes — what `decode` answers for the same bytes.
pub fn Doc::value(self : Doc) -> Value {
  self.root
}

///|
/// The value a path names, or nothing when the path does not name a value.
///
/// A path is the segments of a key as a person writes them: `["soil", "ph"]` is
/// the key under the table a `[soil]` header opens, and `["a", "b"]` is the key
/// written `a.b`.
pub fn Doc::get(self : Doc, path : Array[String]) -> Value? {
  let mut here = self.root
  for i = 0; i < path.length(); i = i + 1 {
    match here {
      Table(fields) =>
        match fields.get(path[i]) {
          Some(held) => here = held
          None => return None
        }
      _ => return None
    }
  }
  Some(here)
}

///|
/// Change the value a path names, in place.
///
/// The path must name a value already in the document; when it names nothing — a
/// missing key, or a table where a value should stand — the answer is nothing and
/// the document is left as it was. Otherwise the value is replaced, the answer is
/// whether it actually moved, and the line that held it is the only one written
/// fresh when the document is written back.
pub fn Doc::set(self : Doc, path : Array[String], value : Value) -> Bool? {
  let key = path_key(path)
  // The item whose key is the path.
  let mut index = -1
  for i = 0; i < self.items.length(); i = i + 1 {
    let item = self.items[i]
    guard item.kind is Pair else { continue }
    if path_key(item.path) == key {
      index = i
      break
    }
  }
  if index < 0 {
    return None
  }
  // The table that holds the key, in the tree the items point into.
  let mut here = self.root
  for i = 0; i < path.length() - 1; i = i + 1 {
    match here {
      Table(fields) =>
        match fields.get(path[i]) {
          Some(held) => here = held
          None => return None
        }
      _ => return None
    }
  }
  guard here is Table(fields) else { return None }
  let name = path[path.length() - 1]
  guard fields.get(name) is Some(held) else { return None }
  let moved = held != value
  fields[name] = value
  let item = self.items[index]
  self.items[index] = { ..item, changed: true, }
  Some(moved)
}

///|
/// The document as it was read, with its changed values written back.
///
/// Nothing changed and the answer is the source byte for byte. A value that moved
/// is written where it occupied, the way this module writes one; the key, the
/// separator and anything after the value on the line are the original text, and
/// so is everything between the lines — the comments, the blank lines, the order.
pub fn Doc::render(self : Doc) -> String {
  let out = StringBuilder()
  let mut prev = 0
  for item in self.items {
    out.write_string(self.src[prev:item.start].to_owned())
    prev = item.end
    if item.kind is Pair && item.changed {
      out.write_string(self.src[item.start:item.vstart].to_owned())
      let value = StringBuilder()
      let held = item.value_of(self.root)
      write_value(value, held)
      out.write_string(value.to_string())
      out.write_string(self.src[item.vend:item.end].to_owned())
    } else {
      out.write_string(self.src[item.start:prev].to_owned())
    }
  }
  out.write_string(self.src[prev:].to_owned())
  out.to_string()
}

///|
/// The value an item of a document holds, walking the tree to its path.
pub fn Item::value_of(self : Item, root : Value) -> Value {
  let mut here = root
  for name in self.path {
    match here {
      Table(fields) =>
        match fields.get(name) {
          Some(held) => here = held
          None => return Value::string("")
        }
      _ => return Value::string("")
    }
  }
  here
}
