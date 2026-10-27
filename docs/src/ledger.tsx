import { useEffect, useMemo, useRef, useState } from "react";

declare global {
  interface Window {
    moontoml?: { inspect(src: string, sort: boolean): string };
  }
}

type Result =
  | { ok: true; tree: unknown; copy: string }
  | { ok: false; line: number; column: number; message: string };

const SAMPLES = [
  {
    id: "manifest",
    label: "A manifest",
    src: `# a field notebook
title = "field notes"
started = 2026-03-01 09:30:00Z
tags = [ "garden", "soil" ]

[author]
name = "A. Ledger"
place = "北京"

[[entry]]
on = 2026-03-02
note = "霜降"
`,
  },
  {
    id: "catalogue",
    label: "A catalogue",
    src: `port = 0x1F90
ratio = 1.5e3
open = true
limits.timeout = 30
point = { x = 1, y = 2 }
mask = 0b11010110
`,
  },
  {
    id: "broken",
    label: "Break a rule",
    src: `title = "notes"
title = "again"

[author]
name = "A."
`,
  },
];

/* ---------- a light highlighter for the manuscript ---------------------- */

type Tok = { t: string; c?: string };

function outside(line: string, target: string): number {
  let quote: string | null = null;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (quote) {
      if (c === "\\" && quote === '"') {
        i++;
        continue;
      }
      if (c === quote) quote = null;
      continue;
    }
    if (c === '"' || c === "'") {
      quote = c;
      continue;
    }
    if (c === target) return i;
  }
  return -1;
}

function valueTokens(s: string): Tok[] {
  const out: Tok[] = [];
  let buf = "";
  let i = 0;
  while (i < s.length) {
    const ch = s[i];
    if (ch === '"' || ch === "'") {
      if (buf) {
        out.push({ t: buf });
        buf = "";
      }
      const quote = ch;
      let j = i + 1;
      let str = ch;
      while (j < s.length) {
        const c = s[j];
        str += c;
        if (c === "\\" && quote === '"' && j + 1 < s.length) {
          str += s[j + 1];
          j += 2;
          continue;
        }
        if (c === quote) {
          j++;
          break;
        }
        j++;
      }
      out.push({ t: str, c: "tok-str" });
      i = j;
      continue;
    }
    buf += ch;
    i++;
  }
  if (buf) out.push({ t: buf });
  return out;
}

function lineTokens(line: string): Tok[] {
  if (line.trimStart().startsWith("#")) return [{ t: line, c: "tok-com" }];
  const hash = outside(line, "#");
  const code = hash >= 0 ? line.slice(0, hash) : line;
  const comment = hash >= 0 ? line.slice(hash) : "";
  const out: Tok[] = [];
  if (line.trimStart().startsWith("[")) {
    out.push({ t: code, c: "tok-hdr" });
  } else {
    const eq = outside(code, "=");
    if (eq >= 0) {
      out.push({ t: code.slice(0, eq), c: "tok-key" });
      out.push({ t: "=", c: "tok-eq" });
      out.push(...valueTokens(code.slice(eq + 1)));
    } else if (code) {
      out.push({ t: code });
    }
  }
  if (comment) out.push({ t: comment, c: "tok-com" });
  return out;
}

/* ---------- the tree ---------------------------------------------------- */

function kindOf(v: unknown): string {
  if (v === null) return "null";
  if (Array.isArray(v)) return "array";
  if (typeof v === "number") return "num";
  if (typeof v === "boolean") return "bool";
  if (typeof v === "string") {
    return /^\d{4}-\d{2}-\d{2}/.test(v) || /^\d{2}:\d{2}:\d{2}/.test(v) ? "date" : "str";
  }
  return "table";
}

function show(v: unknown): string {
  if (v === null) return "null";
  if (typeof v === "string") {
    return /^\d{4}-\d{2}-\d{2}/.test(v) || /^\d{2}:\d{2}:\d{2}/.test(v) ? v : JSON.stringify(v);
  }
  return String(v);
}

function Node({
  name,
  value,
  depth,
}: {
  name: string | null;
  value: unknown;
  depth: number;
}) {
  const pad = { paddingLeft: depth * 13 };
  if (Array.isArray(value)) {
    return (
      <>
        <div className="trow" style={pad}>
          {name !== null ? <span className="tkey">{name}</span> : null}
          <span className="tbranch">
            [ {value.length} ]
          </span>
          <span className="ttype">array</span>
        </div>
        {value.map((v, i) => (
          <Node key={i} name={`[${i}]`} value={v} depth={depth + 1} />
        ))}
      </>
    );
  }
  if (value !== null && typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>);
    return (
      <>
        {name !== null ? (
          <div className="trow" style={pad}>
            <span className="tkey">{name}</span>
            <span className="tbranch">{"{ "}{entries.length}{" }"}</span>
            <span className="ttype">table</span>
          </div>
        ) : null}
        {entries.map(([k, v]) => (
          <Node key={k} name={k} value={v} depth={name === null ? depth : depth + 1} />
        ))}
      </>
    );
  }
  return (
    <div className="trow" style={pad}>
      <span className="tkey">{name}</span>
      <span className={"tval " + kindOf(value)}>{show(value)}</span>
      <span className="ttype">{kindOf(value)}</span>
    </div>
  );
}

/* ---------- the demo ---------------------------------------------------- */

export function LedgerDemo() {
  const wanted =
    typeof location === "undefined" ? null : new URLSearchParams(location.search).get("sample");
  const start = SAMPLES.find((s) => s.id === wanted) ?? SAMPLES[0];

  const [engine, setEngine] = useState<Window["moontoml"]>(() =>
    typeof window === "undefined" ? undefined : window.moontoml,
  );
  const [src, setSrc] = useState(start.src);
  const [active, setActive] = useState(start.id);
  const [sort, setSort] = useState(false);

  const taRef = useRef<HTMLTextAreaElement>(null);
  const backRef = useRef<HTMLPreElement>(null);
  const gutRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (engine) return;
    const ready = () => setEngine(window.moontoml);
    addEventListener("moontoml:ready", ready);
    return () => removeEventListener("moontoml:ready", ready);
  }, [engine]);

  const result = useMemo<Result | null>(() => {
    if (!engine) return null;
    try {
      return JSON.parse(engine.inspect(src, sort)) as Result;
    } catch {
      return { ok: false, line: 0, column: 0, message: "the engine did not answer" };
    }
  }, [engine, src, sort]);

  const lines = src.split("\n");
  const errLine = result && !result.ok ? result.line : 0;

  function sync() {
    const ta = taRef.current;
    if (!ta) return;
    if (backRef.current) {
      backRef.current.scrollTop = ta.scrollTop;
      backRef.current.scrollLeft = ta.scrollLeft;
    }
    if (gutRef.current) {
      gutRef.current.style.transform = `translateY(${-ta.scrollTop}px)`;
    }
  }

  useEffect(sync, [src, result]);

  function choose(sample: (typeof SAMPLES)[number]) {
    setSrc(sample.src);
    setActive(sample.id);
    requestAnimationFrame(() => {
      if (taRef.current) taRef.current.scrollTop = 0;
      sync();
    });
  }

  function edit(next: string) {
    setActive("custom");
    setSrc(next);
    requestAnimationFrame(sync);
  }

  const message = result && !result.ok ? result.message.replace(/^\d+:\d+:\s*/, "") : "";

  return (
    <>
      <div className="ledger-tools">
        <div className="samples">
          {SAMPLES.map((s) => (
            <button
              key={s.id}
              className="chip"
              type="button"
              aria-pressed={active === s.id}
              onClick={() => choose(s)}
            >
              {s.label}
            </button>
          ))}
        </div>
        <label className="switch">
          <input type="checkbox" checked={sort} onChange={(e) => setSort(e.target.checked)} />
          sort keys
        </label>
      </div>

      <div className="ledger">
        <section className="page">
          <div className="page-head">
            <span className="pg-label">
              <i>The manuscript</i>
            </span>
            <span className="pg-label">editable</span>
          </div>

          <div className="editor">
            <div className="gutter">
              <div className="gutter-inner" ref={gutRef}>
                {lines.map((_, i) => (
                  <div key={i} className={"gl" + (i + 1 === errLine ? " hit" : "")}>
                    {i + 1}
                  </div>
                ))}
              </div>
            </div>
            <div className="paper">
              <pre className="backdrop" ref={backRef} aria-hidden="true">
                {lines.map((line, i) => (
                  <div key={i} className={"ln" + (i + 1 === errLine ? " hit" : "")}>
                    {lineTokens(line).map((tok, j) => (
                      <span key={j} className={tok.c}>
                        {tok.t}
                      </span>
                    ))}
                  </div>
                ))}
              </pre>
              <textarea
                className="manuscript"
                ref={taRef}
                value={src}
                onChange={(e) => edit(e.target.value)}
                onScroll={sync}
                spellCheck={false}
                wrap="off"
                aria-label="TOML manuscript"
              />
            </div>
          </div>

          {result && !result.ok ? (
            <p className="marginalia">
              line {result.line}, column {result.column} — {message}
            </p>
          ) : (
            <p className="marginalia">the tree and the copy come from the compiled library</p>
          )}
        </section>

        <section className="page">
          <div className="page-head">
            <span className="pg-label">
              <i>The posting</i>
            </span>
            <span className="pg-label">read by moontoml</span>
          </div>

          <div className="panels">
            {result === null ? (
              <div className="refusal pending">
                The compiled library is not in this build, so the ledger is still.
              </div>
            ) : result.ok ? (
              <>
                <div className="panel">
                  <div className="panel-label">
                    <span>the tree</span>
                    <b>Json</b>
                  </div>
                  <div className="tree">
                    <Node name={null} value={result.tree} depth={0} />
                  </div>
                </div>
                <div className="panel copybox">
                  <div className="panel-label">
                    <span>the fair copy</span>
                    <b>dumps</b>
                  </div>
                  <pre>{result.copy}</pre>
                </div>
              </>
            ) : (
              <div className="refusal">
                <span className="stamp">refused</span>
                <div className="where">
                  line {result.line} · column {result.column}
                </div>
                <p className="msg">{message}</p>
              </div>
            )}
          </div>
        </section>
      </div>
    </>
  );
}
