// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A float, and the text it was written as.
///
/// TOML spells one number many ways — `1e06`, `1000000.0`, `1_000_000.0` — and a
/// document read and written again should not turn one spelling into another. The
/// text is kept whenever the source had one and it is also a JSON spelling, since
/// that is what a tree of `Json` can carry; a float built in code has none and is
/// written from its value.
#derive(Debug)
pub(all) struct Real {
  value : Double
  repr : String?
}

///|
/// A float from its value alone.
pub fn Real::new(value : Double) -> Real {
  { value, repr: None, }
}

///|
/// Two floats are equal when they are the same number: the spelling says how it
/// was written, not what it is. A NaN equals a NaN here, because this is the
/// equality a document needs.
pub impl Eq for Real with fn equal(self, other) -> Bool {
  self.value == other.value || (self.value.is_nan() && other.value.is_nan())
}

///|
pub extend Real with Debug::{to_repr}

///|
pub extend Real with Eq::{not_equal, equal}

///|
/// A string value.
pub fn Value::string(text : String) -> Value {
  String(text)
}

///|
/// An integer value.
pub fn Value::integer(whole : Int64) -> Value {
  Integer(whole)
}

///|
/// A boolean value.
pub fn Value::boolean(flag : Bool) -> Value {
  Boolean(flag)
}

///|
/// An array value.
pub fn Value::array(items : Array[Value]) -> Value {
  Array(items)
}

///|
/// A table value, which is what a document is.
pub fn Value::table(fields : Map[String, Value]) -> Value {
  Table(fields)
}

///|
/// A TOML value, kind for kind.
///
/// A `Json` tree has no date-time and only one number, so `loads` reads a
/// timestamp into text and a 64-bit integer into a double. `decode` reads the same
/// document and keeps what the format says it is, which is what writing it back
/// without guessing needs.
#derive(Debug)
pub(all) enum Value {
  String(String)
  Integer(Int64)
  Float(Real)
  Boolean(Bool)
  Datetime(@moondate.Moment)
  Array(Array[Value])
  Table(Map[String, Value])
}

///|
pub impl Eq for Value with fn equal(self, other) -> Bool {
  match (self, other) {
    (String(a), String(b)) => a == b
    (Integer(a), Integer(b)) => a == b
    (Float(a), Float(b)) => a == b
    (Boolean(a), Boolean(b)) => a == b
    (Datetime(a), Datetime(b)) => same_moment(a, b)
    (Array(a), Array(b)) => {
      if a.length() != b.length() {
        return false
      }
      for i = 0; i < a.length(); i = i + 1 {
        if a[i] != b[i] {
          return false
        }
      }
      true
    }
    (Table(a), Table(b)) => {
      if a.length() != b.length() {
        return false
      }
      for name, held in a {
        guard b.get(name) is Some(far) else { return false }
        if held != far {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
pub extend Value with Debug::{to_repr}

///|
pub extend Value with Eq::{not_equal, equal}

///|
/// Whether two date-times are the same instant.
///
/// Two offsets spell the same instant differently, and TOML's four kinds are not
/// interchangeable: a local date-time is not an offset one, so the kinds must
/// match before the instant is compared.
fn same_moment(a : @moondate.Moment, b : @moondate.Moment) -> Bool {
  match (a, b) {
    (Zoned(date~, time~, ..), Zoned(date=far_date, time=far_time, ..)) =>
      match (a.epoch(), b.epoch()) {
        (Some(here), Some(there)) => here == there
        _ => date == far_date && time == far_time
      }
    (Plain(..), Plain(..)) | (Day(..), Day(..)) | (Clock(..), Clock(..)) =>
      a.to_string() == b.to_string()
    _ => false
  }
}

///|
/// The tree as `Json`, which is what `loads` answers.
///
/// A date-time becomes the RFC 3339 text of the moment it is, the same text
/// `loads` gives, so a caller moving between the two forms sees one spelling.
pub impl ToJson for Value with fn to_json(self) -> Json {
  match self {
    String(s) => Json::string(s)
    Integer(n) => Json::number(n.to_double(), repr=n.to_string())
    Float(real) =>
      match real.repr {
        Some(text) => Json::number(real.value, repr=text)
        None => Json::number(real.value)
      }
    Boolean(b) => Json::boolean(b)
    Datetime(m) => Json::string(m.to_string())
    Array(items) => Json::array(items.map(fn(item) { item.to_json() }))
    Table(fields) => {
      let out : Map[String, Json] = Map([])
      for name, held in fields {
        out[name] = held.to_json()
      }
      Json::object(out)
    }
  }
}

///|
pub extend Value with ToJson::{to_json}

///|
/// The tree a `Json` denotes, for the writer that starts from one.
///
/// A string that is spelled like a date-time becomes one, because a `Json` tree
/// cannot say whether it meant a timestamp; `decode` is the entry point that
/// knows. A number that is whole and small enough becomes an integer, which is how
/// a port stays `12000` rather than `12000.0`.
fn value_of_json(json : Json) -> Value {
  match json {
    Null =>
      // TOML has no null. A caller that needs one spells it, and an empty string
      // is the least surprising, as it is for every encoder in reach.
      String("")
    True => Boolean(true)
    False => Boolean(false)
    Number(n, repr~) =>
      match repr {
        Some(text) =>
          match int64_of_text(text) {
            Some(whole) => Integer(whole)
            None => Float({ value: n, repr: Some(text), })
          }
        None =>
          if n == n.floor() && n.abs() < 1.0e15 {
            Integer(n.to_int64())
          } else {
            Float(Real::new(n))
          }
      }
    String(s) =>
      if is_moment(s) {
        Datetime(@moondate.parse(s[:])) catch {
          _ => String(s)
        }
      } else {
        String(s)
      }
    Array(items) => Array(items.map(value_of_json))
    Object(fields) => {
      let out : Map[String, Value] = Map([])
      for name, held in fields {
        out[name] = value_of_json(held)
      }
      Table(out)
    }
  }
}

///|
/// An integer written the way JSON writes one, or nothing.
fn int64_of_text(text : String) -> Int64? {
  if text.length() == 0 {
    return None
  }
  for i = 0; i < text.length(); i = i + 1 {
    let c = text[i].to_int()
    let digit = (c >= 0x30 && c <= 0x39) || (i == 0 && (c == 0x2d || c == 0x2b))
    if !digit {
      return None
    }
  }
  Some(@string.parse_int64(text[:])) catch {
    _ => None
  }
}
