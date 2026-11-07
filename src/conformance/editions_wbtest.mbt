// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The 0.4 and 0.5 editions have no `toml-test` file list of their own, so they
/// are checked against the edition they grow from: every feature 0.5 introduced
/// is refused of a 0.4 and read in full at a 0.5, and what 0.4 already allowed is
/// read the same in both.
///
/// A document that one edition refuses and the other reads is the difference
/// between them, named here one at a time.

///|
fn load_ed(src : String, at : @moontoml.Edition) -> String? {
  try {
    let tree = @moontoml.loads(src[:], flavor=@moontoml.Flavor::new(edition=at))
    Some(tree.stringify())
  } catch {
    _ => None
  }
}

///|
test "0.4 refuses what 0.5 introduced" {
  let v04 = @moontoml.V04
  // Dotted keys.
  assert_eq(load_ed("a.b = 1\n", v04), None)
  // Prefixed integers.
  assert_eq(load_ed("x = 0xff\n", v04), None)
  assert_eq(load_ed("x = 0o755\n", v04), None)
  assert_eq(load_ed("x = 0b11010110\n", v04), None)
  // The special float values.
  assert_eq(load_ed("x = inf\n", v04), None)
  assert_eq(load_ed("x = nan\n", v04), None)
  // The three local date-time kinds.
  assert_eq(load_ed("d = 1979-05-27\n", v04), None)
  assert_eq(load_ed("t = 07:32:00\n", v04), None)
  assert_eq(load_ed("d = 1979-05-27T07:32:00\n", v04), None)
}

///|
test "0.4 reads what it already had" {
  let v04 = @moontoml.V04
  // The offset date-time, which 0.4 knew, is what a bare date-time is there.
  assert_eq(
    load_ed("d = 1979-05-27T07:32:00Z\n", v04),
    Some("{\"d\":\"1979-05-27T07:32:00Z\"}"),
  )
  // Digit-grouping underscores, a 0.4 feature.
  assert_eq(load_ed("x = 1_000\n", v04), Some("{\"x\":1000}"))
  // A dot inside a quoted key is part of the key, not a separator.
  assert_eq(load_ed("\"a.b\" = 1\n", v04), Some("{\"a.b\":1}"))
}

///|
test "0.5 reads what it introduced" {
  let v05 = @moontoml.V05
  assert_eq(load_ed("a.b = 1\n", v05), Some("{\"a\":{\"b\":1}}"))
  assert_eq(load_ed("x = 0xff\n", v05), Some("{\"x\":255}"))
  assert_eq(load_ed("x = 0o755\n", v05), Some("{\"x\":493}"))
  assert_eq(load_ed("x = 0b11010110\n", v05), Some("{\"x\":214}"))
  // The three local date-time kinds, each as its own kind.
  assert_eq(load_ed("d = 1979-05-27\n", v05), Some("{\"d\":\"1979-05-27\"}"))
  assert_eq(load_ed("t = 07:32:00\n", v05), Some("{\"t\":\"07:32:00\"}"))
  assert_eq(
    load_ed("d = 1979-05-27T07:32:00\n", v05),
    Some("{\"d\":\"1979-05-27T07:32:00\"}"),
  )
}

///|
test "0.5 reads inf and nan as a float" {
  let doc = @moontoml.decode(
    "x = inf\n",
    flavor=@moontoml.Flavor::new(edition=@moontoml.V05),
  )
  guard doc is Table(fields) else { abort("a table") }
  guard fields.get("x") is Some(Float(real)) else { abort("inf is a float") }
  assert_eq(real.value.is_inf(), true)
  // Through a Json tree the same value is the number it is.
  assert_eq(load_ed("x = inf\n", @moontoml.V05), Some("{\"x\":\"Infinity\"}"))
}

///|
test "an array is one kind of value at 0.5, and mixed from 1.0" {
  assert_eq(load_ed("a = [1, \"x\"]\n", @moontoml.V04), None)
  assert_eq(load_ed("a = [1, \"x\"]\n", @moontoml.V05), None)
  assert_eq(load_ed("a = [1, 2, 3]\n", @moontoml.V05), Some("{\"a\":[1,2,3]}"))
  assert_eq(
    load_ed("a = [1, \"x\"]\n", @moontoml.V100),
    Some("{\"a\":[1,\"x\"]}"),
  )
}
