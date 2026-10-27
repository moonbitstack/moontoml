import { useEffect, useState } from "react";
import { CodeBlock, Footer, Header, Inline, Output } from "./util";

type Block =
  | { k: "p"; text: string }
  | { k: "code"; code: string; label?: string }
  | { k: "out"; text: string }
  | { k: "table"; head: string[]; rows: string[][] }
  | { k: "list"; items: string[] };

type Chapter = { id: string; num: string; title: string; blocks: Block[] };

const CHAPTERS: Chapter[] = [
  {
    id: "install",
    num: "00",
    title: "Install and first read",
    blocks: [
      { k: "p", text: "Add the package to a project:" },
      { k: "code", label: "shell", code: "moon add moonbitstack/moontoml" },
      {
        k: "p",
        text: "Then read a document. `loads` takes a `StringView`; `[:]` borrows a `String` as one.",
      },
      {
        k: "code",
        code: String.raw`let doc = @moontoml.loads("title = \"notes\"\n"[:])
println(doc.stringify())`,
      },
      { k: "out", text: `{"title":"notes"}` },
      {
        k: "p",
        text: "A document is always a table, so the result is a `Json` object. `stringify` is the compact form. Every later step works on that tree.",
      },
    ],
  },
  {
    id: "types",
    num: "01",
    title: "What a document becomes",
    blocks: [
      { k: "p", text: "TOML has seven kinds of value. Each becomes a `Json` node:" },
      {
        k: "table",
        head: ["TOML", "Json"],
        rows: [
          ["string", "String"],
          ["integer", "Number"],
          ["float", "Number"],
          ["boolean", "True or False"],
          ["date-time", "String (RFC 3339 text)"],
          ["array", "Array"],
          ["table", "Object"],
        ],
      },
      { k: "p", text: "A document with one of each:" },
      {
        k: "code",
        code: String.raw`let src =
  #|s = "text"
  #|i = 42
  #|f = 1.5
  #|b = true
  #|d = 1979-05-27T07:32:00Z
  #|a = [1, 2]
  #|t = { x = 1 }
let doc = @moontoml.loads(src[:])
println(doc.stringify())`,
      },
      {
        k: "out",
        text: `{"s":"text","i":42,"f":1.5,"b":true,"d":"1979-05-27T07:32:00Z","a":[1,2],"t":{"x":1}}`,
      },
      {
        k: "p",
        text: "A date comes out as the RFC 3339 form, not the text it went in as: `2026-03-01 09:30:00Z` becomes `2026-03-01T09:30:00Z`. A date the calendar does not have is refused.",
      },
    ],
  },
  {
    id: "reading",
    num: "02",
    title: "Reading values",
    blocks: [
      {
        k: "p",
        text: "A `Json` is read by shape. `Object` is a table, `String` a string, and so on; a missing key is `None`.",
      },
      {
        k: "code",
        code: String.raw`let src =
  #|name = "garden"
  #|beds = 4
  #|
  #|[soil]
  #|kind = "loam"
  #|ph = 6.5
let doc = @moontoml.loads(src[:])
guard doc is Object(root) else { abort("not a table") }
let name = match root.get("name") {
  Some(String(s)) => s
  _ => "?"
}
let beds = match root.get("beds") {
  Some(Number(n, ..)) => n.to_int()
  _ => 0
}
let ph = match root.get("soil") {
  Some(Object(soil)) =>
    match soil.get("ph") {
      Some(Number(n, ..)) => n
      _ => 0.0
    }
  _ => 0.0
}
println("\{name}: \{beds} beds, ph \{ph}")`,
      },
      { k: "out", text: "garden: 4 beds, ph 6.5" },
      {
        k: "p",
        text: "The patterns are exhaustive. `Number(n, ..)` ignores the optional source text; `n` is the `Double`.",
      },
    ],
  },
  {
    id: "writing",
    num: "03",
    title: "Writing it back",
    blocks: [
      {
        k: "p",
        text: "`dumps` writes a tree back as TOML. Scalars stay at the level they are on; tables go under their own headers.",
      },
      {
        k: "code",
        code: String.raw`let doc = @moontoml.loads("b = 1\na = 2\n"[:])
println(@moontoml.dumps(doc))`,
      },
      { k: "out", text: "b = 1\na = 2" },
      { k: "p", text: "The order is the tree's own. `sort=true` orders keys by name:" },
      { k: "code", code: String.raw`println(@moontoml.dumps(doc, sort=true))` },
      { k: "out", text: "a = 2\nb = 1" },
      {
        k: "p",
        text: "A document read and written again keeps its values, not its layout. TOML can spell the same tree several ways; this writer picks one.",
      },
    ],
  },
  {
    id: "bytes",
    num: "04",
    title: "Bytes and the byte-order mark",
    blocks: [
      {
        k: "p",
        text: "`load` takes bytes and `dump` returns them. Both hold the same document as `loads` and `dumps`.",
      },
      {
        k: "code",
        code: String.raw`let doc = @moontoml.loads("a = 1\n"[:])
let bytes = @moontoml.dump(doc)
println(bytes.length().to_string() + " bytes")
println(@moontoml.load(bytes).stringify())`,
      },
      { k: "out", text: '6 bytes\n{"a":1}' },
      {
        k: "p",
        text: "A byte-order mark is skipped by default. `bom=false` holds the file to the specification and refuses it:",
      },
      {
        k: "code",
        code: String.raw`let bommed = b"\xef\xbb\xbfa = 1\n"
let where = try {
  let _ = @moontoml.load(bommed, bom=false)
  "read"
} catch {
  e => "\{e.at().line}:\{e.at().column}"
}
println(where)`,
      },
      { k: "out", text: "1:1" },
    ],
  },
  {
    id: "refusals",
    num: "05",
    title: "When it refuses",
    blocks: [
      {
        k: "p",
        text: "A refused document raises `Refused`. The error carries an `At`: the offset, the line and the column.",
      },
      {
        k: "code",
        code: String.raw`let outcome = try {
  let _ = @moontoml.loads("a = 1\nb = @\n"[:])
  "read"
} catch {
  e => e.to_string()
}
println(outcome)`,
      },
      { k: "out", text: "2:5: not a number" },
      {
        k: "p",
        text: "The text is the position and the fault. `at()` gives the position on its own: `e.at().line` is 2 and `e.at().column` is 5.",
      },
      {
        k: "p",
        text: "There are nine kinds, and each carries a position:",
      },
      {
        k: "list",
        items: [
          "`Unexpected` — a character that cannot begin what was expected",
          "`Truncated` — the document ends mid-thing",
          "`BadEscape` — a backslash escape TOML does not define",
          "`BadNumber` — a number TOML cannot spell",
          "`BadDate` — a date or time the calendar does not have",
          "`Redefined` — a key or table defined twice",
          "`Trailing` — content after a value where only a comment or newline may follow",
          "`TooDeep` — nesting past the flavor's limit",
          "`BadUtf8` — bytes that are not UTF-8",
        ],
      },
      {
        k: "p",
        text: "Redefinition is the rule that makes a TOML file safe to append to: a key may be defined once, and so may a table. A second definition is an error, not a value that wins.",
      },
    ],
  },
  {
    id: "limits",
    num: "06",
    title: "Limits",
    blocks: [
      {
        k: "p",
        text: "`Flavor` holds the one limit a reader has: how deep a document may nest. The preset is `strict`, depth 500.",
      },
      {
        k: "code",
        code: String.raw`let deep = StringBuilder()
deep.write_string("a = ")
for i = 0; i < 12; i = i + 1 {
  deep.write_char('[')
}
for i = 0; i < 12; i = i + 1 {
  deep.write_char(']')
}
let outcome = try {
  let _ = @moontoml.loads(deep.to_string()[:], flavor=@moontoml.Flavor::new(depth=8))
  "read"
} catch {
  e => e.to_string()
}
println(outcome)`,
      },
      { k: "out", text: "1:14: nested too deep" },
      {
        k: "p",
        text: "`Flavor::new(depth=…)` builds another; `{ ..strict, depth: 64 }` updates one in place. There is no knob for a repeated key: §1 of the specification makes redefinition an error, so offering to ignore it would be offering to read something that is not a TOML document.",
      },
    ],
  },
];

function Blocks({ blocks }: { blocks: Block[] }) {
  return (
    <>
      {blocks.map((b, i) => {
        if (b.k === "p")
          return (
            <p key={i}>
              <Inline text={b.text} />
            </p>
          );
        if (b.k === "code") return <CodeBlock key={i} code={b.code} label={b.label} />;
        if (b.k === "out") return <Output key={i} text={b.text} />;
        if (b.k === "list")
          return (
            <ul key={i}>
              {b.items.map((it, j) => (
                <li key={j}>
                  <Inline text={it} />
                </li>
              ))}
            </ul>
          );
        return (
          <table className="spec" key={i}>
            <thead>
              <tr>
                {b.head.map((h) => (
                  <th key={h}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {b.rows.map((row, r) => (
                <tr key={r}>
                  {row.map((cell, c) => (
                    <td key={c}>{c === 0 ? <code>{cell}</code> : cell}</td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        );
      })}
    </>
  );
}

export function Guide() {
  const [active, setActive] = useState(CHAPTERS[0].id);

  useEffect(() => {
    const marks = CHAPTERS.map((c) => document.getElementById(c.id)).filter(
      (el): el is HTMLElement => Boolean(el),
    );
    const obs = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((e) => e.isIntersecting)
          .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);
        if (visible[0]) setActive(visible[0].target.id);
      },
      { rootMargin: "-20% 0px -70% 0px", threshold: 0 },
    );
    marks.forEach((el) => obs.observe(el));
    return () => obs.disconnect();
  }, []);

  return (
    <>
      <Header page="guide" />
      <div className="doc">
        <aside className="toc" aria-label="Contents">
          <div className="toc-title">Contents</div>
          {CHAPTERS.map((c) => (
            <a key={c.id} href={`#${c.id}`} className={active === c.id ? "active" : undefined}>
              <i>{c.num}</i>
              {c.title}
            </a>
          ))}
        </aside>
        <article className="reference">
          <header className="guide-head">
            <p className="eyebrow">The guide</p>
            <h1>A whole document, one page at a time.</h1>
            <p className="lede">
              Seven short chapters. Each one compiles and runs; the output under it is from a real
              build, not a sketch.
            </p>
          </header>
          {CHAPTERS.map((c) => (
            <section className="chapter" id={c.id} key={c.id}>
              <h2>
                <span className="k">§ {c.num}</span>
                {c.title}
              </h2>
              <Blocks blocks={c.blocks} />
            </section>
          ))}
        </article>
      </div>
      <Footer />
    </>
  );
}
