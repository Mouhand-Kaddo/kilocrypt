"""Pack a Linux ELF into a self-extracting ELF: context-mixing compressor plus a tiny asm decoder stub.

Usage: pack_linux.py INPUT OUTPUT [--search SECONDS] [--hash-bits BITS] [--verify]

The stub (tools/unpack.S) decodes into memory, writes the result to a memfd and execveat()s it,
passing argv and envp through. --search bounds the model search time (default 30, 0 skips it).
--hash-bits sets the decoder hash table to 4 << BITS bytes of RAM (default 26: 256 MB, briefly).
--verify also builds a debug stub that writes the decoded bytes to stdout and checks them.
"""
import array
import math
import multiprocessing
import os
import struct
import subprocess
import sys
import tempfile
import time

M64 = (1 << 64) - 1
HASH_MUL = 0x9E3779B97F4A7C15
SQUASH_SEED = 1458000
WORD_MASK = 0xFF
STUB_SOURCE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "unpack.S")
OUTBUF = 0x440000
MODEL_STRIDE = 0xD00
MAX_OUTPUT = 0x1E0000
FILESZ_OFFSET = 0x58
DEFAULT_MASKS = [0, 192, 128, 64, 140, 160, 82, 40, 144, 96, 138, WORD_MASK, 166, 32, 80, 220]
DEFAULT_PARAMS = dict(limit=3, rate_scale=8, rate_bias=10, shift=13, winit=1 << 13, hash_bits=26, e8e9=1)
E8E9_STUB_BYTES = 19
CANDIDATE_MASKS = list(range(0, 256, 2)) + [WORD_MASK]
MAX_MODELS = 19


def trim(elf):
    phoff, = struct.unpack_from("<Q", elf, 0x20)
    phentsize, phnum = struct.unpack_from("<HH", elf, 0x36)
    end = 0
    for i in range(phnum):
        kind, _, offset, _, _, filesz = struct.unpack_from("<IIQQQQ", elf, phoff + i * phentsize)
        if kind == 1:
            end = max(end, offset + filesz)
    elf = bytearray(elf[:end])
    struct.pack_into("<Q", elf, 0x28, 0)
    struct.pack_into("<HHH", elf, 0x3A, 0, 0, 0)
    return bytes(elf)


def build_tables():
    squash = [0] * 4096
    stretch = [0] * 4096
    v = SQUASH_SEED
    j = 0
    for x in range(4096):
        s = (v >> 20) + 1
        squash[x] = s
        while j <= s:
            stretch[j] = x - 2048
            j += 1
        v += (v * ((1 << 32) - v)) >> 40
    return squash, stretch


SQUASH, STRETCH = build_tables()
LOG2 = [0.0] + [-math.log2(i / 4096) for i in range(1, 4097)]


def e8e9(data):
    """x86 call/jump target transform, or None when an opcode byte sits in the last 4 bytes."""
    d = bytearray(data)
    i = 0
    while i < len(d):
        if d[i] & 0xFE == 0xE8:
            if i + 5 > len(d):
                return None
            v, = struct.unpack_from("<I", d, i + 1)
            struct.pack_into("<I", d, i + 1, (v + OUTBUF + i + 1) & 0xFFFFFFFF)
            i += 5
        else:
            i += 1
    return bytes(d)


def expand_mask(mask):
    m = 0
    for j in range(8):
        if mask >> j & 1:
            m |= 0xFF << (8 * j)
    return m


def model_address(i, n):
    return OUTBUF - (n - i) * MODEL_STRIDE


def is_word_byte(byte):
    return 0 <= (byte | 0x20) - 0x61 < 26


def byte_contexts(data, masks):
    """Per byte, every model's masked history (the previous 8 bytes, little-endian) as the stub computes it."""
    expanded = [expand_mask(m) for m in masks]
    out = []
    hist = 0
    word = 0
    for byte in data:
        out.append([(word if e & 0xFF else hist) & e for e in expanded])
        hist = (hist >> 8) | (byte << 56)
        word = ((word + 256 + byte) * HASH_MUL & M64) if is_word_byte(byte) else 0
    return out


def update_counter(state, y, limit, rate_scale, rate_bias):
    p = state >> 16
    n = state & 0xFFFF
    num = (p - (32768 if y else -32768)) * (rate_scale + 1)
    den = (rate_scale + 1) * n + rate_bias
    p -= num // den if num >= 0 else -((-num) // den)
    if n < limit:
        n += 1
    return (p << 16) | n


def model_inputs(data, mask, counter):
    """Stretched predictions of one model for every bit, using a private table (search estimate)."""
    table = {}
    out = array.array("h")
    append = out.append
    get = table.get
    for byte, (ctx,) in zip(data, byte_contexts(data, [mask])):
        c0 = 1
        for k in range(7, -1, -1):
            y = byte >> k & 1
            key = ctx ^ c0
            state = get(key, 0)
            append(STRETCH[(state >> 20) + 2048])
            table[key] = update_counter(state, y, *counter)
            c0 = c0 * 2 + y
    return out


def mix_cost(data, streams, shift, winit):
    """Estimated coded size in bytes of the mixer over precomputed model inputs."""
    n = len(streams)
    w1 = [[winit] * n for _ in range(256)]
    w2 = [[0] * n for _ in range(256)]
    w3 = [[0] * n for _ in range(256)]
    rows = list(zip(*streams))
    rng = range(n)
    bits = 0.0
    t = 0
    c1 = c2 = 0
    for byte in data:
        a_set = w1[c1]
        c_set = w3[c2]
        c0 = 1
        for k in range(7, -1, -1):
            y = byte >> k & 1
            ins = rows[t]
            b_set = w2[c0]
            dot = 0
            for i in rng:
                dot += (a_set[i] + b_set[i] + c_set[i]) * ins[i]
            d = dot >> 16
            if d > 2047:
                d = 2047
            elif d < -2048:
                d = -2048
            p = SQUASH[d + 2048]
            bits += LOG2[p] if y else LOG2[4096 - p]
            err = (y << 12) - p
            for i in rng:
                delta = (ins[i] * err) >> shift
                a_set[i] += delta
                b_set[i] += delta
                c_set[i] += delta
            c0 = c0 * 2 + y
            t += 1
        c1, c2 = byte, c1
    return bits / 8


WEIGHT_LIMIT = 1 << 29
PRODUCT_LIMIT = 1 << 31


def encode(data, masks, limit, rate_scale, rate_bias, shift, winit, hash_bits, **_):
    """Exact model and range coder, bit-for-bit what tools/unpack.S decodes.

    The stub mixes in 32-bit registers, so weights and products are kept well inside int32.
    """
    n = len(masks)
    salts = [model_address(i, n) for i in range(n)]
    hshift = 64 - hash_bits
    table = {}
    get = table.get
    w1 = [[0] * n for _ in range(256)]
    w2 = [[0] * n for _ in range(256)]
    w3 = [[0] * n for _ in range(256)]
    order = range(n - 1, -1, -1)
    low = 0
    rng = 1
    shifts = 0
    c1 = c2 = 0
    for byte, ctxs in zip(data, byte_contexts(data, masks)):
        a_set = w1[c1]
        c_set = w3[c2]
        c0 = 1
        for k in range(7, -1, -1):
            y = byte >> k & 1
            while rng < 1 << 24:
                rng <<= 8
                low <<= 8
                shifts += 1
            b_set = w2[c0]
            mixed = c0 | 256
            keys = [((c ^ mixed ^ s) * HASH_MUL & M64) >> hshift for c, s in zip(ctxs, salts)]
            ins = [STRETCH[(get(key, 0) >> 20) + 2048] for key in keys]
            dot = 0
            for a, b, c, x in zip(a_set, b_set, c_set, ins):
                term = (a + b + c + winit) * x
                if not -PRODUCT_LIMIT <= term < PRODUCT_LIMIT:
                    raise OverflowError("mixer product left the stub's int32 range")
                dot += term
            d = max(-2048, min(2047, dot >> 16))
            p = SQUASH[d + 2048]
            bound = (rng >> 12) * p
            if y:
                rng = bound
            else:
                low += bound
                rng -= bound
            err = (y << 12) - p
            for i in order:
                delta = (ins[i] * err) >> shift
                a_set[i] += delta
                b_set[i] += delta
                c_set[i] += delta
                if not (-WEIGHT_LIMIT < a_set[i] < WEIGHT_LIMIT and -WEIGHT_LIMIT < b_set[i] < WEIGHT_LIMIT
                        and -WEIGHT_LIMIT < c_set[i] < WEIGHT_LIMIT):
                    raise OverflowError("mixer weight left the stub's int32 range")
                table[keys[i]] = update_counter(get(keys[i], 0), y, limit, rate_scale, rate_bias)
            c0 = c0 * 2 + y
        c1, c2 = byte, c1
    top = low + rng - 1
    k = shifts
    while k and (top >> (8 * k)) << (8 * k) < low:
        k -= 1
    value = (top >> (8 * k)) << (8 * k)
    return value.to_bytes(shifts, "big").rstrip(b"\0")


_STREAMS = {}
_DATA = {}


def counter_params(config):
    return config["limit"], config["rate_scale"], config["rate_bias"]


def _stream_job(key):
    variant, mask, counter = key
    return key, model_inputs(_DATA[variant], mask, counter)


def _cost_job(job):
    variant, masks, counter, shift, winit = job
    try:
        streams = [_STREAMS[(variant, m, counter)] for m in masks]
        overhead = len(masks) + E8E9_STUB_BYTES * variant
        return job, overhead + mix_cost(_DATA[variant], streams, shift, winit)
    except OverflowError:
        return job, float("inf")


def pool_map(fn, items):
    with multiprocessing.get_context("fork").Pool(os.cpu_count()) as pool:
        return pool.map(fn, items)


class Search:
    """Time-bounded local search over model sets and mixer parameters, using estimated sizes."""

    def __init__(self, data, seconds):
        self.deadline = time.time() + seconds
        _DATA[0] = data
        _DATA[1] = e8e9(data)
        self.best = None
        self.variants = [0, 1] if _DATA[1] else [0]

    def evaluate(self, configs):
        chunk = 2 * os.cpu_count()
        for start in range(0, len(configs), chunk):
            if self.best is not None and time.time() > self.deadline:
                return
            batch = configs[start:start + chunk]
            keys = {(c["e8e9"], m, counter_params(c)) for c in batch for m in c["masks"]}
            _STREAMS.update(pool_map(_stream_job, sorted(keys - _STREAMS.keys())))
            jobs = [(c["e8e9"], tuple(c["masks"]), counter_params(c), c["shift"], c["winit"]) for c in batch]
            for (_, cost), config in zip(pool_map(_cost_job, jobs), batch):
                if self.best is None or cost < self.best[0]:
                    self.best = (cost, config)

    def improve(self, variations):
        if time.time() > self.deadline:
            return False
        before = self.best[0]
        self.evaluate(variations(self.best[1]))
        return self.best[0] < before - 0.5

    def run(self, start):
        self.evaluate([dict(start, e8e9=v) for v in self.variants])
        progress = True
        while progress and time.time() < self.deadline:
            progress = False
            progress |= self.improve(lambda c: [dict(c, masks=c["masks"] + [m]) for m in CANDIDATE_MASKS
                                                if m not in c["masks"] and len(c["masks"]) < MAX_MODELS])
            progress |= self.improve(lambda c: [dict(c, masks=[x for x in c["masks"] if x != m]) for m in c["masks"]])
            progress |= self.improve(lambda c: [dict(c, limit=v, rate_scale=s, rate_bias=s + b)
                                                for v in (2, 3, 4, 5, 6) for s in (2, 4, 8) for b in (2, 3)])
            progress |= self.improve(lambda c: [dict(c, shift=s) for s in (10, 11, 12, 13, 14)])
            progress |= self.improve(lambda c: [dict(c, winit=v) for v in (1 << 12, 1 << 13, 1 << 14, 1 << 15)])
        return self.best[1]


def assemble(params, masks, out_len, debug=False):
    symbols = dict(
        NMODELS=len(masks), LIMIT=params["limit"], RATE_SCALE=params["rate_scale"], RATE_BIAS=params["rate_bias"],
        SHIFT=params["shift"], WINIT=params["winit"], HASH_BITS=params["hash_bits"],
        E8E9=params["e8e9"], SQUASH_SEED=SQUASH_SEED, OUT_LEN=out_len, DEBUG=int(debug),
    )
    with tempfile.TemporaryDirectory() as tmp:
        obj = os.path.join(tmp, "unpack.o")
        flat = os.path.join(tmp, "unpack.bin")
        defsyms = [arg for k, v in symbols.items() for arg in ("--defsym", f"{k}={v}")]
        subprocess.run(["as", "--64", *defsyms, "-o", obj, STUB_SOURCE], check=True)
        subprocess.run(["objcopy", "-O", "binary", "-j", ".text", obj, flat], check=True)
        with open(flat, "rb") as f:
            return f.read()


def link(stub, masks, payload):
    image = bytearray(stub + bytes(masks) + payload)
    struct.pack_into("<Q", image, FILESZ_OFFSET, len(image))
    return bytes(image)


def verify(original, params, masks, payload):
    image = link(assemble(params, masks, len(original), debug=True), masks, payload)
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "debug-unpack")
        with open(path, "wb") as f:
            f.write(image)
        os.chmod(path, 0o755)
        decoded = subprocess.run([path], capture_output=True, check=True, timeout=60).stdout
    if decoded != original:
        first = next((i for i, (a, b) in enumerate(zip(decoded, original)) if a != b), min(len(decoded), len(original)))
        sys.exit(f"verify FAILED: decoded {len(decoded)} bytes, first difference at {first}")
    print(f"verify ok: stub decodes all {len(original)} bytes exactly", file=sys.stderr)


def take_option(args, name, default, kind):
    if name not in args:
        return default
    i = args.index(name)
    if i + 1 >= len(args):
        sys.exit(__doc__)
    value = kind(args[i + 1])
    del args[i:i + 2]
    return value


def main():
    args = sys.argv[1:]
    check = "--verify" in args
    if check:
        args.remove("--verify")
    seconds = take_option(args, "--search", 30.0, float)
    hash_bits = take_option(args, "--hash-bits", DEFAULT_PARAMS["hash_bits"], int)
    if len(args) != 2 or not 16 <= hash_bits <= 28:
        sys.exit(__doc__)
    started = time.time()
    with open(args[0], "rb") as f:
        elf = f.read()
    if elf[:5] != b"\x7fELF\x02" or len(elf) < 64:
        sys.exit(f"{args[0]}: not a 64-bit ELF file")
    elf = trim(elf)
    if not 8 <= len(elf) <= MAX_OUTPUT:
        sys.exit(f"{args[0]}: loaded size {len(elf)} is outside the stub's 8..{MAX_OUTPUT} byte buffer")
    config = dict(DEFAULT_PARAMS, masks=list(DEFAULT_MASKS), e8e9=int(e8e9(elf) is not None), hash_bits=hash_bits)
    if seconds > 0:
        config = Search(elf, seconds).run(config)
    masks = config["masks"]
    data = e8e9(elf) if config["e8e9"] else elf
    try:
        payload = encode(data, **config)
    except OverflowError as error:
        sys.exit(f"cannot pack with {config}: {error}")
    stub = assemble(config, masks, len(elf))
    image = link(stub, masks, payload)
    with open(args[1], "wb") as f:
        f.write(image)
    os.chmod(args[1], 0o755)
    shown = {k: v for k, v in config.items() if k != "masks"}
    print(f"elf {len(elf)} -> stub {len(stub)} + models {len(masks)} + payload {len(payload)} = {len(image)} bytes"
          f" in {time.time() - started:.1f}s", file=sys.stderr)
    print(f"masks {masks} {shown}", file=sys.stderr)
    if check:
        verify(elf, config, masks, payload)


if __name__ == "__main__":
    main()
