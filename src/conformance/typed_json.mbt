// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A document the format accepts, with the tree it denotes as `toml-test` writes
/// one.
pub(all) struct Accepted {
  name : String
  src : Bytes
  want : String
}

///|
/// A document the format refuses.
pub(all) struct Rejected {
  name : String
  src : Bytes
}

///|
/// The tree of `toml-test`'s JSON: every scalar is a pair of `type` and `value`,
/// and a table or an array is bare.
///
/// The four date-time kinds and the split between an integer and a float are what
/// this carries and a `Json` tree does not, which is why the reading under test is
/// `decode` rather than `loads`.
pub fn typed(value : @moontoml.Value) -> Json {
  match value {
    String(s) => scalar("string", s)
    Integer(n) => scalar("integer", n.to_string())
    Float(real) => scalar("float", float_text(real))
    Boolean(b) => scalar("bool", if b { "true" } else { "false" })
    Datetime(m) => scalar(kind_of(m), m.to_string())
    Array(items) => Json::array(items.map(typed))
    Table(fields) => {
      let out : Map[String, Json] = Map([])
      for name, held in fields {
        out[name] = typed(held)
      }
      Json::object(out)
    }
  }
}

///|
fn scalar(kind : String, text : String) -> Json {
  Json::object({ "type": Json::string(kind), "value": Json::string(text) })
}

///|
/// The name `toml-test` gives each of the four date-time kinds.
fn kind_of(m : @moondate.Moment) -> String {
  match m {
    Zoned(..) => "datetime"
    Plain(..) => "datetime-local"
    Day(..) => "date-local"
    Clock(..) => "time-local"
  }
}

///|
/// A float as text a reader parses back to the same number.
fn float_text(real : @moontoml.Real) -> String {
  match real.repr {
    Some(text) => text
    None =>
      if real.value.is_nan() {
        "nan"
      } else if real.value.is_inf() {
        if real.value > 0.0 {
          "inf"
        } else {
          "-inf"
        }
      } else {
        real.value.to_string()
      }
  }
}

///|
/// The tree `toml-test`'s JSON denotes, which is what the writing direction is
/// handed.
pub fn of_typed(json : Json) -> @moontoml.Value raise Error {
  match json {
    Object(fields) =>
      match (fields.get("type"), fields.get("value")) {
        (Some(String(kind)), Some(String(text))) => of_scalar(kind, text)
        _ => of_table(fields)
      }
    Array(items) => @moontoml.Value::array(items.map(of_typed))
    _ => fail_kind("a table or an array")
  }
}

///|
fn of_table(fields : Map[String, Json]) -> @moontoml.Value raise Error {
  let out : Map[String, @moontoml.Value] = Map([])
  for name, held in fields {
    out[name] = of_typed(held)
  }
  @moontoml.Value::table(out)
}

///|
fn of_scalar(kind : String, text : String) -> @moontoml.Value raise Error {
  match kind {
    "string" => @moontoml.Value::string(text)
    "integer" => @moontoml.Value::integer(@string.parse_int64(text[:]))
    "float" =>
      @moontoml.Value::Float({
        value: @string.parse_double(text[:]),
        repr: None,
      })
    "bool" => @moontoml.Value::boolean(text == "true")
    "datetime" | "datetime-local" | "date-local" | "time-local" =>
      @moontoml.Value::Datetime(@moondate.parse(text[:]))
    _ => fail_kind(kind)
  }
}

///|
fn fail_kind(kind : String) -> @moontoml.Value raise Error {
  raise Failure("not a toml-test value: " + kind)
}
