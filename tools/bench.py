#!/usr/bin/env python3
"""Compare c3f with c3fmt (github.com/lmichaudel/c3fmt) on a tree of C3 files.

Usage:
    tools/bench.py --c3fmt PATH [--c3f build/c3f] [--corpus DIR] [--runs 5]
                   [--unit DIR] [--keep DIR]

Example, with c3c's unit tests (test/unit of a c3c checkout) as an extra check:
    tools/bench.py --c3fmt ../c3fmt/build/c3fmt --unit ../c3c/test/unit

Each formatter, in its default settings, formats a fresh copy of the corpus in
place (c3f also a second time with wrapping at 120 columns). The default corpus
is the standard library of the c3c on PATH (`c3c --version`, "Installed
directory" + lib/std). Build both tools with -O3 first.

Measured:
  time, memory   median wall time of --runs runs and the highest peak RSS
                 (/usr/bin/time), each run on a fresh copy
  lines changed  lines of the input that were changed or removed
  long lines     lines over 120 columns (tab = 4) before and after
  code changed   files whose text differs once all whitespace is removed
  second run     files that change again when the tool formats its own output
  third run      the same for a third run
  unit tests     with --unit DIR (c3c's test/unit): `c3c compile-test` against
                 each formatted copy (via --stdlib); the original is run first
  syntax error   formats a small file with an unclosed '(' via stdin
"""
import argparse
import os
import re
import shutil
import statistics
import subprocess
import sys
import tempfile

SYNTAX_ERROR = "module foo;\nfn void main()\n{\n  int x=1;\n  if (x>0 {\n    x+=2;\n  }\n}\n"
WHITESPACE = re.compile(rb"\s+")


def c3_files(root):
    out = []
    for d, _, names in os.walk(root):
        out += [os.path.relpath(os.path.join(d, n), root) for n in names if n.endswith((".c3", ".c3i"))]
    return sorted(out)


def read(path):
    with open(path, "rb") as f:
        return f.read()


def long_lines(root):
    return sum(1 for f in c3_files(root)
               for line in read(os.path.join(root, f)).decode("utf-8", "replace").split("\n")
               if len(line.expandtabs(4)) > 120)


def changed_files(a, b):
    return [f for f in c3_files(a) if read(os.path.join(a, f)) != read(os.path.join(b, f))]


def code_changed(a, b):
    return [f for f in c3_files(a)
            if WHITESPACE.sub(b"", read(os.path.join(a, f))) != WHITESPACE.sub(b"", read(os.path.join(b, f)))]


def lines_changed(a, b):
    out = subprocess.run(["git", "diff", "--no-index", "--numstat", a, b], capture_output=True, text=True).stdout
    return sum(int(line.split("\t")[1]) for line in out.splitlines() if not line.startswith("-"))


def copy(src, dst):
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst)


def timed(cmd, cwd):
    r = subprocess.run(["/usr/bin/time", "-f", "BENCH %e %M"] + cmd, cwd=cwd, capture_output=True, text=True)
    m = re.search(r"BENCH ([\d.]+) (\d+)", r.stderr)
    return float(m.group(1)), int(m.group(2)), r.returncode


def unit_tests(unit_dir, stdlib):
    unit_dir = os.path.abspath(unit_dir)
    r = subprocess.run(["c3c", "compile-test", os.path.basename(unit_dir), "--stdlib", os.path.abspath(stdlib)],
                       cwd=os.path.dirname(unit_dir), capture_output=True, text=True)
    out = re.sub(r"\x1b\[[0-9;]*m", "", r.stdout + r.stderr)
    m = re.search(r"Test Result: (\w+): (\d+) passed, (\d+) failed", out)
    if r.returncode == 0 and m:
        return f"yes ({m.group(2)} passed)"
    return f"no ({m.group(3)} failed)" if m else "no (does not compile)"


def default_corpus():
    out = subprocess.run(["c3c", "--version"], capture_output=True, text=True).stdout
    m = re.search(r"Installed directory:\s*(\S+)", out)
    if not m:
        sys.exit("cannot find the c3c installed directory; pass --corpus")
    return os.path.join(m.group(1), "lib", "std")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--c3f", default="build/c3f")
    ap.add_argument("--c3fmt", required=True)
    ap.add_argument("--corpus")
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--unit", help="c3c's test/unit directory")
    ap.add_argument("--keep", help="write the formatted copies here instead of a temporary directory")
    args = ap.parse_args()

    c3f, c3fmt = os.path.abspath(args.c3f), os.path.abspath(args.c3fmt)
    corpus = os.path.abspath(args.corpus or default_corpus())
    tools = {
        "c3f": [c3f, "--config", "/dev/null", "-w", "."],
        "c3f, 120 columns": [c3f, "--config", "/dev/null", "--set", "max_line_length=120",
                             "--set", "c3f_line_breaks=wrap", "-w", "."],
        "c3fmt": [c3fmt, "--default", "--in-place", "."],
    }
    stdin_cmd = {
        "c3f": [c3f, "--config", "/dev/null", "-"],
        "c3f, 120 columns": [c3f, "--config", "/dev/null", "--set", "max_line_length=120",
                             "--set", "c3f_line_breaks=wrap", "-"],
        "c3fmt": [c3fmt, "--default", "--stdin", "--stdout"],
    }
    work = args.keep or tempfile.mkdtemp(prefix="c3f-bench-")
    os.makedirs(work, exist_ok=True)
    files = c3_files(corpus)
    long_before = long_lines(corpus)
    print(f"corpus {corpus}: {len(files)} files, {long_before} lines over 120 columns, {os.cpu_count()} CPUs",
          file=sys.stderr)

    rows = {}
    if args.unit:
        rows["original"] = unit_tests(args.unit, corpus)
        print(f"unit tests on the original: {rows['original']}", file=sys.stderr)
    results = {}
    for name, cmd in tools.items():
        out = os.path.join(work, name.replace(", ", "-").replace(" ", "-"))
        times, mems, codes = [], [], []
        for _ in range(args.runs):
            copy(corpus, out)
            t, m, rc = timed(cmd, out)
            times.append(t), mems.append(m), codes.append(rc)
        second, third = out + "-run2", out + "-run3"
        copy(out, second)
        subprocess.run(cmd, cwd=second, capture_output=True)
        copy(second, third)
        subprocess.run(cmd, cwd=third, capture_output=True)
        err = subprocess.run(stdin_cmd[name], input=SYNTAX_ERROR, capture_output=True, text=True)
        if err.returncode == 0 and err.stdout.strip():
            syntax = "yes"
        elif err.returncode < 0:
            syntax = f"no (crashes, signal {-err.returncode})"
        else:
            syntax = f"no (exit {err.returncode})"
        r = {
            "time": f"{statistics.median(times):.2f} s",
            "memory": f"{max(mems) / 1024:.0f} MB",
            "exit": max(codes),
            "lines": lines_changed(corpus, out),
            "long": long_lines(out),
            "code": code_changed(corpus, out),
            "second": changed_files(out, second),
            "third": changed_files(second, third),
            "syntax": syntax,
        }
        if args.unit:
            r["unit"] = unit_tests(args.unit, out)
        results[name] = r
        print(f"{name}: {r['time']} (runs {times}), {r['memory']}, exit {r['exit']}, "
              f"code changed in {r['code']}, second run changes {r['second']}", file=sys.stderr)

    names = list(tools)
    table = [
        ("Time (median of %d runs)" % args.runs, "time"),
        ("Peak memory", "memory"),
        ("Lines changed", "lines"),
        ("Lines over 120 columns left (%s before)" % f"{long_before:,}", "long"),
        ("Files whose code changed (whitespace aside)", "code"),
        ("Files that change again on a second run", "second"),
        ("... and on a third run", "third"),
        ("Formats a file with a syntax error", "syntax"),
    ]
    if args.unit:
        table.append(("c3c's unit tests pass afterwards", "unit"))
    print("| | " + " | ".join(names) + " |")
    print("|---" * (len(names) + 1) + "|")
    for label, key in table:
        cells = []
        for n in names:
            v = results[n][key]
            cells.append(f"{len(v)}" if isinstance(v, list) else (f"{v:,}" if isinstance(v, int) else v))
        print(f"| {label} | " + " | ".join(cells) + " |")
    if args.keep:
        print(f"\nformatted copies in {work}", file=sys.stderr)
    else:
        shutil.rmtree(work)


if __name__ == "__main__":
    main()
