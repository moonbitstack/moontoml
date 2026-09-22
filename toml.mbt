// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Where in the source something is: the offset in code units, and the line and
/// column a person counts from one.
pub(all) struct At {
  at : Int
  line : Int
  column : Int
} derive(Eq, Debug)

///|
pub impl Show for At with fn output(self, logger) {
  logger.write_string("\{self.line}:\{self.column}")
}

///|
pub extend At with Debug::{to_repr}

///|
pub extend At with Show::{to_string, output}

///|
pub extend At with Eq::{not_equal, equal}

///|
/// Why a document was refused.
///
/// `Redefined` is the one TOML has that JSON does not: §1 says a key may be
/// defined only once, and so may a table, so a second definition is an error
/// rather than a value that wins. It is the rule that makes a TOML file safe to
/// append to.
pub(all) suberror Refused {
  Unexpected(At, Char)
  Truncated(At)
  BadEscape(At)
  BadNumber(At)
  BadDate(At)
  Redefined(At, String)
  Trailing(At)
  TooDeep(At)
  BadUtf8(At)
} derive(Eq, Debug)

///|
/// A refusal prints as the fault and the line it is on.
pub impl Show for Refused with fn output(self, logger) {
  match self {
    Unexpected(at, c) => logger.write_string("\{at}: unexpected '\{c}'")
    Truncated(at) => logger.write_string("\{at}: ends mid-document")
    BadEscape(at) => logger.write_string("\{at}: not an escape")
    BadNumber(at) => logger.write_string("\{at}: not a number")
    BadDate(at) => logger.write_string("\{at}: not a date or time")
    Redefined(at, k) => logger.write_string("\{at}: \{k} is already defined")
    Trailing(at) => logger.write_string("\{at}: trailing content")
    TooDeep(at) => logger.write_string("\{at}: nested too deep")
    BadUtf8(at) => logger.write_string("\{at}: not UTF-8")
  }
}

///|
pub extend Refused with Debug::{to_repr}

///|
pub extend Refused with Show::{to_string, output}

///|
pub extend Refused with Eq::{not_equal, equal}

///|
/// Where the refusal happened.
///
/// Every variant carries a position, so a caller reporting a line does not have to
/// match all nine of them to get at it.
pub fn Refused::at(self : Refused) -> At {
  match self {
    Unexpected(at, _)
    | Truncated(at)
    | BadEscape(at)
    | BadNumber(at)
    | BadDate(at)
    | Redefined(at, _)
    | Trailing(at)
    | TooDeep(at)
    | BadUtf8(at) => at
  }
}

///|
/// How a document is read.
///
/// The preset is [`strict`]. Build another with [`Flavor::new`], or update one in
/// place with `{ ..strict, depth: 64 }`.
///
/// There is no knob for a repeated key. TOML 1.0.0 §1 makes redefinition an error,
/// not a policy, so making it configurable would be offering to read a document the
/// format says is not one.
pub(all) struct Flavor {
  depth : Int
} derive(Eq, Debug)

///|
pub extend Flavor with Debug::{to_repr}

///|
pub extend Flavor with Eq::{not_equal, equal}

///|
/// How deep a document may nest.
///
/// 500 is what this family uses for JSON and YAML, between Jackson's 1000 and
/// serde_json's 128.
pub let depth : Int = 500

///|
/// The preset.
pub let strict : Flavor = { depth, }

///|
/// A flavor by name, every knob with the preset's value.
pub fn Flavor::new(depth? : Int = depth) -> Flavor {
  { depth, }
}

///|
/// The document in `src`.
///
/// TOML defines one document rather than a stream, so there is no plural form of
/// this — unlike `moonyaml`, where `---` makes both meaningful.
pub fn loads(src : StringView, flavor? : Flavor = strict) -> Json raise Refused {
  Reader::new(src, flavor).document()
}

///|
/// The document in `src`, decoded as UTF-8.
///
/// TOML 1.0.0 §1 says a file is UTF-8 and does not allow a byte-order mark; `bom`
/// skips one anyway, because an editor on Windows writes it and refusing the file
/// helps nobody. Pass `bom=false` to hold the format to its word.
pub fn load(
  src : BytesView,
  flavor? : Flavor = strict,
  bom? : Bool = true,
) -> Json raise Refused {
  let text = @utf8.decode(src, ignore_bom=bom) catch {
    _ => raise BadUtf8({ at: 0, line: 1, column: 1, })
  }
  loads(text, flavor~)
}
