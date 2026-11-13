// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Read `src` and name the fault when there is one: `{ "ok": false, "kind":
/// "Redefined", "line": n, "column": m, "message": "…" }`, or `{ "ok": true }`.
///
/// The kind is the variant of `Refused` the library raised, so a page that shows
/// a specimen of each fault is showing what the library actually raises for it.
/// `edition` picks the grammar, with the numbers the conformance driver uses.
pub fn fault(src : String, edition : Int32) -> String {
  let read : Result[@moontoml.Value, @moontoml.Refused] = Ok(
    @moontoml.decode(src[:], flavor=flavor_of(edition)),
  ) catch {
    error => Err(error)
  }
  answer(read)
}

///|
/// The same, over bytes: this is the only way to reach `BadUtf8`, which is a
/// fault of the bytes a file is made of and not of the text they spell.
pub fn fault_bytes(src : Bytes, edition : Int32) -> String {
  let read : Result[@moontoml.Value, @moontoml.Refused] = Ok(
    @moontoml.decode_bytes(src[:], flavor=flavor_of(edition)),
  ) catch {
    error => Err(error)
  }
  answer(read)
}

///|
fn answer(read : Result[@moontoml.Value, @moontoml.Refused]) -> String {
  match read {
    Ok(_) => spelled(Json::object({ "ok": Json::boolean(true) }))
    Err(fault) => {
      let refused = refused_answer(fault.to_string(), fault.at())
      let fields = match refused {
        Json::Object(fields) => fields
        _ => Map([])
      }
      fields["kind"] = Json::string(kind_of(fault))
      spelled(Json::object(fields))
    }
  }
}

///|
fn flavor_of(edition : Int32) -> @moontoml.Flavor {
  @moontoml.Flavor::new(
    edition=match edition {
      4 => @moontoml.V04
      5 => @moontoml.V05
      11 => @moontoml.V110
      _ => @moontoml.V100
    },
  )
}

///|
/// The name of the variant, which is the name the README and the API use.
fn kind_of(fault : @moontoml.Refused) -> String {
  match fault {
    Unexpected(_, _) => "Unexpected"
    Truncated(_) => "Truncated"
    BadEscape(_) => "BadEscape"
    BadNumber(_) => "BadNumber"
    BadDate(_) => "BadDate"
    Redefined(_, _) => "Redefined"
    MixedArray(_) => "MixedArray"
    Trailing(_) => "Trailing"
    TooDeep(_) => "TooDeep"
    BadUtf8(_) => "BadUtf8"
  }
}
