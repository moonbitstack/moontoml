// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A document as the compact JSON it denotes.
fn j(src : String) -> String raise Refused {
  loads(src[:]).stringify()
}

///|
test "a key-value pair, as the specification's first example" {
  assert_eq(j("key = \"value\""), "{\"key\":\"value\"}")
  assert_eq(
    j("bare_key = 1\nbare-key = 2\n1234 = 3"),
    "{\"bare_key\":1,\"bare-key\":2,\"1234\":3}",
  )
  // Quoted keys, both forms.
  assert_eq(
    j("\"127.0.0.1\" = 1\n'key two' = 2"),
    "{\"127.0.0.1\":1,\"key two\":2}",
  )
  // A comment is not a value.
  assert_eq(j("# a comment\nkey = 1 # another"), "{\"key\":1}")
}

///|
test "a dotted key builds the tables it names" {
  assert_eq(j("a.b.c = 1"), "{\"a\":{\"b\":{\"c\":1}}}")
  assert_eq(
    j(
      "name = \"Orange\"\nphysical.color = \"orange\"\nphysical.shape = \"round\"",
    ),
    "{\"name\":\"Orange\",\"physical\":{\"color\":\"orange\",\"shape\":\"round\"}}",
  )
  // Whitespace around the dots is allowed.
  assert_eq(j("a . b . c = 1"), "{\"a\":{\"b\":{\"c\":1}}}")
}

///|
test "the four string forms" {
  assert_eq(j("s = \"I'm a string\""), "{\"s\":\"I'm a string\"}")
  // A literal string has no escapes at all, which is why a Windows path goes in one.
  assert_eq(j("p = 'C:\\Users\\nodejs'"), "{\"p\":\"C:\\\\Users\\\\nodejs\"}")
  // Multi-line, with the newline after the opening delimiter dropped.
  assert_eq(j("s = \"\"\"\none\ntwo\"\"\""), "{\"s\":\"one\\ntwo\"}")
  assert_eq(j("s = '''\none\ntwo'''"), "{\"s\":\"one\\ntwo\"}")
  // A backslash at the end of a line eats the break and the indentation after it.
  assert_eq(j("s = \"\"\"\\\n  one \\\n  two\"\"\""), "{\"s\":\"one two\"}")
}

///|
test "the escapes a basic string carries" {
  assert_eq(j("s = \"a\\tb\""), "{\"s\":\"a\\tb\"}")
  assert_eq(j("s = \"\\u0041\\U0001F600\""), "{\"s\":\"A\u{1F600}\"}")
  assert_eq(j("s = \"a\\\"b\""), "{\"s\":\"a\\\"b\"}")
  // An escape TOML does not define is a fault, not a literal backslash.
  assert_eq(refused("s = \"a\\qb\""), true)
}

///|
test "integers in the four bases TOML writes" {
  assert_eq(
    j("a = 42\nb = +99\nc = -17\nd = 0"),
    "{\"a\":42,\"b\":99,\"c\":-17,\"d\":0}",
  )
  assert_eq(j("a = 0xDEADBEEF"), "{\"a\":3735928559}")
  assert_eq(j("a = 0o755"), "{\"a\":493}")
  assert_eq(j("a = 0b11010110"), "{\"a\":214}")
  // Underscores group digits and mean nothing else.
  assert_eq(j("a = 1_000_000"), "{\"a\":1000000}")
  assert_eq(j("a = 0xdead_beef"), "{\"a\":3735928559}")
  // One that is not between two digits is a fault.
  assert_eq(refused("a = _1"), true)
  assert_eq(refused("a = 1_"), true)
  assert_eq(refused("a = 1__0"), true)
  // A leading zero is only legal on its own.
  assert_eq(refused("a = 0123"), true)
}

///|
test "floats, with the exponent and the two named values" {
  // The text a number was written as is kept when JSON spells it the same way.
  // TOML has an integer type and a float type and JSON has neither, so `1.0`
  // staying `1.0` is what preserves the difference from `1`.
  assert_eq(
    j("a = 1.0\nb = 3.1415\nc = -0.01"),
    "{\"a\":1.0,\"b\":3.1415,\"c\":-0.01}",
  )
  assert_eq(
    j("a = 5e+22\nb = 1e06\nc = -2E-2"),
    "{\"a\":5e+22,\"b\":1e06,\"c\":-2E-2}",
  )
  assert_eq(j("a = 6.626e-34"), "{\"a\":6.626e-34}")
  // TOML requires a digit either side of the dot.
  assert_eq(refused("a = .7"), true)
  assert_eq(refused("a = 7."), true)
  assert_eq(refused("a = 3.e+20"), true)
}

///|
test "the four date-time types TOML defines, read as the dates they are" {
  // The specification's own examples, normalised to RFC 3339.
  assert_eq(j("d = 1979-05-27T07:32:00Z"), "{\"d\":\"1979-05-27T07:32:00Z\"}")
  assert_eq(
    j("d = 1979-05-27T00:32:00-07:00"),
    "{\"d\":\"1979-05-27T00:32:00-07:00\"}",
  )
  assert_eq(j("d = 1979-05-27T07:32:00"), "{\"d\":\"1979-05-27T07:32:00\"}")
  assert_eq(j("d = 1979-05-27"), "{\"d\":\"1979-05-27\"}")
  assert_eq(j("d = 07:32:00"), "{\"d\":\"07:32:00\"}")
  // A space may join the date to the time, which is what a person writes.
  assert_eq(j("d = 1979-05-27 07:32:00Z"), "{\"d\":\"1979-05-27T07:32:00Z\"}")
  // A date the calendar does not have is refused rather than read as a string.
  assert_eq(refused("d = 1979-02-30"), true)
  assert_eq(refused("d = 1979-05-27T25:00:00Z"), true)
}

///|
test "arrays, which may span lines and may end with a comma" {
  assert_eq(j("a = [1, 2, 3]"), "{\"a\":[1,2,3]}")
  assert_eq(j("a = [\"x\", 'y']"), "{\"a\":[\"x\",\"y\"]}")
  assert_eq(j("a = [[1, 2], [3]]"), "{\"a\":[[1,2],[3]]}")
  assert_eq(j("a = [\n  1,\n  2,\n]"), "{\"a\":[1,2]}")
  assert_eq(j("a = []"), "{\"a\":[]}")
  // 1.0.0 allows a mixed-type array, which 0.5 did not.
  assert_eq(j("a = [1, \"two\", true]"), "{\"a\":[1,\"two\",true]}")
  // A comment inside one.
  assert_eq(j("a = [\n  1, # first\n  2,\n]"), "{\"a\":[1,2]}")
}

///|
test "tables under their own headers" {
  assert_eq(j("[t]\na = 1\nb = 2"), "{\"t\":{\"a\":1,\"b\":2}}")
  assert_eq(j("[a.b.c]\nx = 1"), "{\"a\":{\"b\":{\"c\":{\"x\":1}}}}")
  // A super-table may be defined after the one under it.
  assert_eq(j("[a.b]\nx = 1\n[a]\ny = 2"), "{\"a\":{\"b\":{\"x\":1},\"y\":2}}")
  // Keys before any header belong to the root.
  assert_eq(j("root = 1\n[t]\nx = 2"), "{\"root\":1,\"t\":{\"x\":2}}")
}

///|
test "inline tables, which close the moment their brace does" {
  assert_eq(j("a = { x = 1, y = 2 }"), "{\"a\":{\"x\":1,\"y\":2}}")
  assert_eq(j("a = {}"), "{\"a\":{}}")
  assert_eq(j("a = { b = { c = 1 } }"), "{\"a\":{\"b\":{\"c\":1}}}")
  assert_eq(j("a = { b.c = 1 }"), "{\"a\":{\"b\":{\"c\":1}}}")
  // 1.0.0 keeps an inline table on one line and forbids a trailing comma.
  assert_eq(refused("a = { x = 1, }"), true)
  // And nothing may be added to it afterwards.
  assert_eq(refused("a = { x = 1 }\n[a.b]\ny = 2"), true)
  assert_eq(refused("a = { x = 1 }\na.y = 2"), true)
}

///|
test "arrays of tables append rather than replace" {
  assert_eq(
    j("[[p]]\nname = \"a\"\n[[p]]\nname = \"b\""),
    "{\"p\":[{\"name\":\"a\"},{\"name\":\"b\"}]}",
  )
  // A header under one lands in the element just appended.
  assert_eq(
    j("[[p]]\nname = \"a\"\n[p.q]\nx = 1\n[[p]]\nname = \"b\""),
    "{\"p\":[{\"name\":\"a\",\"q\":{\"x\":1}},{\"name\":\"b\"}]}",
  )
  // Nested arrays of tables.
  assert_eq(
    j("[[a]]\n[[a.b]]\nx = 1\n[[a.b]]\nx = 2"),
    "{\"a\":[{\"b\":[{\"x\":1},{\"x\":2}]}]}",
  )
}

///|
test "a key defined twice is refused, which is what makes a file safe to append to" {
  assert_eq(refused("a = 1\na = 2"), true)
  assert_eq(refused("[t]\nx = 1\nx = 2"), true)
  // A table header may not repeat.
  assert_eq(refused("[t]\n[t]"), true)
  // A dotted key may not later be opened by a header.
  assert_eq(refused("a.b = 1\n[a]"), true)
  // But a header may be extended by dotted keys under it.
  assert_eq(j("[a]\nb.c = 1\nb.d = 2"), "{\"a\":{\"b\":{\"c\":1,\"d\":2}}}")
  // And a table implied by a deeper header may still be opened by its own.
  assert_eq(j("[a.b]\nx = 1\n[a]\ny = 2"), "{\"a\":{\"b\":{\"x\":1},\"y\":2}}")
}

///|
test "text that is not a document is refused with a line" {
  for
    bad in [
      "a =", "= 1", "a = 1 b = 2", "[a", "a = [1, 2", "a = \"unterminated", "a = 'unterminated",
      "[]", "a = 1\n[[b]\n", "a = @",
    ] {
    assert_eq(refused(bad), true)
  }
  // And the refusal says which line.
  let said = try {
    let _ = loads("a = 1\nb = @\n"[:])
    ""
  } catch {
    e => e.to_string()
  }
  assert_eq(said.contains("2:"), true)
}

///|
test "nesting past the limit is refused rather than run into the ground" {
  let deep = StringBuilder()
  deep.write_string("a = ")
  for i = 0; i < 40; i = i + 1 {
    deep.write_char('[')
  }
  for i = 0; i < 40; i = i + 1 {
    deep.write_char(']')
  }
  let src = deep.to_string()
  assert_eq(loads(src[:]) is Object(_), true)
  let mut out = false
  try {
    let _ = loads(src[:], flavor=Flavor::new(depth=8))
  } catch {
    TooDeep(_) => out = true
    _ => ()
  }
  assert_eq(out, true)
}

///|
test "UTF-8, with or without the mark an editor writes" {
  assert_eq(
    load(b"a = \"\xe4\xb8\xad\"\n"[:]).stringify(),
    "{\"a\":\"\u{4e2d}\"}",
  )
  assert_eq(load(b"\xef\xbb\xbfa = 1\n"[:]).stringify(), "{\"a\":1}")
  // TOML says a file has no byte-order mark, so a caller may hold it to that.
  assert_eq(
    try {
      let _ = load(b"\xef\xbb\xbfa = 1\n"[:], bom=false)
      false
    } catch {
      _ => true
    },
    true,
  )
}

///|
test "MoonBit's own manifests read, which is the case this module exists for" {
  let manifest =
    #|name = "moonbitstack/moontoml"
    #|version = "0.1.0"
    #|readme = "README.md"
    #|license = "Apache-2.0"
    #|keywords = [ "toml", "config", "parser", "moonbit" ]
    #|preferred_target = "wasm-gc"
    #|
    #|[import]
    #|"moonbitstack/moondate" = "0.1.0"
    #|
  let doc = loads(manifest[:])
  guard doc is Object(m) else { fail("a manifest is a table") }
  assert_eq(m.get("name"), Some(Json::string("moonbitstack/moontoml")))
  assert_eq(m.get("keywords") is Some(Array(_)), true)
  guard m.get("import") is Some(Object(deps)) else {
    fail("the imports are a table")
  }
  assert_eq(deps.get("moonbitstack/moondate"), Some(Json::string("0.1.0")))
}

///|
fn refused(src : String) -> Bool {
  try {
    let _ = loads(src[:])
    false
  } catch {
    _ => true
  }
}
