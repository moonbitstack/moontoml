// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The whole of `toml-test`'s TOML 1.0.0 corpus, read and written.
///
/// The corpus is in `vectors_accepted.mbt` and `vectors_rejected.mbt`, written
/// there by `scripts/gen_vectors.py` from a pinned release. A failure names the
/// document and what was read instead, and every case is tried before the test
/// reports, so one run says how far off the reader is.

///|
test "toml-test: every valid document reads as the tree it denotes" {
  let failures : Array[String] = []
  let mut count = 0
  for case in accepted() {
    count = count + 1
    match read_fault(case) {
      Some(why) => failures.push("\{case.name}: \{why}")
      None => ()
    }
  }
  report("valid", count, failures)
}

///|
test "toml-test: every invalid document is refused" {
  let failures : Array[String] = []
  let mut count = 0
  for case in rejected() {
    count = count + 1
    let got = Ok(@moontoml.decode_bytes(case.src[:])) catch { _ => Err(()) }
    match got {
      Ok(_) => failures.push("\{case.name}: read a document the format refuses")
      Err(_) => ()
    }
  }
  report("invalid", count, failures)
}

///|
test "toml-test: every valid document writes back to the same tree" {
  let failures : Array[String] = []
  let mut count = 0
  for case in accepted() {
    count = count + 1
    match write_fault(case) {
      Some(why) => failures.push("\{case.name}: \{why}")
      None => ()
    }
  }
  report("written", count, failures)
}

///|
test "toml-test: the tree and the JSON tree agree on every document they both read" {
  let failures : Array[String] = []
  let mut count = 0
  for case in accepted() {
    // A byte-order mark is the one thing `loads` reads differently: it takes text,
    // and `load` is what skips the mark.
    if starts_with_mark(case.src) {
      continue
    }
    count = count + 1
    let text = @utf8.decode(case.src, ignore_bom=false) catch {
      _ => {
        failures.push("\{case.name}: not UTF-8")
        continue
      }
    }
    let typed = @moontoml.decode(text, flavor=@moontoml.strict) catch {
      _ => {
        failures.push("\{case.name}: decode refused it")
        continue
      }
    }
    let tree = @moontoml.loads(text, flavor=@moontoml.strict) catch {
      _ => {
        failures.push("\{case.name}: loads refused it")
        continue
      }
    }
    if typed.to_json().stringify() != tree.stringify() {
      failures.push(
        "\{case.name}: \{typed.to_json().stringify()} against \{tree.stringify()}",
      )
    }
  }
  report("both readings", count, failures)
}

///|
/// Why a valid document did not read as the tree it denotes, or nothing.
fn read_fault(case : Accepted) -> String? {
  let got = Ok(@moontoml.decode_bytes(case.src[:])) catch {
    fault => Err(fault.to_string())
  }
  let value = match got {
    Ok(value) => value
    Err(why) => return Some("refused: \{why}")
  }
  let want = Ok(of_typed(@json.parse(case.want[:]))) catch { _ => Err(()) }
  let expected = match want {
    Ok(value) => value
    Err(_) => return Some("the expectation does not read")
  }
  if value != expected {
    return Some("read \{typed(value).stringify()}")
  }
  None
}

///|
/// Why a valid document did not write back to the tree it came from, or nothing.
///
/// This is the writing direction as the tool tests it: the tree of the expectation
/// goes through `encode`, and the document that comes out is read again. The tool
/// reads it with its own parser; this reads it with the one under test, which is
/// the part a vector can check on its own.
fn write_fault(case : Accepted) -> String? {
  let want = Ok(of_typed(@json.parse(case.want[:]))) catch { _ => Err(()) }
  let value = match want {
    Ok(value) => value
    Err(_) => return Some("the expectation does not read")
  }
  let text = @moontoml.encode(value)
  let back = Ok(@moontoml.decode(text[:])) catch {
    fault => Err("wrote a document it refuses: \{fault.to_string()}")
  }
  match back {
    Ok(again) =>
      if again != value {
        Some("wrote \{text} which reads back as a different tree")
      } else {
        None
      }
    Err(why) => Some(why)
  }
}

///|
fn starts_with_mark(src : Bytes) -> Bool {
  src.length() >= 3 &&
  src[0] == b'\xef' &&
  src[1] == b'\xbb' &&
  src[2] == b'\xbf'
}

///|
/// Fail with the first few names, so a run says which documents are still wrong.
fn report(kind : String, count : Int32, failures : Array[String]) -> Unit raise {
  if failures.length() == 0 {
    return
  }
  let out = StringBuilder()
  out.write_string("\{failures.length()} of \{count} \{kind} documents failed:")
  let shown = if failures.length() < 12 { failures.length() } else { 12 }
  for i = 0; i < shown; i = i + 1 {
    out.write_string("\n  ")
    out.write_string(failures[i])
  }
  fail(out.to_string())
}
