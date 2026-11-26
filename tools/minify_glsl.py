"""Minify a GLSL shader and emit it as a C header defining `shader_source`.

Function parameters and locals get scope-aware one-letter names (the same original name
reuses the same letter across functions); globals get the shortest names that do not clash
with locals in the functions that reference them. Float literals with no fraction are written
as ints (GLSL 4.3 converts implicitly) unless they touch `/` or `%`, or they are one bound of
`clamp` or `smoothstep` and the other bound is not a whole-number literal: NVIDIA rejects bounds
of mixed int and float type as an ambiguous overload.
"""
import collections
import os
import re
import sys

RESERVED = set("""
attribute const uniform varying layout centroid flat smooth noperspective break continue do for while switch case
default if else in out inout float int void bool true false invariant discard return mat2 mat3 mat4 vec2 vec3 vec4
ivec2 ivec3 ivec4 bvec2 bvec3 bvec4 uint uvec2 uvec3 uvec4 sampler2D struct precision highp mediump lowp location
version main radians degrees sin cos tan asin acos atan pow exp log exp2 log2 sqrt inversesqrt abs sign floor ceil
fract mod min max clamp mix step smoothstep length distance dot cross normalize reflect refract texture round trunc
tanh sinh cosh fwidth dFdx dFdy any all not equal lessThan greaterThan transpose inverse determinant
buffer std430 binding local_size_x ifdef ifndef endif define barrier memoryBarrier
""".split())
TYPES = set("float int uint bool vec2 vec3 vec4 ivec2 ivec3 ivec4 uvec2 uvec3 uvec4 bvec2 bvec3 bvec4 mat2 mat3 mat4 void".split())
TOKEN = re.compile(r"(?P<comment>//[^\n]*|/\*.*?\*/)|(?P<directive>#[^\n]*)|(?P<number>\d+\.\d*(?:[eE][-+]?\d+)?|\.\d+(?:[eE][-+]?\d+)?|\d+(?:[eE][-+]?\d+)?[uU]?)|(?P<ident>[A-Za-z_]\w*)|(?P<space>\s+)|(?P<other>.)", re.S)
DEV_MACROS = {"BOT", "LEVEL", "SHOWCASE", "STAND"}


def short_number(text, as_int):
    if "." not in text or "e" in text.lower():
        return text
    whole, frac = text.split(".")
    frac = frac.rstrip("0")
    whole = whole.lstrip("0")
    if not frac and as_int:
        return whole or "0"
    return (whole or ("" if frac else "0")) + "." + frac


def names():
    letters = "ZYXWVUTSRQPONMLKJIHGFEDCBAabcdefghijklmnopqrstuvwxyz"
    for a in letters:
        yield a
    for a in letters:
        for b in letters + "0123456789":
            if a + b not in RESERVED:
                yield a + b


BOUND_ARGUMENTS = {"clamp": (1, 2), "smoothstep": (0, 1)}


def call_arguments(tokens, i):
    """The function name and argument token spans of the call whose argument list holds token i."""
    depth = 0
    for open_at in range(i - 1, 0, -1):
        text = tokens[open_at][1]
        if text in (")", "]"):
            depth += 1
        elif text in ("(", "["):
            if depth == 0:
                break
            depth -= 1
    else:
        return None, []
    if tokens[open_at][1] != "(":
        return None, []
    spans, start = [], open_at + 1
    for j in range(open_at + 1, len(tokens)):
        text = tokens[j][1]
        if text in ("(", "["):
            depth += 1
        elif text in (")", "]") and depth > 0:
            depth -= 1
        elif depth == 0 and text in (",", ")"):
            spans.append((start, j))
            start = j + 1
            if text == ")":
                break
    return tokens[open_at - 1][1], spans


def whole_literal(tokens, start, end):
    words = [text for _, text in tokens[start:end]]
    words = words[1:] if words[:1] == ["-"] else words
    return len(words) == 1 and re.fullmatch(r"\d+(\.0*)?", words[0]) is not None


def integral_safe(tokens, i):
    """A fraction-less float literal may be written as an int unless int arithmetic could change its value
    or it would leave `clamp`/`smoothstep` with one int and one float bound."""
    before, after = tokens[i - 1][1], tokens[i + 1][1] if i + 1 < len(tokens) else ""
    across = [tokens[j][0] for j, operator in ((i - 2, before), (i + 2, after)) if operator == "*" and 0 <= j < len(tokens)]
    if before in "/%" or after in "/%" or "number" in across:
        return False
    name, spans = call_arguments(tokens, i)
    bounds = [span for k, span in enumerate(spans) if k in BOUND_ARGUMENTS.get(name, ())]
    own = next((span for span in bounds if span[0] <= i < span[1]), None)
    if len(bounds) == 2 and own and whole_literal(tokens, *own) and not all(whole_literal(tokens, *span) for span in bounds):
        return False
    return float(tokens[i][1].rstrip("uU")) < 2 ** 31


def scopes(tokens):
    """Return the function index of every token (None outside bodies) and each function's locals."""
    owner = [None] * len(tokens)
    locals_of = collections.defaultdict(set)
    depth, current, count = 0, None, 0
    for i, (_, text) in enumerate(tokens):
        if text == "{" and depth == 0 and tokens[i - 1][1] == ")":
            current, count = count, count + 1
            j, nesting = i - 1, 0
            while True:
                nesting += {")": 1, "(": -1}.get(tokens[j][1], 0)
                if nesting == 0:
                    break
                j -= 1
            for q in range(j + 1, i):
                owner[q] = current
                if tokens[q][0] == "ident" and tokens[q - 1][1] in TYPES:
                    locals_of[current].add(tokens[q][1])
        if text == "{":
            depth += 1
        elif text == "}":
            depth -= 1
            if depth == 0:
                owner[i] = current
                current = None
        if current is not None:
            owner[i] = current
    for i, (_, text) in enumerate(tokens[:-1]):
        if owner[i] is None or text not in TYPES or tokens[i + 1][0] != "ident" or tokens[i - 1][1] == ".":
            continue
        expect, nesting = True, 0
        for kind, word in tokens[i + 1:]:
            if expect and nesting == 0 and kind == "ident":
                if word in RESERVED:
                    break
                locals_of[owner[i]].add(word)
                expect = False
            elif word in "([":
                nesting += 1
            elif word in ")]":
                nesting -= 1
                if nesting < 0:
                    break
            elif word == "," and nesting == 0:
                expect = True
            elif word == ";" and nesting == 0:
                break
    return owner, locals_of


def minify(source):
    raw = [(m.lastgroup, m.group()) for m in TOKEN.finditer(source) if m.lastgroup != "comment"]
    tokens = [t for t in raw if t[0] != "space"]
    owner, locals_of = scopes(tokens)

    def renamable(i):
        kind, text = tokens[i]
        return kind == "ident" and text not in RESERVED and not text.startswith("gl_") and not text.isupper() and tokens[i - 1][1] != "."

    role = [None] * len(tokens)
    local_count, global_count = collections.Counter(), collections.Counter()
    users = collections.defaultdict(set)
    for i, (_, text) in enumerate(tokens):
        if not renamable(i):
            continue
        if owner[i] is not None and text in locals_of[owner[i]]:
            role[i] = "local"
            local_count[text] += 1
        else:
            role[i] = "global"
            global_count[text] += 1
            if owner[i] is not None:
                users[text].add(owner[i])
    global_scope = {text for i, (kind, text) in enumerate(tokens) if owner[i] is None and kind == "ident"}
    clashes = sorted(global_scope & set().union(*locals_of.values()))
    if clashes:
        sys.exit(f"minify: locals reuse global names: {clashes}")
    defined = [tokens[i + 1][1] for i in range(len(tokens) - 2) if owner[i] is None and tokens[i][1] in TYPES and tokens[i + 2][1] == "(" and owner[i + 3] is not None]
    duplicates = sorted({name for name in defined if defined.count(name) > 1} - {"main"})
    if duplicates:
        sys.exit(f"minify: overloaded functions are not supported: {duplicates}")

    local_name, taken_in = {}, collections.defaultdict(set)
    for name in sorted(local_count, key=lambda n: -local_count[n]):
        functions = {f for f, names_ in locals_of.items() if name in names_}
        local_name[name] = next(c for c in names() if not any(c in taken_in[f] for f in functions))
        for f in functions:
            taken_in[f].add(local_name[name])
    global_name, taken = {}, set()
    for name in sorted(global_count, key=lambda n: -global_count[n]):
        clash = set().union(*(taken_in[f] for f in users[name]))
        global_name[name] = next(c for c in names() if c not in taken and c not in clash)
        taken.add(global_name[name])

    out, index = [], 0
    for kind, text in raw:
        if kind == "space":
            out.append(("space", " "))
            continue
        i, index = index, index + 1
        if kind == "directive":
            out.append(("directive", text.strip() + "\n"))
        elif kind == "number":
            out.append(("word", short_number(text, integral_safe(tokens, i))))
        elif role[i] == "local":
            out.append(("word", local_name[text]))
        elif role[i] == "global":
            out.append(("word", global_name[text]))
        else:
            out.append(("word" if kind == "ident" else "other", text))
    result = []
    for i, (kind, text) in enumerate(out):
        if kind == "space":
            before = result[-1] if result else ""
            after = next((t for k, t in out[i + 1:] if k != "space"), "")
            if before and after and (re.match(r"\w", before[-1]) and re.match(r"[\w.]", after[0]) or before[-1] in "+-" and after[0] == before[-1]):
                result.append(" ")
            continue
        if kind == "directive" and result and not result[-1].endswith("\n"):
            result.append("\n")
        result.append(text)
    return "".join(result)


def strip_dev(source):
    """Drop `#ifdef` blocks guarded by dev-only macros, keeping nesting intact."""
    kept, skipping = [], 0
    for line in source.split("\n"):
        words = line.split()
        if skipping:
            if words[:1] in (["#ifdef"], ["#ifndef"], ["#if"]):
                skipping += 1
            elif words[:1] == ["#endif"]:
                skipping -= 1
        elif words[:1] == ["#ifdef"] and words[1] in DEV_MACROS:
            skipping = 1
        else:
            kept.append(line)
    return "\n".join(kept)


def game_lines(source):
    """The source as the release compute shader sees it: dev blocks and the fragment branch blanked, line numbers kept."""
    lines, stack = [], []
    for line in source.split("\n"):
        words = line.split()
        head = words[0] if words else ""
        if head in ("#ifdef", "#ifndef", "#if"):
            name = words[1] if len(words) > 1 else ""
            kind = "dev" if head == "#ifdef" and name in DEV_MACROS else "game" if head == "#ifdef" and name == "GAME" else "other"
            stack.append([kind != "dev", kind])
            line = ""
        elif head == "#else" and stack:
            stack[-1][0] = stack[-1][0] and stack[-1][1] != "game"
            line = ""
        elif head == "#endif" and stack:
            stack.pop()
            line = ""
        lines.append(line if all(active for active, _ in stack) else "")
    return "\n".join(lines)


def constant(tokens):
    return bool(tokens) and all(kind == "number" or word in "+-*/()." for kind, word in tokens)


def loop_bound_problems(source):
    """Loops in release compute code whose trip count is a compile-time constant without `dynamicZero` in the bound.

    The AMD Windows driver fully unrolls such loops (a 153 s link and a black screen), so every one must read `N + dynamicZero`.
    """
    tokens, line = [], 1
    for m in TOKEN.finditer(game_lines(source)):
        if m.lastgroup not in ("space", "comment"):
            tokens.append((m.lastgroup, m.group(), line))
        line += m.group().count("\n")
    problems, lines = [], source.split("\n")
    for i, (_, word, at) in enumerate(tokens):
        if word != "for" or i + 1 >= len(tokens) or tokens[i + 1][1] != "(":
            continue
        parts, depth = [[]], 1
        for kind, w, _ in tokens[i + 2:]:
            depth += (w == "(") - (w == ")")
            if depth == 0:
                break
            if depth == 1 and w == ";":
                parts.append([])
            else:
                parts[-1].append((kind, w))
        if len(parts) != 3 or any(w == "dynamicZero" for _, w in parts[1]):
            continue
        init, cond = parts[0], parts[1]
        words = [w for _, w in init]
        if "=" not in words:
            continue
        var, start = init[words.index("=") - 1][1], init[words.index("=") + 1:]
        for k in range(len(cond) - 1):
            if cond[k][1] != var or cond[k + 1][1] not in ("<", ">", "!"):
                continue
            rest = cond[k + 2:]
            if rest and rest[0][1] == "=":
                rest = rest[1:]
            bound, depth = [], 0
            for kind, w in rest:
                depth += (w == "(") - (w == ")")
                if depth < 0 or depth == 0 and w in ("&", "|", "?", ","):
                    break
                bound.append((kind, w))
            shifted = len(bound) > len(start) and bound[:len(start)] == start and constant(bound[len(start):])
            if constant(bound) and constant(start) or shifted:
                problems.append(f"line {at}: constant loop bound without dynamicZero: {lines[at - 1].strip()}")
    return problems


def mod_divisor_problems(source):
    """`mod()` calls in release code whose divisor is not a constant.

    radeonsi computes `mod(x, y)` as `x - y * floor(x * rcp(y))`; for a runtime `y`, `mod(3.0, 3.0)` returns 3.0, so a
    wrap-around index can land one past its range. Use a constant divisor or an integer `%`.
    """
    tokens, line = [], 1
    for m in TOKEN.finditer(strip_dev(source)):
        if m.lastgroup not in ("space", "comment"):
            tokens.append((m.lastgroup, m.group(), line))
        line += m.group().count("\n")
    problems = []
    for i, (_, word, at) in enumerate(tokens):
        if word != "mod" or i + 1 >= len(tokens) or tokens[i + 1][1] != "(":
            continue
        args, depth = [[]], 1
        for kind, w, _ in tokens[i + 2:]:
            depth += (w == "(") - (w == ")")
            if depth == 0:
                break
            if depth == 1 and w == ",":
                args.append([])
            else:
                args[-1].append((kind, w))
        if len(args) == 2 and not constant(args[1]):
            problems.append(f"mod() with a runtime divisor: mod({' '.join(w for _, w in args[0])}, {' '.join(w for _, w in args[1])})")
    return problems


def main():
    source = open(sys.argv[1]).read()
    if "--release" in sys.argv:
        sys.argv.remove("--release")
        problems = loop_bound_problems(source) + mod_divisor_problems(source)
        if problems and os.environ.get("LINT") == "warn":
            print("\n".join(problems), file=sys.stderr)
        elif problems:
            sys.exit("\n".join(problems))
        source = strip_dev(source)
    text = minify(source)
    escaped = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    with open(sys.argv[2], "w") as f:
        f.write('static const char shader_source[] = "%s";\n' % escaped)
    if len(sys.argv) > 3:
        open(sys.argv[3], "w").write(text)
    print(f"shader: {len(source)} -> {len(text)} bytes", file=sys.stderr)


main()
