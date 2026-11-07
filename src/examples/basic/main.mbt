// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A small, complete use of moontoml: read a config, pull two values out, change
// one, and write the document back — once as a tree, once as the document kept.
//
// Run it with `moon run src/examples/basic`. The first part is the four steps on
// the tree: load, read, edit, dump. The second is the same change through the
// document, where the write back keeps the comments and the order.

///|
fn main raise {
  let src =
    #|# a garden, planted 1979
    #|name = "garden"  # the one by the gate
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

  // 4. Write. `dumps` returns the whole tree as a TOML document. The values moved,
  //    and the new key landed; the layout is the writer's, not the file's.
  println("written from the tree:")
  println(@moontoml.dumps(doc))

  // 5. The same change through the document, which keeps it as it was written:
  //    read, change one value in place, and write it back.
  let page = @moontoml.decode_doc(src[:])
  let moved = page.set(["beds"], @moontoml.Value::integer(6)) is Some(true)
  println("the document kept, one value moved: \{moved}")
  println("written from the document:")
  println(page.render())
}
