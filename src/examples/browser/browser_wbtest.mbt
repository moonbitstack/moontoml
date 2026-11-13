// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The answer a page reads, as a tree.
fn fields(text : String) -> Map[String, Json] raise {
  match @moonjson.loads(text[:], @moonjson.strict) {
    Json::Object(fields) => fields
    _ => fail("an answer is an object")
  }
}

///|
fn text_at(answer : Map[String, Json], key : String) -> String raise {
  match answer.get(key) {
    Some(Json::String(text)) => text
    _ => fail("\{key} is text")
  }
}

///|
test "inspect gives the tree and the copy, or the place of the refusal" {
  let answer = fields(inspect("beds = 4\nsoil = \"loam\"\n", false))
  assert_eq(answer.get("ok"), Some(Json::boolean(true)))
  match answer.get("tree") {
    Some(Json::Object(tree)) =>
      assert_eq(tree.get("beds"), Some(Json::number(4.0, repr="4")))
    _ => fail("the tree is a table")
  }
  assert_eq(text_at(answer, "copy"), "beds = 4\nsoil = \"loam\"\n")

  let refused = fields(inspect("a = 1\na = 2\n", false))
  assert_eq(refused.get("ok"), Some(Json::boolean(false)))
  assert_eq(refused.get("line"), Some(Json::number(2.0, repr="2")))
  assert_eq(refused.get("column"), Some(Json::number(1.0, repr="1")))
  assert_eq(text_at(refused, "message"), "2:1: a is already defined")
}

///|
test "editions reads one line at four grammars" {
  let dotted = fields(editions("a.b = 1\n"))
  let rows = match dotted.get("rows") {
    Some(Json::Array(rows)) => rows
    _ => fail("the answer holds the rows")
  }
  assert_eq(rows.length(), 4)
  let ok : Array[Json?] = []
  for row in rows {
    let held = match row {
      Json::Object(held) => held
      _ => fail("a row is an object")
    }
    ok.push(held.get("ok"))
  }
  assert_eq(ok, [
    Some(Json::boolean(false)),
    Some(Json::boolean(true)),
    Some(Json::boolean(true)),
    Some(Json::boolean(true)),
  ])

  let comma = fields(editions("p = { x = 1, }\n"))
  let rows = match comma.get("rows") {
    Some(Json::Array(rows)) => rows
    _ => fail("the answer holds the rows")
  }
  assert_eq(rows.length(), 4)
  let last = rows[3]
  let held = match last {
    Json::Object(held) => held
    _ => fail("a row is an object")
  }
  assert_eq(held.get("edition"), Some(Json::string("1.1")))
  assert_eq(held.get("ok"), Some(Json::boolean(true)))
}

///|
test "kept lists the keys and changes only the line that moved" {
  let src =
    #|# a garden
    #|name = "garden"  # the one by the gate
    #|beds = 4
    #|
    #|[soil]
    #|ph = 6.5
    #|
  let plain = fields(kept(src, "", ""))
  assert_eq(plain.get("moved"), Some(@json.null))
  assert_eq(text_at(plain, "before"), text_at(plain, "after"))
  let paths = match plain.get("paths") {
    Some(Json::Array(paths)) => paths
    _ => fail("the answer holds the keys")
  }
  assert_eq(paths.length(), 3)

  let changed = fields(kept(src, "[\"beds\"]", "6"))
  assert_eq(changed.get("moved"), Some(Json::boolean(true)))
  let expected =
    #|# a garden
    #|name = "garden"  # the one by the gate
    #|beds = 6
    #|
    #|[soil]
    #|ph = 6.5
    #|
  assert_eq(text_at(changed, "after"), expected)

  let missing = fields(kept(src, "[\"absent\"]", "6"))
  assert_eq(missing.get("moved"), Some(@json.null))
  assert_eq(text_at(missing, "before"), text_at(missing, "after"))
}

///|
test "a TOML value written by a person is read by the library" {
  let src = "beds = 4\n"
  let changed = fields(kept(src, "[\"beds\"]", "0x2A"))
  assert_eq(text_at(changed, "after"), "beds = 42\n")

  let quoted = fields(kept("kind = \"loam\"\n", "[\"kind\"]", "\"silt\""))
  assert_eq(text_at(quoted, "after"), "kind = \"silt\"\n")
}

///|
test "fault names the variant the library raised" {
  let doubled = fields(fault("a = 1\na = 2\n", 10))
  assert_eq(doubled.get("ok"), Some(Json::boolean(false)))
  assert_eq(text_at(doubled, "kind"), "Redefined")
  assert_eq(text_at(doubled, "message"), "2:1: a is already defined")

  let mixed = fields(fault("a = [1, \"two\"]\n", 5))
  assert_eq(text_at(mixed, "kind"), "MixedArray")

  let accepted = fields(fault("a = [1, \"two\"]\n", 10))
  assert_eq(accepted.get("ok"), Some(Json::boolean(true)))
}

///|
test "fault_bytes names the fault of bytes that are not UTF-8" {
  let answer = fields(fault_bytes(b"\xff\xfe", 10))
  assert_eq(answer.get("ok"), Some(Json::boolean(false)))
  assert_eq(text_at(answer, "kind"), "BadUtf8")
  assert_eq(answer.get("line"), Some(Json::number(1.0, repr="1")))
}
