// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The document as the kinds it holds.
fn v(src : String) -> Value raise {
  decode(src[:])
}

///|
/// The one value a document holds under `name`.
fn at(src : String, name : String) -> Value raise {
  guard v(src) is Table(fields) else { fail("a document is a table") }
  guard fields.get(name) is Some(held) else {
    fail(name + " is not in the document")
  }
  held
}

///|
test "a document read kind for kind keeps what the format says each value is" {
  assert_eq(at("n = 42", "n"), Integer(42L))
  assert_eq(at("n = 0x2a", "n"), Integer(42L))
  assert_eq(at("b = true", "b"), Boolean(true))
  assert_eq(at("s = \"x\"", "s"), String("x"))
  assert_eq(at("a = [1, 2]", "a").to_json().stringify(), "[1,2]")
  guard at("d = 1979-05-27", "d") is Datetime(m) else {
    fail("a date is a date")
  }
  assert_eq(m.to_string(), "1979-05-27")
}

///|
test "an integer is 64 bits, which a double cannot hold above 2^53" {
  assert_eq(at("n = 9223372036854775807", "n"), Integer(9223372036854775807L))
  assert_eq(
    at("n = -9223372036854775808", "n"),
    Integer(-9223372036854775807L - 1L),
  )
  // The text of an integer past what a double holds is written back as itself,
  // because the value was never a double.
  assert_eq(encode(v("n = 9007199254740993")), "n = 9007199254740993\n")
  // Out of range is a fault rather than a rounded value.
  assert_eq(refused("n = 9223372036854775808"), true)
}

///|
test "a value that only looks like a date is still a string" {
  // This is the difference the kinds make: a date is a date, and text that a
  // reader could mistake for one is text.
  assert_eq(at("s = \"1979-05-27\"", "s"), String("1979-05-27"))
  assert_eq(encode(v("s = \"1979-05-27\"")), "s = \"1979-05-27\"\n")
  assert_eq(encode(v("d = 1979-05-27")), "d = 1979-05-27\n")
  // Written through a `Json` tree there is no kind to go on, so the spelling
  // decides, and a timestamp stays a timestamp.
  assert_eq(
    dumps(loads("d = 1979-05-27T07:32:00Z"[:])),
    "d = 1979-05-27T07:32:00Z\n",
  )
}

///|
test "the four date-time kinds survive a round trip" {
  for
    src in [
      "d = 1979-05-27T07:32:00Z", "d = 1979-05-27T00:32:00-07:00", "d = 1979-05-27T07:32:00",
      "d = 1979-05-27", "d = 07:32:00", "d = 1979-05-27T07:32:00.999999Z",
    ] {
    let once = at(src, "d")
    assert_eq(once is Datetime(_), true)
    assert_eq(at(encode(once), "value"), once)
  }
}

///|
test "a float keeps the text it was written as" {
  assert_eq(encode(v("f = 1e06")), "f = 1e06\n")
  assert_eq(encode(v("f = 1.0")), "f = 1.0\n")
  // A whole float built in code still reads back as a float.
  assert_eq(encode(Float(Real::new(12000.0))), "value = 12000.0\n")
  assert_eq(encode(Float(Real::new(@double.not_a_number))), "value = nan\n")
  assert_eq(encode(Float(Real::new(-@double.infinity))), "value = -inf\n")
}

///|
test "two floats are the same value when the number is the same" {
  assert_eq(
    Float(Real::new(1.0)) == Float({ value: 1.0, repr: Some("1.0"), }),
    true,
  )
  assert_eq(Float(Real::new(1.0)) == Float(Real::new(2.0)), false)
  // A NaN is the same value as a NaN, which is what comparing documents needs.
  assert_eq(
    Float(Real::new(@double.not_a_number)) ==
    Float(Real::new(@double.not_a_number)),
    true,
  )
}

///|
test "values of different kinds are never equal" {
  assert_eq(Integer(1L) == Float(Real::new(1.0)), false)
  assert_eq(String("1") == Integer(1L), false)
  assert_eq(Array([Integer(1L)]) == Array([Integer(1L), Integer(2L)]), false)
}

///|
test "two offsets that name the same instant are the same date-time" {
  assert_eq(
    at("d = 1979-05-27T07:32:00Z", "d") ==
    at("d = 1979-05-27T00:32:00-07:00", "d"),
    true,
  )
  // Kind is part of it: a local date-time is not an offset one.
  assert_eq(
    at("d = 1979-05-27T07:32:00", "d") == at("d = 1979-05-27", "d"),
    false,
  )
}

///|
test "the tree a Json denotes is what the writer starts from" {
  assert_eq(
    encode(value_of_json(loads("n = 1\ns = \"x\""[:]))),
    "n = 1\ns = \"x\"\n",
  )
  // A whole number written through a `Json` tree stays an integer, which is how
  // a port is `12000` rather than `12000.0`.
  assert_eq(encode(value_of_json(loads("port = 12000"[:]))), "port = 12000\n")
  // A `Json` null has no TOML spelling, and an empty string is the one every
  // encoder in reach picks.
  assert_eq(encode(value_of_json(@json.null)), "value = \"\"\n")
}

///|
test "the writer quotes a key only when it has to" {
  let doc : Map[String, Value] = Map([])
  doc["a.b"] = Integer(1L)
  doc["plain"] = Integer(2L)
  assert_eq(encode(Table(doc)), "\"a.b\" = 1\nplain = 2\n")
}

///|
test "bytes in, kinds out" {
  assert_eq(decode_bytes(b"n = 1\n"[:]), Table({ "n": Integer(1L) }))
  assert_eq(
    decode_bytes(b"\xef\xbb\xbfn = 1\n"[:]),
    Table({ "n": Integer(1L) }),
  )
  // A file that is not UTF-8 is refused rather than read as if it were.
  assert_eq(
    try {
      let _ = decode_bytes(b"n = \"\xff\"\n"[:])
      false
    } catch {
      _ => true
    },
    true,
  )
  assert_eq(encode_bytes(v("n = 1")), b"n = 1\n")
}
