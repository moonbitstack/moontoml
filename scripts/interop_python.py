"""Cross-check the reader and the writer against two independent implementations.

The official suite says what each document denotes. This script asks two mature
Python implementations to go both ways with the library over those same 205
documents:

  * CPython's `tomllib` (the standard library reader) reads what our writer
    emits, and reads the same documents our reader reads.
  * `tomli_w` (the companion writer) emits TOML that our reader must read back
    to the tree the suite expects.

Nothing is skipped. A value of a kind the two implementations spell differently
(a float's digits, `Z` against `+00:00`, a fraction's trailing zeroes) is
compared after parsing, not as text.

Usage, from the repository root, after
`moon build --target js --release src/conformance`:

    python3 scripts/interop_python.py

Requires Python 3.11 or newer and `tomli_w`; CI pins the version.
"""

import base64
import datetime
import json
import math
import pathlib
import subprocess
import sys

try:
    import tomllib
    import tomli_w
except ImportError as exc:
    raise SystemExit(f"the interop check needs Python 3.11+ and tomli-w: {exc}")

from gen_vectors import corpora

ROOT = pathlib.Path(__file__).resolve().parent.parent
DRIVER = ROOT / "scripts" / "interop_driver.mjs"


def float_of(text: str) -> float:
    return float(text)


def to_python(node):
    """A toml-test tree as Python values a writer can put back on the wire."""
    if isinstance(node, list):
        return [to_python(item) for item in node]
    if isinstance(node, dict) and set(node) == {"type", "value"}:
        kind, text = node["type"], node["value"]
        if kind == "string":
            return text
        if kind == "integer":
            return int(text)
        if kind == "float":
            return float_of(text)
        if kind == "bool":
            return text == "true"
        if kind == "datetime":
            return datetime.datetime.fromisoformat(text.replace("Z", "+00:00"))
        if kind == "datetime-local":
            return datetime.datetime.fromisoformat(text)
        if kind == "date-local":
            return datetime.date.fromisoformat(text)
        if kind == "time-local":
            return datetime.time.fromisoformat(text)
        raise SystemExit(f"unknown kind in a suite tree: {kind}")
    if isinstance(node, dict):
        return {name: to_python(held) for name, held in node.items()}
    raise SystemExit(f"unknown node in a suite tree: {node!r}")


def from_python(value):
    """The same tree, as the library writes it for `toml-test`."""
    if isinstance(value, bool):
        return {"type": "bool", "value": "true" if value else "false"}
    if isinstance(value, int):
        return {"type": "integer", "value": str(value)}
    if isinstance(value, float):
        return {"type": "float", "value": repr(value)}
    if isinstance(value, str):
        return {"type": "string", "value": value}
    if isinstance(value, list):
        return [from_python(item) for item in value]
    if isinstance(value, dict):
        return {name: from_python(held) for name, held in value.items()}
    if isinstance(value, datetime.datetime):
        if value.tzinfo is None:
            return {"type": "datetime-local", "value": value.isoformat()}
        return {"type": "datetime", "value": value.isoformat()}
    if isinstance(value, datetime.date):
        return {"type": "date-local", "value": value.isoformat()}
    if isinstance(value, datetime.time):
        return {"type": "time-local", "value": value.isoformat()}
    raise SystemExit(f"unknown Python value from tomllib: {value!r}")


def canon(node):
    """A tree with the spellings of its scalars normalized away."""
    if isinstance(node, list):
        return [canon(item) for item in node]
    if isinstance(node, dict) and set(node) == {"type", "value"}:
        kind, text = node["type"], node["value"]
        if kind == "float":
            number = float_of(text)
            if math.isnan(number):
                return (kind, "nan")
            if number == 0.0:
                number = 0.0
            return (kind, repr(number))
        if kind == "integer":
            return (kind, int(text))
        if kind == "datetime":
            return (kind, datetime.datetime.fromisoformat(text.replace("Z", "+00:00")).isoformat())
        if kind == "datetime-local":
            return (kind, datetime.datetime.fromisoformat(text).isoformat())
        if kind == "date-local":
            return (kind, datetime.date.fromisoformat(text).isoformat())
        if kind == "time-local":
            return (kind, datetime.time.fromisoformat(text).isoformat())
        return (kind, text)
    if isinstance(node, dict):
        return {name: canon(held) for name, held in node.items()}
    raise SystemExit(f"unknown node: {node!r}")


def b64(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def main():
    files = corpora()[""]
    cases = sorted(n for n in files if n.startswith("valid/") and n.endswith(".toml"))
    jobs = []
    expected = {}
    for name in cases:
        src = files[name]
        want = json.loads(files[name[:-5] + ".json"].decode("utf-8"))
        expected[name] = want
        # What the other writer emits is built here, from the suite's own tree.
        theirs = tomli_w.dumps(to_python(want)).encode("utf-8")
        jobs.append({"mode": "decode", "edition": 10, "data": b64(src)})
        jobs.append({"mode": "encode", "data": b64(json.dumps(want).encode("utf-8"))})
        jobs.append({"mode": "decode", "edition": 10, "data": b64(theirs)})

    reply = subprocess.run(
        ["node", str(DRIVER)],
        input=json.dumps(jobs),
        text=True,
        capture_output=True,
        check=True,
    )
    answers = json.loads(reply.stdout)
    if len(answers) != len(jobs):
        raise SystemExit("the driver did not answer every document")

    checks = {
        "tomllib reads the suite the way the suite says": 0,
        "our reader agrees with tomllib on the same bytes": 0,
        "tomllib reads what our writer emits": 0,
        "our reader reads what tomli-w emits": 0,
    }
    failures = []
    for index, name in enumerate(cases):
        want = expected[name]
        ours, encoded, from_theirs = answers[3 * index : 3 * index + 3]
        src = files[name]

        try:
            python_tree = from_python(tomllib.loads(src.decode("utf-8")))
        except Exception as exc:
            failures.append(f"{name}: tomllib could not read the suite's own file: {exc}")
            continue
        # Both readers on the suite's own bytes.
        ours_tree = json.loads(ours["text"]) if ours["ok"] else None
        if not ours["ok"]:
            failures.append(f"{name}: our reader refused the suite's own file: {ours['text']}")

        # The writer's output, read back by the standard library reader.
        written = None
        if encoded["ok"]:
            try:
                written = from_python(tomllib.loads(encoded["text"]))
            except Exception as exc:
                failures.append(f"{name}: tomllib could not read our output: {exc}: {encoded['text']!r}")
        else:
            failures.append(f"{name}: our writer refused the suite's tree: {encoded['text']}")

        # Their writer's output, read back by ours.
        from_their_tree = json.loads(from_theirs["text"]) if from_theirs["ok"] else None
        if not from_theirs["ok"]:
            failures.append(f"{name}: our reader refused tomli-w's output: {from_theirs['text']}")

        wanted = canon(want)
        for label, got in [
            ("tomllib reads the suite the way the suite says", python_tree),
            ("our reader agrees with tomllib on the same bytes", ours_tree),
            ("tomllib reads what our writer emits", written),
            ("our reader reads what tomli-w emits", from_their_tree),
        ]:
            if got is None:
                failures.append(f"{name}: {label}: no answer")
                continue
            try:
                same = canon(got) == wanted
            except Exception as exc:
                same = False
                failures.append(f"{name}: {label}: {exc}")
            if same:
                checks[label] += 1
            else:
                failures.append(
                    f"{name}: {label}\n    want {wanted}\n    got  {canon(got)}"
                )

    total = len(cases)
    for label, count in checks.items():
        print(f"{label}: {count}/{total}")
    if failures:
        print(f"\n{len(failures)} divergences:", file=sys.stderr)
        for line in failures[:25]:
            print("  " + line, file=sys.stderr)
        raise SystemExit(1)
    print(f"interop: {total} documents, {len(checks)} directions, all agreed")


if __name__ == "__main__":
    main()
