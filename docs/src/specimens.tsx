import { useMemo, useState } from "react";
import { Footer, Header, Inline, SecHead } from "./util";
import { useEngine } from "./engine";

/* ---------- one line, four grammars -------------------------------------- */

const GRAMMAR = [
  {
    id: "dotted",
    label: "a dotted key",
    src: 'a.b = 1\n',
    note: "0.5 lets a key be written as a path; 0.4 has no dotted keys.",
  },
  {
    id: "hex",
    label: "a prefixed integer",
    src: "n = 0xff\n",
    note: "0.5 adds hexadecimal, octal and binary integers.",
  },
  {
    id: "inf",
    label: "infinity",
    src: "f = inf\n",
    note: "0.5 adds inf and nan as floats.",
  },
  {
    id: "date",
    label: "a local date",
    src: "d = 1979-05-27\n",
    note: "0.5 adds the local date-time kinds; 0.4 has only the offset one.",
  },
  {
    id: "clock",
    label: "a local time",
    src: "t = 07:32:00\n",
    note: "A local time is 0.5 and later, and needs its seconds until 1.1.",
  },
  {
    id: "mixed",
    label: "a mixed array",
    src: 'a = [1, "two"]\n',
    note: "An array holds one kind until 1.0.0.",
  },
  {
    id: "comma",
    label: "a trailing comma",
    src: "p = { x = 1, }\n",
    note: "1.1 lets an inline table end with a comma.",
  },
  {
    id: "lines",
    label: "an inline table across lines",
    src: "p = { x = 1,\n y = 2 }\n",
    note: "1.1 lets an inline table span lines.",
  },
  {
    id: "escape",
    label: "a \\x escape",
    src: 's = "\\x41"\n',
    note: "1.1 adds the \\x and \\e escapes.",
  },
  {
    id: "short",
    label: "a time without seconds",
    src: "t = 07:32\n",
    note: "1.1 lets a time drop its seconds.",
  },
];

type Verdict = {
  edition: string;
  ok: boolean;
  line?: number;
  column?: number;
  message?: string;
};

function GrammarSpecimens() {
  const engine = useEngine();
  const [active, setActive] = useState(GRAMMAR[0].id);
  const [src, setSrc] = useState(GRAMMAR[0].src);
  const chosen = GRAMMAR.find((g) => g.id === active) ?? GRAMMAR[0];

  const rows = useMemo<Verdict[] | null>(() => {
    if (!engine) return null;
    try {
      return (JSON.parse(engine.editions(src)) as { rows: Verdict[] }).rows;
    } catch {
      return null;
    }
  }, [engine, src]);

  return (
    <>
      <div className="spec-chips">
        {GRAMMAR.map((g) => (
          <button
            key={g.id}
            className="chip"
            type="button"
            aria-pressed={active === g.id}
            onClick={() => {
              setActive(g.id);
              setSrc(g.src);
            }}
          >
            {g.label}
          </button>
        ))}
      </div>

      <div className="specimen-book">
        <div className="specimen-slip">
          <span className="pg-label">
            <i>The line</i>
          </span>
          <textarea
            className="spec-input scroll"
            value={src}
            onChange={(e) => {
              setActive("custom");
              setSrc(e.target.value);
            }}
            spellCheck={false}
            wrap="off"
            aria-label="A TOML document to read at each edition"
          />
          <p className="marginalia">
            {active === "custom" ? (
              "your line, read at each edition"
            ) : (
              <Inline text={chosen.note} />
            )}
          </p>
        </div>

        <div className="verdicts">
          {rows === null ? (
            <div className="refusal pending">
              The compiled library is not in this build, so the specimens are still.
            </div>
          ) : (
            rows.map((row) => (
              <article className={"verdict " + (row.ok ? "yes" : "no")} key={row.edition}>
                <div className="verdict-head">
                  <span className="v-edition">{row.edition}</span>
                  <span className={"v-stamp " + (row.ok ? "yes" : "no")}>
                    {row.ok ? "accepted" : "refused"}
                  </span>
                </div>
                {row.ok ? (
                  <p className="v-note">the document reads in full at this grammar</p>
                ) : (
                  <>
                    <p className="v-where">
                      line {row.line} · column {row.column}
                    </p>
                    <p className="v-msg">
                      {(row.message ?? "").replace(/^\d+:\d+:\s*/, "")}
                    </p>
                  </>
                )}
              </article>
            ))
          )}
        </div>
      </div>
    </>
  );
}

/* ---------- the one line that moved -------------------------------------- */

const DOCUMENTS = [
  {
    id: "garden",
    label: "a garden",
    src: `# a garden, planted 1979
name = "garden"  # the one by the gate
beds = 4

[soil]
kind = "loam"
ph = 6.5
`,
  },
  {
    id: "manifest",
    label: "a moon.mod",
    src: `# the module
name = "moonbitstack/example"
version = "0.1.0"

[imports]
"moonbitstack/moondate" = "0.1.6"
`,
  },
];

type Kept = {
  ok: boolean;
  paths?: { path: string[]; line: number }[];
  before?: string;
  after?: string;
  moved?: boolean | null;
  message?: string;
  line?: number;
  column?: number;
};

function changedLines(before: string, after: string): number[] {
  const a = before.split("\n");
  const b = after.split("\n");
  const out: number[] = [];
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    if (a[i] !== b[i]) out.push(i);
  }
  return out;
}

function KeptSpecimen() {
  const engine = useEngine();
  const [active, setActive] = useState(DOCUMENTS[0].id);
  const [src, setSrc] = useState(DOCUMENTS[0].src);
  const [path, setPath] = useState<string[]>(["beds"]);
  const [value, setValue] = useState("6");

  const answer = useMemo<Kept | null>(() => {
    if (!engine) return null;
    try {
      return JSON.parse(engine.kept(src, JSON.stringify(path), value)) as Kept;
    } catch {
      return null;
    }
  }, [engine, src, path, value]);

  const paths = answer?.ok ? answer.paths ?? [] : [];
  const before = answer?.before ?? "";
  const after = answer?.after ?? "";
  const moved = changedLines(before, after);

  function choose(doc: (typeof DOCUMENTS)[number]) {
    setActive(doc.id);
    setSrc(doc.src);
    setPath(doc.id === "garden" ? ["beds"] : ["version"]);
    setValue(doc.id === "garden" ? "6" : '"0.2.0"');
  }

  return (
    <>
      <div className="spec-chips">
        {DOCUMENTS.map((d) => (
          <button
            key={d.id}
            className="chip"
            type="button"
            aria-pressed={active === d.id}
            onClick={() => choose(d)}
          >
            {d.label}
          </button>
        ))}
      </div>

      <div className="kept-book">
        <div className="kept-controls">
          <span className="pg-label">
            <i>The key</i>
          </span>
          <div className="key-chips">
            {paths.map((p) => {
              const name = p.path.join(".");
              return (
                <button
                  key={name}
                  className="chip"
                  type="button"
                  aria-pressed={JSON.stringify(path) === JSON.stringify(p.path)}
                  onClick={() => setPath(p.path)}
                >
                  {name}
                </button>
              );
            })}
          </div>
          <label className="value-field">
            <span>new value</span>
            <input
              type="text"
              value={value}
              onChange={(e) => setValue(e.target.value)}
              spellCheck={false}
              aria-label="The new TOML value"
            />
          </label>
          <p className="marginalia">
            {answer === null
              ? "The compiled library is not in this build."
              : !answer.ok
                ? `line ${answer.line}, column ${answer.column} — ${(answer.message ?? "").replace(/^\d+:\d+:\s*/, "")}`
                : answer.moved === null
                  ? "That path names nothing; the document is left as it was."
                  : answer.moved === false
                    ? "The value is the one already there, so nothing moved."
                    : `${moved.length} line moved; ${before.split("\n").length - 1 - moved.length} lines are the source byte for byte.`}
          </p>
        </div>

        <div className="kept-pages">
          <section className="page">
            <div className="page-head">
              <span className="pg-label">
                <i>Before</i>
              </span>
              <span className="pg-label">as it was written</span>
            </div>
            <pre className="diff scroll">
              {before.split("\n").map((line, i) => (
                <div className="dline" key={i}>
                  <span className="dn">{i + 1}</span>
                  <span className="dt">{line}</span>
                </div>
              ))}
            </pre>
          </section>
          <section className="page">
            <div className="page-head">
              <span className="pg-label">
                <i>After</i>
              </span>
              <span className="pg-label">rendered by moontoml</span>
            </div>
            <pre className="diff scroll">
              {after.split("\n").map((line, i) => (
                <div className={"dline" + (moved.includes(i) ? " hit" : "")} key={i}>
                  <span className="dn">{i + 1}</span>
                  <span className="dt">{line}</span>
                </div>
              ))}
            </pre>
          </section>
        </div>
      </div>
      <p className="kept-note">
        <Inline text="The path, the value and the document all go to the compiled library: `decode_doc` opens the page, `set` changes one value, and `render` writes it back. The two pages above are its answers, not a copy of the source." />
      </p>
    </>
  );
}

/* ---------- the ten refusals --------------------------------------------- */

type Specimen = {
  kind: string;
  what: string;
  src?: string;
  edition: number;
  bytes?: number[];
  display: string;
};

const FAULT_SPECIMENS: Specimen[] = [
  {
    kind: "Unexpected",
    what: "a character that cannot begin what was expected",
    src: "a..b = 1\n",
    edition: 10,
    display: "a..b = 1",
  },
  {
    kind: "Truncated",
    what: "the document ends mid-thing",
    src: 'a = "unterminated\n',
    edition: 10,
    display: 'a = "unterminated',
  },
  {
    kind: "BadEscape",
    what: "a backslash escape the format does not define",
    src: 'a = "\\q"\n',
    edition: 10,
    display: 'a = "\\q"',
  },
  {
    kind: "BadNumber",
    what: "a number the format cannot spell",
    src: "a = @\n",
    edition: 10,
    display: "a = @",
  },
  {
    kind: "BadDate",
    what: "a date the calendar does not have",
    src: "a = 1979-02-30\n",
    edition: 10,
    display: "a = 1979-02-30",
  },
  {
    kind: "Redefined",
    what: "a key or table defined twice",
    src: "a = 1\na = 2\n",
    edition: 10,
    display: "a = 1\na = 2",
  },
  {
    kind: "MixedArray",
    what: "a second kind in an array, before 1.0.0",
    src: 'a = [1, "two"]\n',
    edition: 5,
    display: 'a = [1, "two"]   (read at 0.5)',
  },
  {
    kind: "Trailing",
    what: "content after a value where none may follow",
    src: "a = 1 b = 2\n",
    edition: 10,
    display: "a = 1 b = 2",
  },
  {
    kind: "TooDeep",
    what: "nesting past the flavor's limit of 500",
    src: "a = " + "[".repeat(600) + "1" + "]".repeat(600) + "\n",
    edition: 10,
    display: "a = [ [ [ … 600 deep … ] ] ]",
  },
  {
    kind: "BadUtf8",
    what: "bytes that are not UTF-8",
    bytes: [0xff, 0xfe],
    edition: 10,
    display: "FF FE   (bytes, not text)",
  },
];

type Fault = {
  ok: boolean;
  kind?: string;
  line?: number;
  column?: number;
  message?: string;
};

function FaultShelf() {
  const engine = useEngine();
  const [active, setActive] = useState(FAULT_SPECIMENS[0].kind);
  const specimen = FAULT_SPECIMENS.find((s) => s.kind === active) ?? FAULT_SPECIMENS[0];

  const answer = useMemo<Fault | null>(() => {
    if (!engine) return null;
    try {
      const text = specimen.bytes
        ? engine.fault_bytes(new Uint8Array(specimen.bytes), specimen.edition)
        : engine.fault(specimen.src ?? "", specimen.edition);
      return JSON.parse(text) as Fault;
    } catch {
      return null;
    }
  }, [engine, specimen]);

  return (
    <>
      <div className="shelf">
        {FAULT_SPECIMENS.map((s) => (
          <button
            key={s.kind}
            className={"specimen" + (active === s.kind ? " on" : "")}
            type="button"
            aria-pressed={active === s.kind}
            onClick={() => setActive(s.kind)}
          >
            <span className="s-no">{String(FAULT_SPECIMENS.indexOf(s) + 1).padStart(2, "0")}</span>
            <b>{s.kind}</b>
            <span className="s-what">{s.what}</span>
            <code className="s-src">{s.display}</code>
          </button>
        ))}
      </div>

      <div className="fault-readout">
        {answer === null ? (
          <div className="refusal pending">
            The compiled library is not in this build, so the shelf is still.
          </div>
        ) : answer.ok ? (
          <div className="refusal pending">This specimen was accepted at that edition.</div>
        ) : (
          <div className="refusal fault-card">
            <span className="stamp">refused</span>
            <div className="f-kind">{answer.kind}</div>
            <div className="where">
              line {answer.line} · column {answer.column}
            </div>
            <p className="msg">
              {(answer.message ?? "").replace(/^\d+:\d+:\s*/, "")}
            </p>
            <p className="f-foot">
              {specimen.bytes
                ? "read by decode_bytes, over the bytes a file is made of"
                : `read by decode at edition ${specimen.edition === 5 ? "0.5" : "1.0.0"}`}
            </p>
          </div>
        )}
      </div>
    </>
  );
}

/* ---------- the page ------------------------------------------------------ */

export function Specimens() {
  return (
    <>
      <Header page="specimens" />
      <main className="wrap">
        <section className="hero specimens-hero">
          <div>
            <p className="eyebrow">The specimen book · run by the compiled library</p>
            <h1>
              Three questions,
              <br />answered by the <span className="accent">reader itself</span>.
            </h1>
            <p className="lede">
              Which grammar reads this line? Which line moves when one value changes? Which fault
              does a broken document raise? Every answer on this page is a call into moontoml,
              compiled to JavaScript — nothing here is written out in advance.
            </p>
          </div>
          <aside className="slip" aria-label="How to read this page">
            <span className="no">Catalogue No. 2</span>
            <div className="pkg">Specimens</div>
            <dl>
              <div className="row">
                <dt>Grammars</dt>
                <dd>4</dd>
              </div>
              <div className="row">
                <dt>Readings</dt>
                <dd>tree · kinds · document</dd>
              </div>
              <div className="row">
                <dt>Refusals</dt>
                <dd>10</dd>
              </div>
              <div className="row">
                <dt>Engine</dt>
                <dd>compiled from src/</dd>
              </div>
            </dl>
            <div className="barcode" aria-hidden="true">
              {Array.from({ length: 30 }).map((_, i) => (
                <i key={i} />
              ))}
            </div>
          </aside>
        </section>

        <section className="section" id="grammars">
          <SecHead
            num="§ 1"
            title="A line under four grammars"
            intro={
              <Inline text="TOML editions differ by real rules. Pick a specimen, or write your own line; the four verdicts are four real reads, one at each `Flavor` the library defines." />
            }
          />
          <GrammarSpecimens />
        </section>

        <section className="section" id="moved">
          <SecHead
            num="§ 2"
            title="The one line that moved"
            intro={
              <Inline text="A tree forgets the page it came from. `decode_doc` keeps it. Choose a key, write a value as you would in the file, and compare the two pages the library answers with." />
            }
          />
          <KeptSpecimen />
        </section>

        <section className="section" id="shelf">
          <SecHead
            num="§ 3"
            title="Ten ways a document is refused"
            intro={
              <Inline text="Each specimen breaks one rule. The variant, the place and the message are what `Refused` raised when the compiled library read it." />
            }
          />
          <FaultShelf />
        </section>
      </main>
      <Footer />
    </>
  );
}
