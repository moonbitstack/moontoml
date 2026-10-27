// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The TOML a document is written as, read from TOML itself.
fn t(src : String) -> String raise Refused {
  dumps(loads(src[:]))
}

///|
test "scalars stay on the line, tables go under a header" {
  assert_eq(t("a = 1\nb = \"x\""), "a = 1\nb = \"x\"\n")
  // A header that opens the document gets no blank line before it.
  assert_eq(t("[s]\nx = 1"), "[s]\nx = 1\n")
  // Scalars are written before any header, because a key after one would belong
  // to that header.
  assert_eq(t("[s]\nx = 1\nroot = 2"), "[s]\nx = 1\nroot = 2\n")
  assert_eq(t("root = 2\n[s]\nx = 1"), "root = 2\n\n[s]\nx = 1\n")
}

///|
test "a key is quoted only when it cannot be bare" {
  assert_eq(dumps({ "a-b_1": Json::number(1) }), "a-b_1 = 1\n")
  assert_eq(dumps({ "a.b": Json::number(1) }), "\"a.b\" = 1\n")
  assert_eq(dumps({ "a b": Json::number(1) }), "\"a b\" = 1\n")
  assert_eq(dumps({ "": Json::number(1) }), "\"\" = 1\n")
}

///|
test "a number is written as the value it is" {
  assert_eq(dumps({ "a": Json::number(12000) }), "a = 12000\n")
  assert_eq(dumps({ "a": Json::number(1.5) }), "a = 1.5\n")
  assert_eq(dumps({ "a": Json::number(-2) }), "a = -2\n")
  // A number read from text keeps that text, so a base or a big integer survives
  // the round trip as written.
  assert_eq(t("a = 9007199254740993"), "a = 9007199254740993\n")
  assert_eq(t("a = 1.0"), "a = 1.0\n")
}

///|
test "a date-time is written as one, not quoted into a string" {
  // This module reads TOML's four date-time types; writing them quoted would turn
  // a timestamp back into a string, which is the one thing the types exist to
  // prevent.
  assert_eq(t("d = 1979-05-27T07:32:00Z"), "d = 1979-05-27T07:32:00Z\n")
  assert_eq(t("d = 1979-05-27"), "d = 1979-05-27\n")
  assert_eq(t("d = 07:32:00"), "d = 07:32:00\n")
  // A string that merely looks like one is another matter: it has to read back as
  // a string, so it stays quoted.
  assert_eq(dumps({ "d": Json::string("not-a-date") }), "d = \"not-a-date\"\n")
}

///|
test "a multi-line string goes in the form a person would write" {
  assert_eq(
    dumps({ "s": Json::string("one\ntwo\n") }),
    "s = '''\none\ntwo\n'''\n",
  )
  // Unless it carries something a literal cannot hold, and then it is escaped.
  assert_eq(dumps({ "s": Json::string("one\n'two'") }), "s = \"one\\n'two'\"\n")
  assert_eq(dumps({ "s": Json::string("a\\b") }), "s = \"a\\\\b\"\n")
  assert_eq(dumps({ "s": Json::string("a\u{0}b") }), "s = \"a\\u0000b\"\n")
}

///|
test "an array of tables is written as one when every element is a table" {
  assert_eq(
    t("[[p]]\nname = \"a\"\n[[p]]\nname = \"b\""),
    "[[p]]\nname = \"a\"\n\n[[p]]\nname = \"b\"\n",
  )
  // A mixed array has no header form, so it stays inline.
  assert_eq(
    dumps({
      "a": Json::array([Json::number(1), Json::object({ "x": Json::number(2) })]),
    }),
    "a = [1, { x = 2 }]\n",
  )
  // And an empty array is inline too, since `[[a]]` would write no element.
  assert_eq(dumps({ "a": Json::array([]) }), "a = []\n")
}

///|
test "every document this reads, it writes back to the same values" {
  let cases = [
    "a = 1\nb = \"x\"\nc = [1, 2]\n", "[t]\nx = 1\ny = 2\n", "[a.b.c]\nx = 1\n",
    "[[p]]\nn = 1\n[[p]]\nn = 2\n", "a = { x = 1, y = 2 }\n", "d = 1979-05-27T07:32:00Z\ne = 1979-05-27\n",
    "s = \"\"\"\none\ntwo\"\"\"\n", "n = 0xff\nm = 1_000\np = 1.5e3\n", "root = 1\n[t]\nx = 2\n[[q]]\ny = 3\n",
  ]
  for src in cases {
    let once = loads(src[:])
    let twice = loads(dumps(once)[:])
    assert_eq(twice.stringify(), once.stringify())
  }
}

///|
test "sorting is a knob, off by default so a document keeps its order" {
  assert_eq(t("b = 1\na = 2"), "b = 1\na = 2\n")
  assert_eq(dumps(loads("b = 1\na = 2"[:]), sort=true), "a = 2\nb = 1\n")
}

///|
test "bytes in and bytes out" {
  assert_eq(dump(loads("a = 1"[:])), b"a = 1\n")
  assert_eq(load(b"a = 1\n"[:]).stringify(), "{\"a\":1}")
}
