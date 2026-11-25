"""Reading the app's Swift as code, for the tests that follow a view through its blocks and its modifiers
(test_ios_readout_rows.py, test_ios_palette.py's Medium test).

`code_only` blanks every comment and every string literal's characters - same length, the same newlines, so an index
into it is an index into the file - and keeps a string's interpolations as code: `Text("\\(Text(a).font(f))")` still
names its font. Over that, the brackets match: `opener_before` finds the block or call a position is inside, `closer`
and `opener` match a bracket either way, and `chain_end` steps over a view's modifiers (`.font(...)`, `.overlay { }`,
`label: { }`, an `else { }`) to where its expression ends.
"""

import re

PAIRS = {"(": ")", "[": "]", "{": "}"}
BACK = {close: open_ for open_, close in PAIRS.items()}


def code_only(text: str) -> str:
    out = list(text)
    i, n = 0, len(text)
    modes = ["code"]
    depths = [0]

    def blank(a: int, b: int) -> None:
        for k in range(a, b):
            if out[k] != "\n":
                out[k] = " "

    while i < n:
        mode = modes[-1]
        c = text[i]
        if mode == "code":
            if text.startswith("//", i):
                j = text.find("\n", i)
                j = n if j < 0 else j
                blank(i, j)
                i = j
            elif text.startswith("/*", i):
                j = text.find("*/", i + 2)
                j = n if j < 0 else j + 2
                blank(i, j)
                i = j
            elif text.startswith('"""', i):
                modes.append("long")
                i += 3
            elif c == '"':
                modes.append("string")
                i += 1
            else:
                if c == "(":
                    depths[-1] += 1
                elif c == ")":
                    if depths[-1] == 0 and len(depths) > 1:
                        # an interpolation's end: back in its string, the ")" blanked with it
                        depths.pop()
                        modes.pop()
                        out[i] = " "
                        i += 1
                        continue
                    depths[-1] -= 1
                i += 1
            continue
        if c == "\\" and text.startswith("\\(", i):
            blank(i, i + 2)
            modes.append("code")
            depths.append(0)
            i += 2
        elif c == "\\":
            blank(i, min(i + 2, n))
            i += 2
        elif mode == "long" and text.startswith('"""', i):
            modes.pop()
            i += 3
        elif mode == "string" and c == '"':
            modes.pop()
            i += 1
        else:
            if c != "\n":
                out[i] = " "
            i += 1
    return "".join(out)


def closer(code: str, at: int) -> int:
    """The index of the bracket that closes the one at `at`."""
    depth = 0
    for i in range(at, len(code)):
        if code[i] in PAIRS:
            depth += 1
        elif code[i] in BACK:
            depth -= 1
            if depth == 0:
                return i
    raise ValueError(f"no closer for {at}")


def opener(code: str, at: int) -> int:
    """The index of the bracket that opens the one closing at `at`."""
    depth = 0
    for i in range(at, -1, -1):
        if code[i] in BACK:
            depth += 1
        elif code[i] in PAIRS:
            depth -= 1
            if depth == 0:
                return i
    raise ValueError(f"no opener for {at}")


def opener_before(code: str, at: int, kinds: str = "({[") -> int:
    """The index of the nearest unclosed bracket before `at` of `kinds` - the call or block `at` is inside - or -1."""
    depth = 0
    for i in range(at - 1, -1, -1):
        c = code[i]
        if c in BACK:
            depth += 1
        elif c in PAIRS:
            if depth == 0:
                if c in kinds:
                    return i
                # inside a bracket of another kind: keep looking past it
                continue
            depth -= 1
    return -1


def blocks_around(code: str, at: int) -> list[tuple[str, int, int]]:
    """The blocks `at` is inside, innermost first: (what opens it - the code before its "{" back to the statement's
    start - the "{" and its "}")."""
    found = []
    i = at
    while True:
        o = opener_before(code, i, "{")
        if o < 0:
            return found
        j = o - 1
        while j >= 0 and code[j] in " \t\n":
            j -= 1
        if j >= 0 and code[j] == ")":
            # a call's trailing closure (`HStack(spacing: 0) {`, a call over several lines): the whole call, from the
            # line its name is on
            line = code.rfind("\n", 0, opener(code, j)) + 1
            head = code[line:o].strip()
        else:
            start = max(code.rfind("\n", 0, o), code.rfind("{", 0, o), code.rfind("}", 0, o), code.rfind(";", 0, o))
            head = code[start + 1:o].strip()
        found.append((head, o, closer(code, o)))
        i = o


def chain_end(code: str, at: int) -> int:
    """From just after a view's expression (`at`), past every modifier and trailing closure of it: the index where the
    expression ends."""
    i = at
    n = len(code)
    while True:
        j = i
        while j < n and code[j] in " \t\n":
            j += 1
        if code.startswith(".", j) and re.match(r"\.[A-Za-z_]\w*", code[j:]):
            word = re.match(r"\.[A-Za-z_]\w*", code[j:])
            j += word.end()
            k = j
            while k < n and code[k] in " \t":
                k += 1
            if k < n and code[k] == "(":
                j = closer(code, k) + 1
                k = j
                while k < n and code[k] in " \t":
                    k += 1
            if k < n and code[k] == "{":
                j = closer(code, k) + 1
            i = j
            continue
        trailing = re.match(r"(label|content|header|footer|trailing|leading|else(\s+if\b[^{]*)?)\s*:?\s*\{", code[j:])
        if trailing:
            k = j + trailing.end() - 1
            i = closer(code, k) + 1
            continue
        return i


def expression_start(code: str, at: int) -> int:
    """Back from a modifier's "." at `at` to the start of the view expression it is a link of."""
    i = at
    while True:
        j = i - 1
        while j >= 0 and code[j] in " \t\n":
            j -= 1
        if j < 0:
            return i
        if code[j] in ")}]":
            o = opener(code, j)
            k = o - 1
            while k >= 0 and code[k] in " \t":
                k -= 1
            # a trailing closure after a call's arguments: `HStack(...) {`
            if code[o] == "{" and k >= 0 and code[k] == ")":
                o = opener(code, k)
            word = re.search(r"[A-Za-z_][\w.]*$", code[:o])
            i = word.start() if word else o
            if i > 0 and code[i - 1] == ".":
                i -= 1
                continue
            return i
        word = re.search(r"[A-Za-z_][\w.]*$", code[:j + 1])
        if word:
            return word.start()
        return i
