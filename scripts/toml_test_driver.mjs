// The command `toml-test` runs: a document on standard input, its tree on standard
// output, and a refusal on standard error.
//
//     node scripts/toml_test_driver.mjs decode
//     node scripts/toml_test_driver.mjs encode
//
// The work is the library's, compiled to JavaScript; this file only moves bytes
// between the process and it. `MOONTOML_JS` overrides where the build is read from.

import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const engine =
  process.env.MOONTOML_JS ?? "_build/js/release/build/conformance/conformance.js";
const [mode] = process.argv.slice(2);
if (mode !== "decode" && mode !== "encode") {
  process.stderr.write("usage: toml_test_driver.mjs decode|encode\n");
  process.exit(2);
}

const wasm = await import(pathToFileURL(engine).href);
const input = readFileSync(0);
const reply = JSON.parse(
  (mode === "decode" ? wasm.decode_document : wasm.encode_document)(input),
);
if (!reply.ok) {
  process.stderr.write(reply.text + "\n");
  process.exit(1);
}
process.stdout.write(reply.text);
if (!reply.text.endsWith("\n")) {
  process.stdout.write("\n");
}
