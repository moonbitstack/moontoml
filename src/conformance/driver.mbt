// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Read a document and answer `toml-test`'s JSON for the tree it denotes.
///
/// The answer is `{ "ok": true, "text": <json> }` or `{ "ok": false, "text":
/// <message> }`; the command line driver prints the first to standard output and
/// the second to standard error, which is how a refusal is reported.
pub fn decode_document(src : Bytes) -> String {
  let got = Ok(@moontoml.decode_bytes(src[:])) catch {
    fault => Err(fault.to_string())
  }
  match got {
    Ok(value) => envelope(true, typed(value).stringify())
    Err(why) => envelope(false, why)
  }
}

///|
/// Write the document a tree denotes.
///
/// `src` is `toml-test`'s JSON for the tree; the answer is `{ "ok": true, "text":
/// <toml> }`.
pub fn encode_document(src : Bytes) -> String {
  let text = @utf8.decode(src, ignore_bom=false) catch {
    _ => return envelope(false, "the input is not UTF-8")
  }
  let tree = Ok(of_typed(@json.parse(text[:]))) catch { _ => Err(()) }
  match tree {
    Ok(value) => envelope(true, @moontoml.encode(value))
    Err(_) => envelope(false, "the input is not a toml-test tree")
  }
}

///|
fn envelope(ok : Bool, text : String) -> String {
  "{\"ok\":" +
  (if ok { "true" } else { "false" }) +
  ",\"text\":" +
  Json::string(text).stringify() +
  "}"
}
