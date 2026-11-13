// A batch of reads and writes through the compiled library, for the Python
// differential script. One process for the whole corpus rather than one per
// document: the work is the library's, this file only moves bytes in and out.
//
//     node scripts/interop_driver.mjs < requests.json > answers.json
//
// `MOONTOML_JS` overrides where the build is read from.

import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const engine =
  process.env.MOONTOML_JS ?? "_build/js/release/build/conformance/conformance.js";
const wasm = await import(pathToFileURL(engine).href);
const jobs = JSON.parse(readFileSync(0, "utf8"));
const answers = jobs.map((job) => {
  const bytes = Buffer.from(job.data, "base64");
  const reply =
    job.mode === "decode"
      ? wasm.decode_document(bytes, job.edition ?? 10)
      : wasm.encode_document(bytes);
  return JSON.parse(reply);
});
process.stdout.write(JSON.stringify(answers));
