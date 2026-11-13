// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Open `src` as a document that keeps how it was written, optionally change one
/// value in place, and answer what the library has before and after.
///
/// `path` is a JSON array of the key's segments — `["soil","ph"]` is the key
/// under a `[soil]` header — and `value` is a TOML value written as a person
/// would write it, read by the library rather than by the page. An empty path or
/// an empty value changes nothing, which is how the page asks for the document
/// and the keys it holds.
///
/// The answer is `{ "ok": true, "paths": [{ "path": [...], "line": n }],
/// "before": "<toml>", "after": "<toml>", "moved": true }`. `moved` is nothing
/// when the path named nothing, so the page can say the document was left alone.
pub fn kept(src : String, path : String, value : String) -> String {
  let doc = @moontoml.decode_doc(src[:]) catch {
    fault => return spelled(refused_answer(fault.to_string(), fault.at()))
  }
  let before = doc.render()
  let segments = segments_of(path)
  let mut moved : Bool? = None
  if segments.length() > 0 && value != "" {
    match value_of(value) {
      Some(held) => moved = doc.set(segments, held)
      None => ()
    }
  }
  spelled(
    Json::object({
      "ok": Json::boolean(true),
      "paths": paths_of(doc),
      "before": Json::string(before),
      "after": Json::string(doc.render()),
      "moved": match moved {
        Some(flag) => Json::boolean(flag)
        None => @json.null
      },
    }),
  )
}

///|
/// The keys a document holds, each with the line it is on, so the page can offer
/// the ones that can be changed.
fn paths_of(doc : @moontoml.Doc) -> Json {
  let rows : Array[Json] = []
  for item in doc.items {
    guard item.kind is Pair else { continue }
    let line = line_at(doc.src, item.start)
    rows.push(
      Json::object({
        "path": Json::array(item.path.map(Json::string)),
        "line": Json::number(line.to_double(), repr=line.to_string()),
      }),
    )
  }
  Json::array(rows)
}

///|
/// The line an offset is on, counted from one.
fn line_at(src : String, offset : Int32) -> Int32 {
  let mut line = 1
  for i = 0; i < offset && i < src.length(); i = i + 1 {
    if src[i] == '\n' {
      line = line + 1
    }
  }
  line
}

///|
/// A path handed in as JSON, which is the form that keeps a key with a dot in it
/// a single segment. Anything that is not an array of strings names nothing.
fn segments_of(text : String) -> Array[String] {
  let parsed = @moonjson.loads(text[:], @moonjson.strict) catch {
    _ => return []
  }
  match parsed {
    Json::Array(items) => {
      let out : Array[String] = []
      for item in items {
        match item {
          Json::String(segment) => out.push(segment)
          _ => return []
        }
      }
      out
    }
    _ => []
  }
}

///|
/// A value written the way a person writes one, read by the library: the text is
/// put in a document of its own and the value is taken out of it.
fn value_of(text : String) -> @moontoml.Value? {
  let doc = @moontoml.decode_doc(("v = " + text)[:]) catch { _ => return None }
  doc.get(["v"])
}
