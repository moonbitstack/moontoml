// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The four editions this library reads, in the order they grew.
let editions_read : Array[(String, @moontoml.Edition)] = [
  ("0.4", @moontoml.V04),
  ("0.5", @moontoml.V05),
  ("1.0.0", @moontoml.V100),
  ("1.1", @moontoml.V110),
]

///|
/// Read `src` at each edition and answer one verdict per edition:
/// `{ "edition": "0.4", "ok": true }`, or the place and the fault where the
/// edition refuses it.
///
/// The verdicts are the library's own — each row is a real read at that edition,
/// not a table of what the editions are supposed to allow.
pub fn editions(src : String) -> String {
  let rows = Json::array(
    editions_read.map(fn(row) {
      let (name, edition) = row
      let read = Ok(
        @moontoml.decode(src[:], flavor=@moontoml.Flavor::new(edition~)),
      ) catch {
        fault => Err(fault)
      }
      let verdict = match read {
        Ok(_) =>
          Json::object({
            "edition": Json::string(name),
            "ok": Json::boolean(true),
          })
        Err(fault) => {
          let refused = refused_answer(fault.to_string(), fault.at())
          // The place is already in the refusal; this adds which edition refused.
          let fields = match refused {
            Json::Object(fields) => fields
            _ => Map([])
          }
          fields["edition"] = Json::string(name)
          Json::object(fields)
        }
      }
      verdict
    }),
  )
  spelled(Json::object({ "rows": rows }))
}
