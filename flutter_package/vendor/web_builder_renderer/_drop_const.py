"""WB-theme — drop `const` from constructor calls whose body contains
`context.bt.` (the runtime theme lookup that can't be const).

Walk each .dart file under `lib/forms/`, find `const Foo(...)`,
`const Bar.named(...)`, etc. constructor calls; if the matching
parens contain `context.bt.` anywhere, drop the leading `const`.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path


def _matching_paren(s: str, open_idx: int) -> int:
    """Return index of the ``)`` that matches the ``(`` at ``open_idx``.
    Skips parens inside string literals (quotes ', ") and comments.
    Returns -1 if no match found."""
    depth = 0
    i = open_idx
    in_str: str | None = None
    while i < len(s):
        c = s[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == in_str:
                in_str = None
        else:
            if c in ("'", '"'):
                in_str = c
            elif c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    return i
        i += 1
    return -1


def process(text: str) -> tuple[str, int]:
    # Pattern: `const ` followed by an identifier (with optional .named)
    # then an opening paren. We then balance-match and check if
    # context.bt. is inside.
    pat = re.compile(r"\bconst (?=[A-Z][A-Za-z0-9_]*(?:\.[a-zA-Z][a-zA-Z0-9_]*)?\s*\()")
    out = []
    last = 0
    changed = 0
    for m in pat.finditer(text):
        const_start = m.start()
        # Find the opening paren after the identifier.
        open_paren = text.find("(", m.end())
        if open_paren == -1:
            continue
        close_paren = _matching_paren(text, open_paren)
        if close_paren == -1:
            continue
        body = text[open_paren:close_paren + 1]
        if "context.bt." in body:
            # Emit text up to const_start, skip the "const " keyword.
            out.append(text[last:const_start])
            last = m.end()  # skip "const "
            changed += 1
    out.append(text[last:])
    return "".join(out), changed


def main() -> int:
    base = Path(__file__).resolve().parent / "lib" / "forms"
    total = 0
    for f in base.rglob("*.dart"):
        original = f.read_text(encoding="utf-8")
        new, n = process(original)
        if n > 0:
            f.write_text(new, encoding="utf-8")
            print(f"  {f.relative_to(base)}: dropped {n} const")
            total += n
    print(f"\ntotal: {total}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
