import { useState } from "react";
import { Footer, Header, Inline, SecHead } from "./util";
import { LedgerDemo } from "./ledger";

const STATS = [
  { big: "1.0.0", label: "the specification it reads" },
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
    title: "Refuses what TOML refuses",
    body: "A key defined twice, a repeated header, a dotted key later opened by a header, a key added to a closed inline table. Each refusal carries a line and a column.",
  },
  {
    no: "III",
    title: "Keeps what a double would lose",
    body: "A number's digits travel beside the value, so 9007199254740993 writes back as itself. Dates are read as RFC 3339 text and written back bare, not quoted.",
  },
  {
    no: "IV",
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
              <strong>moontoml</strong> reads a TOML document into a <code>Json</code> tree and
              writes it back. Values survive the round trip. A broken rule comes back with a line
              and a column.
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
                <dd>4</dd>
              </div>
              <div className="row">
                <dt>Tree</dt>
                <dd>Json</dd>
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

        <section className="section" id="faults">
          <SecHead
            num="§ 3"
            title="The nine refusals"
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
          <SecHead num="§ 4" title="Where to go next" />
          <div className="exits">
            <a className="exit" href="guide.html">
              <b>The guide</b>
              <span>install, read, write, refuse</span>
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
