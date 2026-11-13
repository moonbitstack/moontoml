import { useState } from "react";
import { CodeBlock, Footer, Header, Inline, Output, SecHead } from "./util";
import { LedgerDemo } from "./ledger";

const STATS = [
  { big: "0.4–1.1", label: "the editions it reads" },
  { big: "4", label: "string forms, with escapes" },
  { big: "4", label: "integer bases: dec, hex, oct, bin" },
  { big: "4", label: "date-time types, read as dates" },
];

const FEATURES = [
  {
    no: "I",
    title: "Reads the whole format",
    body: "Bare, quoted and dotted keys. [table] and [[array of tables]]. Four string forms, four integer bases, floats with inf and nan, four date-times. Arrays across lines; inline tables.",
  },
  {
    no: "II",
    title: "Keeps what a double would lose",
    body: "`decode` gives every value the kind the format says it has: a date is a date, an integer is 64 bits. Through a `Json` tree a number's digits travel beside the value instead, so 9007199254740993 writes back as itself.",
  },
  {
    no: "III",
    title: "Keeps the document, not the tree",
    body: "`decode_doc` holds the page it read: every line, the comment before it, the blank lines between. Change one value and `render` writes the rest back byte for byte, so the diff is the one line that moved.",
  },
  {
    no: "IV",
    title: "Reads it at the edition it was written",
    body: "A `0.5` file refuses of a `0.4` and reads in full at its own; a `1.1` file of newlines-in-inline-tables and seconds-less time reads at `v110`. The subpackages pin the grammar; the root reads it with a `flavor`.",
  },
  {
    no: "V",
    title: "Refuses what TOML refuses",
    body: "A key defined twice, a repeated header, a dotted key later opened by a header, a key added to a closed inline table. Each refusal carries a line and a column.",
  },
  {
    no: "VI",
    title: "Writes it back to read",
    body: "Scalars first, then tables under their own headers, arrays of tables as [[…]]. sort gives one order; off, the document keeps its own.",
  },
];

const STEPS = [
  {
    n: "01",
    title: "Source",
    body: "The bytes are decoded as UTF-8. A leading byte-order mark is skipped unless bom=false.",
    code: "load(bytes)   // BytesView -> Json",
  },
  {
    n: "02",
    title: "Cursor",
    body: "The reader keeps the offset, the line and the column. Every refusal has a place to point at.",
    code: "At { at, line, column }",
  },
  {
    n: "03",
    title: "Tokens",
    body: "One pass reads keys, headers and values: bare and quoted keys, dotted paths, four string forms, four integer bases, dates.",
    code: "key = value",
  },
  {
    n: "04",
    title: "Tree",
    body: "Tables and arrays are built as a Json object. The redefinition rules decide whether a second write is allowed.",
    code: "Json::object(...)",
  },
];

const FAULTS = [
  ["Unexpected(at, c)", "a character that cannot begin what was expected"],
  ["Truncated(at)", "the document ends mid-thing"],
  ["BadEscape(at)", "a backslash escape TOML does not define"],
  ["BadNumber(at)", "a number TOML cannot spell"],
  ["BadDate(at)", "a date or time the calendar does not have"],
  ["Redefined(at, key)", "a key or table defined twice"],
  ["MixedArray(at)", "a second kind of value in an array, at an edition before mixed ones"],
  ["Trailing(at)", "content after a value where only a comment or newline may follow"],
  ["TooDeep(at)", "nesting past the flavor's limit"],
  ["BadUtf8(at)", "bytes that are not UTF-8"],
];

function Pipeline() {
  const [on, setOn] = useState(0);
  const step = STEPS[on];
  return (
    <>
      <div className="pipe">
        {STEPS.map((s, i) => (
          <button
            key={s.n}
            type="button"
            aria-pressed={i === on}
            onClick={() => setOn(i)}
          >
            <span className="pn">{s.n}</span>
            <span className="pt">{s.title}</span>
          </button>
        ))}
      </div>
      <div className="pipe-note">
        <p>{<Inline text={step.body} />}</p>
        <code>{step.code}</code>
      </div>
    </>
  );
}

export function Home() {
  return (
    <>
      <Header page="home" />
      <main className="wrap">
        <section className="hero">
          <div>
            <p className="eyebrow">TOML 1.0.0 · configuration, kept as a ledger</p>
            <h1>
              Every config,
              <br />a page in the <span className="accent">ledger</span>.
            </h1>
            <p className="lede">
              <strong>moontoml</strong> reads a TOML document into a <code>Json</code> tree, or kind
              for kind, and writes it back. Values survive the round trip. A broken rule comes back
              with a line and a column.
            </p>
            <div className="cta">
              <a className="btn" href="#ledger">
                Open the ledger
              </a>
              <a className="btn ghost" href="guide.html">
                Read the guide
              </a>
            </div>
          </div>

          <aside className="slip" aria-label="Package facts">
            <span className="no">Catalogue No. 1</span>
            <div className="pkg">moonbitstack/moontoml</div>
            <dl>
              <div className="row">
                <dt>Spec</dt>
                <dd>1.0.0</dd>
              </div>
              <div className="row">
                <dt>Licence</dt>
                <dd>Apache-2.0</dd>
              </div>
              <div className="row">
                <dt>Entry points</dt>
                <dd>8</dd>
              </div>
              <div className="row">
                <dt>Tree</dt>
                <dd>Json · Value</dd>
              </div>
            </dl>
            <div className="barcode" aria-hidden="true">
              {Array.from({ length: 30 }).map((_, i) => (
                <i key={i} />
              ))}
            </div>
          </aside>
        </section>

        <div className="stats">
          {STATS.map((s) => (
            <div className="stat" key={s.label}>
              <b>{s.big}</b>
              <span>{s.label}</span>
            </div>
          ))}
        </div>

        <section className="section" id="features">
          <SecHead
            num="§ 0"
            title="What it does, in four slips"
            intro="A reader and a writer over one tree. Nothing else is in the package."
          />
          <div className="features">
            {FEATURES.map((f) => (
              <article className="feature" key={f.no}>
                <span className="no">{f.no}</span>
                <h3>{f.title}</h3>
                <p>{<Inline text={f.body} />}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="section" id="ledger">
          <SecHead
            num="§ 1"
            title="The ledger"
            intro="The real library, compiled to JavaScript, running in this page. Write on the left; the tree and the fair copy follow. Break a rule and the margin marks the line."
          />
          <LedgerDemo />
        </section>

        <section className="section" id="reading">
          <SecHead
            num="§ 2"
            title="How a line becomes a table"
            intro="A document is read once, left to right. These are the four places the work happens. Pick one."
          />
          <Pipeline />
        </section>

        <section className="section" id="kept">
          <SecHead
            num="§ 3"
            title="The document, kept"
            intro={
              <Inline text="A tree forgets the page it came from. `decode_doc` does not: it holds every line, the comment before it, and the blank lines between. Change one value and `render` writes the rest back as it was." />
            }
          />
          <div className="kept">
            <CodeBlock
              label="moonbit"
              code={String.raw`let page = @moontoml.decode_doc(src[:])
let moved = page.set(["beds"], @moontoml.Value::integer(6))
page.render()  // the rest is the source`}
            />
            <Output
              text={String.raw`# a garden, planted 1979
name = "garden"  # the one by the gate
beds = 6

[soil]
kind = "loam"
ph = 6.5`}
            />
          </div>
          <p className="kept-note">
            <Inline text="`get` reaches a value by path, `set` replaces one in place, and `render` answers the document. When the path names nothing, `set` answers nothing and the document is left as it was. This is the reading for `moon.mod` and the config a person edits by hand — the diff is the one line that moved." />
          </p>
        </section>

        <section className="section" id="editions">
          <SecHead
            num="§ 4"
            title="The editions"
            intro={
              <Inline text="The root reads TOML 1.0.0. The editions differ by real grammar, and the subpackages pin the one their file was written in — the same entry points, only the edition moves." />
            }
          />
          <dl className="editions">
            <div className="edition">
              <dt><code>…/moontoml</code></dt>
              <dd><b>1.0.0</b> — dotted keys, prefixed integers, mixed-type arrays, one-line inline tables</dd>
            </div>
            <div className="edition">
              <dt><code>…/moontoml/v110</code></dt>
              <dd><b>1.1</b> — inline tables that span lines with a trailing comma, <code>\x</code> and <code>\e</code> escapes, a time that may drop its seconds</dd>
            </div>
            <div className="edition">
              <dt><code>…/moontoml/v05</code></dt>
              <dd><b>0.5</b> — dotted keys, prefixed integers, <code>inf</code> and <code>nan</code>, the local date-time kinds; an array of one kind</dd>
            </div>
            <div className="edition">
              <dt><code>…/moontoml/v04</code></dt>
              <dd><b>0.4</b> — no dotted keys, no prefixed integers, no <code>inf</code> or <code>nan</code>, only the offset date-time</dd>
            </div>
          </dl>
          <CodeBlock
            label="moonbit"
            code={String.raw`// the 1.0.0 reading refuses a 1.1 file
let r = try {
  let _ = @moontoml.loads("p = { x = 1,\n}"[:])
  false
} catch {
  _ => true
}
assert_eq(r, true)
// and v110 reads it in full
assert_eq(@v110.loads("p = { x = 1,\n}"[:]).stringify(), "{\"p\":{\"x\":1}}")`}
          />
        </section>

        <section className="section" id="faults">
          <SecHead
            num="§ 5"
            title="The ten refusals"
            intro={
              <Inline text="Every fault carries an At — offset, line, column. Refused::at reaches it without matching the variant." />
            }
          />
          <dl className="faults">
            {FAULTS.map(([name, what]) => (
              <div className="fault" key={name}>
                <dt>{name}</dt>
                <dd>{what}</dd>
              </div>
            ))}
          </dl>
        </section>

        <section className="section" id="exits">
          <SecHead num="§ 6" title="Where to go next" />
          <div className="exits">
            <a className="exit" href="guide.html">
              <b>The guide</b>
              <span>install, read, write, refuse</span>
            </a>
            <a className="exit" href="specimens.html">
              <b>The specimens</b>
              <span>four grammars, one moved line, ten refusals</span>
            </a>
            <a className="exit" href="api.html">
              <b>The API</b>
              <span>every type, function and value</span>
            </a>
            <a className="exit" href="https://mooncakes.io/docs/moonbitstack/moontoml">
              <b>mooncakes</b>
              <span>the package page</span>
            </a>
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}
