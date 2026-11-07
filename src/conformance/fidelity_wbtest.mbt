// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The whole of `toml-test`'s TOML 1.0.0 corpus read into the `Doc`, which is
/// the fidelity reading.
///
/// The guarantee is byte for byte: a document read and written back with nothing
/// changed is the source. That holds for every document in the suite, and the
/// mutation tests below are what keep it honest.
test "toml-test: every valid document round-trips byte for byte" {
  let failures : Array[String] = []
  let mut count = 0
  for case in accepted() {
    count = count + 1
    let text = @utf8.decode(case.src, ignore_bom=false) catch {
      _ => {
        failures.push("\{case.name}: not UTF-8")
        continue
      }
    }
    let outcome = try {
      let doc = @moontoml.Doc::decode(text[:])
      if doc.render() != text {
        "the write back is not the source"
      } else {
        ""
      }
    } catch {
      why => "\{why.to_string()}"
    }
    if outcome != "" {
      failures.push("\{case.name}: \{outcome}")
    }
  }
  report("fidelity", count, failures)
}

///|
/// The mutation the fidelity guarantee is meant to catch: a comment that belongs
/// to one line must not move when that line is the one that changes.
test "a comment that hangs on a line stays put when the line changes" {
  let src = "a = 1  # a comment on this line\nb = 2\nc = 3\n"
  let doc = @moontoml.Doc::decode(src[:])
  let moved = doc.set(["b"], @moontoml.Value::integer(20))
  assert_eq(moved, Some(true))
  let out = doc.render()
  // The comment stays on line one, and the two lines around it are byte for byte.
  assert_eq(out, "a = 1  # a comment on this line\nb = 20\nc = 3\n")
}

///|
/// The second mutation: the order of the keys is the document's, and changing a
/// value in the middle does not reorder anything.

///|
test "changing a middle value keeps the order of the keys" {
  let src = "b = 1\na = 2\nz = 3\n"
  let doc = @moontoml.Doc::decode(src[:])
  let _ = doc.set(["a"], @moontoml.Value::integer(99))
  let out = doc.render()
  assert_eq(out, "b = 1\na = 99\nz = 3\n")
}

///|
/// A value that does not move is not marked moved, and the document is unchanged.

///|
test "setting a value to what it is, is not a move" {
  let src = "a = 1\n"
  let doc = @moontoml.Doc::decode(src[:])
  let moved = doc.set(["a"], @moontoml.Value::integer(1))
  assert_eq(moved, Some(false))
  assert_eq(doc.render(), src)
}

///|
/// A key that is not in the document is left alone, and nothing is invented.

///|
test "a key that is not there is refused" {
  let doc = @moontoml.Doc::decode("a = 1\n"[:])
  assert_eq(doc.set(["nope"], @moontoml.Value::integer(1)), None)
  assert_eq(doc.set(["a", "b"], @moontoml.Value::integer(1)), None)
  // And a table a value should stand in for.
  let doc = @moontoml.Doc::decode("[t]\nx = 1\n"[:])
  assert_eq(doc.set(["t"], @moontoml.Value::integer(1)), None)
}

///|
/// The value a path names comes back as the tree it is.

///|
test "get gives the value the path names" {
  let doc = @moontoml.Doc::decode("[t]\nx = 1\ny = \"two\"\n"[:])
  assert_eq(doc.get(["t", "x"]), Some(@moontoml.Value::integer(1)))
  assert_eq(doc.get(["t", "y"]), Some(@moontoml.Value::string("two")))
  assert_eq(doc.get(["t", "z"]), None)
  assert_eq(doc.get([]), Some(doc.value()))
}

///|
/// A date-time, a float and a 64-bit integer each write back as their kind.

///|
test "a changed value is written as the kind it is" {
  let doc = @moontoml.Doc::decode("n = 1\n"[:])
  let _ = doc.set(["n"], @moontoml.Value::integer(9007199254740993))
  assert_eq(doc.render(), "n = 9007199254740993\n")
  let doc = @moontoml.Doc::decode("s = \"x\"\n"[:])
  let _ = doc.set(["s"], @moontoml.Value::string("a\nb"))
  // A string with a line break is written in the form a person would write.
  assert_eq(doc.render(), "s = '''\na\nb'''\n")
}
