// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Read `src` as TOML and report what the library made of it, as a JSON string
/// the documentation page can hand to JavaScript.
///
/// On success the object is `{ "ok": true, "tree": <json>, "copy": "<toml>" }`,
/// where `tree` is the parsed document and `copy` is the same document written
/// back by `dumps`, ordered by key when `sort` is true. On a refusal it is
/// `{ "ok": false, "line": n, "column": m, "message": "…" }`, with the position
/// taken from the fault so the page can mark the line.
pub fn inspect(src : String, sort : Bool) -> String {
  try {
    let tree = @moontoml.loads(src[:])
    let copy = @moontoml.dumps(tree, sort~)
    "{ \"ok\": true, \"tree\": " +
    tree.stringify() +
    ", \"copy\": " +
    Json::string(copy).stringify() +
    " }"
  } catch {
    fault => {
      let at = fault.at()
      "{ \"ok\": false, \"line\": " +
      at.line.to_string() +
      ", \"column\": " +
      at.column.to_string() +
      ", \"message\": " +
      Json::string(fault.to_string()).stringify() +
      " }"
    }
  }
}
