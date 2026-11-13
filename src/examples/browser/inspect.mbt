// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Read `src` as TOML and report what the library made of it.
///
/// On success the object is `{ "ok": true, "tree": <json>, "copy": "<toml>" }`,
/// where `tree` is the document as `loads` reads it and `copy` is the same
/// document written back by `dumps`, ordered by key when `sort` is true. On a
/// refusal it is `{ "ok": false, "line": n, "column": m, "message": "…" }`, with
/// the position taken from the fault so the page can mark the line.
pub fn inspect(src : String, sort : Bool) -> String {
  try {
    let tree = @moontoml.loads(src[:])
    spelled(
      Json::object({
        "ok": Json::boolean(true),
        "tree": tree,
        "copy": Json::string(@moontoml.dumps(tree, sort~)),
      }),
    )
  } catch {
    fault => spelled(refused_answer(fault.to_string(), fault.at()))
  }
}
