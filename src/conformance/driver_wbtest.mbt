// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The envelope as the tool reads it: strict JSON, one member for whether the
/// document was read and one for the tree or the message.
fn answered(text : String) -> Map[String, Json] raise {
  match @moonjson.loads(text[:], @moonjson.strict) {
    Object(fields) => fields
    _ => fail("the answer is an object")
  }
}

///|
fn text_of(fields : Map[String, Json]) -> String raise {
  match fields.get("text") {
    Some(String(text)) => text
    _ => fail("the answer carries text")
  }
}

///|
test "the driver answers a valid document with the tree it denotes" {
  let answer = answered(decode_document(b"a = 1\nb = \"two\"\n", 10))
  assert_eq(answer.get("ok"), Some(Json::boolean(true)))
  assert_eq(
    text_of(answer),
    "{\"a\":{\"type\":\"integer\",\"value\":\"1\"},\"b\":{\"type\":\"string\",\"value\":\"two\"}}",
  )
}

///|
test "the driver answers a refusal with the place and the fault" {
  let answer = answered(decode_document(b"a = 1\na = 2\n", 10))
  assert_eq(answer.get("ok"), Some(Json::boolean(false)))
  assert_eq(text_of(answer), "2:1: a is already defined")
}

///|
test "the driver reads the document at the edition it is given" {
  let dotted = b"a.b = 1\n"
  assert_eq(
    answered(decode_document(dotted, 4)).get("ok"),
    Some(Json::boolean(false)),
  )
  for edition in [5, 10, 11] {
    assert_eq(
      answered(decode_document(dotted, edition)).get("ok"),
      Some(Json::boolean(true)),
    )
  }
}

///|
test "the driver writes a tree it was handed as TOML" {
  let tree =
    #|{"a": {"type": "integer", "value": "1"}, "b": {"type": "string", "value": "two"}}
  let answer = answered(encode_document(@utf8.encode(tree[:])))
  assert_eq(answer.get("ok"), Some(Json::boolean(true)))
  assert_eq(text_of(answer), "a = 1\nb = \"two\"\n")
}

///|
test "the driver refuses JSON that is not a toml-test tree, and bytes that are not UTF-8" {
  let answer = answered(encode_document(b"{\"a\": 1}"))
  assert_eq(answer.get("ok"), Some(Json::boolean(false)))
  assert_eq(text_of(answer), "the input is not a toml-test tree")

  let bytes = answered(encode_document(b"\xff\xfe"))
  assert_eq(bytes.get("ok"), Some(Json::boolean(false)))
  assert_eq(text_of(bytes), "the input is not UTF-8")
}

///|
test "a quote and a line break in the text survive the envelope" {
  let tree =
    #|{"a": {"type": "string", "value": "one \"two\"\nthree\\four"}, "b": {"type": "bool", "value": "true"}}
  let answer = answered(encode_document(@utf8.encode(tree[:])))
  assert_eq(answer.get("ok"), Some(Json::boolean(true)))
  // The text came out of the envelope as the writer wrote it, escapes and all.
  assert_eq(
    text_of(answer),
    "a = \"one \\\"two\\\"\\nthree\\\\four\"\nb = true\n",
  )
}
