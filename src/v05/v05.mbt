// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The edition this package reads at: every entry point below reads here.
pub let edition : Edition = V05

// The preset at this edition, the preset depth.

///|
let preset : Flavor = @moontoml.Flavor::new(edition~)

///|
/// The document in `src`, read at TOML 0.5.
pub fn decode(src : StringView) -> Value raise Refused {
  @moontoml.decode(src, flavor=preset)
}

///|
/// The document in `src`, read at TOML 0.5, decoded as UTF-8.
pub fn decode_bytes(src : BytesView, bom~ : Bool = true) -> Value raise Refused {
  @moontoml.decode_bytes(src, flavor=preset, bom~)
}

///|
/// The document in `src`, read at TOML 0.5, as a tree of `Json`.
pub fn loads(src : StringView) -> Json raise Refused {
  @moontoml.loads(src, flavor=preset)
}

///|
/// The document in `src`, read at TOML 0.5, as a tree of `Json`, decoded as UTF-8.
pub fn load(src : BytesView, bom~ : Bool = true) -> Json raise Refused {
  @moontoml.load(src, flavor=preset, bom~)
}

///|
/// The document in `src`, kept as it was written, read at TOML 0.5.
pub fn decode_doc(src : StringView) -> Doc raise Refused {
  @moontoml.Doc::decode(src, flavor=preset)
}

///|
/// The value types and the writing entry points, which are the same at every
/// edition.
pub using @moontoml {
  type Value,
  type Flavor,
  type Edition,
  type At,
  type Real,
  type Refused,
  type Doc,
  encode,
  encode_bytes,
  dumps,
  dump,
}
