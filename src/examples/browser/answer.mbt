// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The library, compiled to JavaScript, answering the documentation pages.
//
// A page hands in text and gets JSON text back; every answer is written by
// `moonjson`, so what a page reads is what any other reader of JSON would read.
// Nothing here parses or writes TOML itself — the answers are calls into
// `moontoml`, which is the point of the pages: what they show is what the
// library computes.

///|
/// An answer, as the text a page reads.
fn spelled(answer : Json) -> String {
  @moonjson.dumps(answer)
}

///|
/// The page's answer for a document that was refused: the place, and what the
/// fault says.
fn refused_answer(message : String, at : @moontoml.At) -> Json {
  Json::object({
    "ok": Json::boolean(false),
    "line": Json::number(at.line.to_double(), repr=at.line.to_string()),
    "column": Json::number(at.column.to_double(), repr=at.column.to_string()),
    "message": Json::string(message),
  })
}
