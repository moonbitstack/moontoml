// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A small, complete use of moontoml: read a config, pull two values out of the
// tree, change one, and write the whole document back.
//
// Run it with `moon run examples/basic`. The point is the four steps in the
// middle: load, read, edit, dump.

///|
fn main raise {
  let src =
    #|name = "garden"
    #|beds = 4
    #|
    #|[soil]
    #|kind = "loam"
    #|ph = 6.5
    #|

  // 1. Read. `loads` takes a `StringView`; `[:]` borrows the `String` as one.
  //    A document is always a table, so `doc` is a `Json` object.
  let doc = @moontoml.loads(src[:])

  // 2. Read values. A `Json` is matched by shape; a missing key is `None`.
  guard doc is Object(root) else { abort("a document is a table") }
  let name = match root.get("name") {
    Some(String(s)) => s
    _ => "?"
  }
  let beds = match root.get("beds") {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
  println("read: \{name}, \{beds} beds")

  // 3. Edit. Tables are mutable in place, and a new key can be added the same way.
  root["beds"] = Json::number(6)
  root["sun"] = Json::boolean(true)

  // 4. Write. `dumps` returns the whole tree as a TOML document.
  println(@moontoml.dumps(doc))
}
