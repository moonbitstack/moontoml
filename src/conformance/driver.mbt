// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Read a document at the named edition and answer `toml-test`'s JSON for the
/// tree it denotes.
///
/// `edition` names the edition the document is read under — `4`, `5`, `10` or
/// `11` — which is what makes the same driver check the 1.0.0 and the 1.1.0
/// suites. The answer is `{ "ok": true, "text": <json> }` or `{ "ok": false,
/// "text": <message> }`; the command line driver prints the first to standard
/// output and the second to standard error, which is how a refusal is reported.
pub fn decode_document(src : Bytes, edition : Int32) -> String {
  let flavor = @moontoml.Flavor::new(edition=of_number(edition))
  let got = Ok(@moontoml.decode_bytes(src[:], flavor~)) catch {
    fault => Err(fault.to_string())
  }
  match got {
    Ok(value) => envelope(true, @moonjson.dumps(typed(value)))
    Err(why) => envelope(false, why)
  }
}

///|
/// The edition a number names.
fn of_number(n : Int32) -> @moontoml.Edition {
  match n {
    4 => @moontoml.V04
    5 => @moontoml.V05
    11 => @moontoml.V110
    _ => @moontoml.V100
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
  let tree = Ok(of_typed(@moonjson.loads(text[:], @moonjson.strict))) catch {
    _ => Err(())
  }
  match tree {
    Ok(value) => envelope(true, @moontoml.encode(value))
    Err(_) => envelope(false, "the input is not a toml-test tree")
  }
}

///|
fn envelope(ok : Bool, text : String) -> String {
  @moonjson.dumps(
    Json::object({ "ok": Json::boolean(ok), "text": Json::string(text) }),
  )
}
