import { useEffect, useState, type ReactNode } from "react";

/* ---------- theme ------------------------------------------------------- */

const THEME_KEY = "moontoml-theme";

function initialTheme(): "light" | "dark" {
  if (typeof document === "undefined") return "light";
  const set = document.documentElement.dataset.theme;
  return set === "dark" ? "dark" : "light";
}

export function useTheme() {
  const [theme, setTheme] = useState<"light" | "dark">(initialTheme);
  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    try {
      localStorage.setItem(THEME_KEY, theme);
    } catch {
      /* private mode */
    }
  }, [theme]);
  return [theme, () => setTheme((t) => (t === "dark" ? "light" : "dark"))] as const;
}

/* ---------- icons ------------------------------------------------------- */

export function GithubIcon() {
  return (
    <svg viewBox="0 0 16 16" aria-hidden="true">
      <path
        fill="currentColor"
        d="M8 0C3.58 0 0 3.58 0 8a8 8 0 0 0 5.47 7.59c.4.07.55-.17.55-.38v-1.33c-2.23.48-2.7-1.07-2.7-1.07-.36-.92-.89-1.17-.89-1.17-.73-.5.06-.49.06-.49.8.06 1.23.83 1.23.83.72 1.22 1.88.87 2.34.66.07-.52.28-.87.5-1.07-1.78-.2-3.65-.89-3.65-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.6 7.6 0 0 1 4 0c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48v2.2c0 .21.15.46.55.38A8 8 0 0 0 16 8c0-4.42-3.58-8-8-8Z"
      />
    </svg>
  );
}

/* ---------- header / footer -------------------------------------------- */

export type Page = "home" | "guide" | "api";

export function Header({ page }: { page: Page }) {
  const [, toggle] = useTheme();
  return (
    <header className="bar">
      <div className="bar-in">
        <a className="brand" href="./">
          <span className="brand-name">
            moon<b>toml</b>
          </span>
          <span className="brand-sub">TOML for MoonBit</span>
        </a>
        <nav className="nav">
          <a href="./" aria-current={page === "home" ? "page" : undefined}>
            Home
          </a>
          <a href="guide.html" aria-current={page === "guide" ? "page" : undefined}>
            Guide
          </a>
          <a href="api.html" aria-current={page === "api" ? "page" : undefined}>
            API
          </a>
        </nav>
        <div className="bar-right">
          <button className="theme" type="button" onClick={toggle} aria-label="Switch theme">
            <span className="t-full">Light / dark</span>
            <span className="t-short">Theme</span>
          </button>
          <a
            className="gh"
            href="https://github.com/moonbitstack/moontoml"
            aria-label="Source on GitHub"
          >
            <GithubIcon />
          </a>
        </div>
      </div>
    </header>
  );
}

export function Footer() {
  return (
    <footer className="foot">
      <div className="foot-in">
        <span>moontoml · TOML 1.0.0 · Apache-2.0</span>
        <a href="https://mooncakes.io/docs/moonbitstack/moontoml">mooncakes</a>
        <span className="spread" />
        <a href="https://github.com/moonbitstack/moontoml">github.com/moonbitstack/moontoml</a>
      </div>
    </footer>
  );
}

/* ---------- inline prose ------------------------------------------------ */

export function Inline({ text }: { text: string }) {
  const parts = text.split(/(`[^`]+`|\*\*[^*]+\*\*)/g);
  return (
    <>
      {parts.map((p, i) => {
        if (p.startsWith("`") && p.endsWith("`")) return <code key={i}>{p.slice(1, -1)}</code>;
        if (p.startsWith("**") && p.endsWith("**")) return <strong key={i}>{p.slice(2, -2)}</strong>;
        return <span key={i}>{p}</span>;
      })}
    </>
  );
}

/* ---------- code and output -------------------------------------------- */

export function CodeBlock({
  code,
  label = "moonbit",
}: {
  code: string;
  label?: string;
}) {
  const [copied, setCopied] = useState(false);
  async function copy() {
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      setTimeout(() => setCopied(false), 1400);
    } catch {
      /* clipboard blocked */
    }
  }
  return (
    <figure className="code">
      <figcaption>
        <span>{label}</span>
        <button type="button" onClick={copy}>
          {copied ? "copied" : "copy"}
        </button>
      </figcaption>
      <pre>
        <code>{code}</code>
      </pre>
    </figure>
  );
}

export function Output({ text, label = "output" }: { text: string; label?: string }) {
  return (
    <figure className="output">
      <figcaption>
        <span>{label}</span>
        <span>real run</span>
      </figcaption>
      <pre>
        <code>{text}</code>
      </pre>
    </figure>
  );
}

/* ---------- section heading -------------------------------------------- */

export function SecHead({
  num,
  title,
  intro,
}: {
  num: string;
  title: string;
  intro?: ReactNode;
}) {
  return (
    <>
      <div className="sec-head">
        <span className="sec-num">{num}</span>
        <h2>{title}</h2>
      </div>
      {intro ? <p className="sec-intro">{intro}</p> : null}
    </>
  );
}
