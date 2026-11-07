// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The whole of `toml-test`'s TOML 1.1.0 corpus, read at the 1.1 edition.
///
/// The edition is what changes between this and the 1.0.0 corpus: an inline
/// table may span lines and end with a comma, a string may use `\x` and `\e`,
/// and a time may drop its seconds. The reader is the same, at a different
/// grammar.
let eleven : @moontoml.Flavor = @moontoml.Flavor::new(edition=@moontoml.V110)

///|
test "toml 1.1: every valid document reads as the tree it denotes" {
  let failures : Array[String] = []
  let mut count = 0
  for case in accepted_11() {
    count = count + 1
    match read_fault_11(case, eleven) {
      Some(why) => failures.push("\{case.name}: \{why}")
      None => ()
    }
  }
  report("1.1 valid", count, failures)
}

///|
test "toml 1.1: every invalid document is refused" {
  let failures : Array[String] = []
  let mut count = 0
  for case in rejected_11() {
    count = count + 1
    let got = Ok(@moontoml.decode_bytes(case.src[:], flavor=eleven)) catch {
      _ => Err(())
    }
    match got {
      Ok(_) => failures.push("\{case.name}: read a document the format refuses")
      Err(_) => ()
    }
  }
  report("1.1 invalid", count, failures)
}

///|
test "toml 1.1: every valid document round-trips byte for byte" {
  let failures : Array[String] = []
  let mut count = 0
  for case in accepted_11() {
    count = count + 1
    let text = @utf8.decode(case.src, ignore_bom=false) catch {
      _ => {
        failures.push("\{case.name}: not UTF-8")
        continue
      }
    }
    let outcome = try {
      let doc = @moontoml.Doc::decode(text[:], flavor=eleven)
      if doc.render() != text {
        "the write back is not the source"
      } else {
        ""
      }
    } catch {
      why => "\{why.to_string()}"
    }
    if outcome != "" {
      failures.push("\{case.name}: \{outcome}")
    }
  }
  report("1.1 fidelity", count, failures)
}

///|
/// Why a valid document did not read, at the named edition, or nothing.
fn read_fault_11(case : Accepted, flavor : @moontoml.Flavor) -> String? {
  let got = Ok(@moontoml.decode_bytes(case.src[:], flavor~)) catch {
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
