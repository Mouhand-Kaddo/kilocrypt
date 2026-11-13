"""Compare two PNG frames written by the headless harness and optionally write an amplified difference image.

Usage: python3 tools/linux-test/pixdiff.py A.png B.png [DIFF.png]

Reads the harness's own PNGs (8-bit RGB, unfiltered rows). Prints the share of pixels that differ by more
than 2/255 in any channel, the largest channel difference and the mean absolute difference.
"""
import struct
import sys
import zlib


def read_png(path):
    try:
        data = open(path, "rb").read()
    except OSError as error:
        sys.exit(f"{path}: {error.strerror}")
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit(f"{path}: not a PNG")
    pos, idat, size = 8, b"", None
    while pos + 8 <= len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, color = struct.unpack(">IIBB", body[:10])
            if (depth, color) != (8, 2):
                sys.exit(f"{path}: only 8-bit RGB PNGs are supported")
            size = (width, height)
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    if size is None or not idat:
        sys.exit(f"{path}: missing IHDR or IDAT")
    raw, stride = zlib.decompress(idat), size[0] * 3 + 1
    if len(raw) != stride * size[1] or any(raw[y * stride] for y in range(size[1])):
        sys.exit(f"{path}: filtered or truncated rows are not supported")
    return size, [raw[y * stride + 1:(y + 1) * stride] for y in range(size[1])]


def write_png(path, size, rows):
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))
    header = struct.pack(">IIBBBBB", size[0], size[1], 8, 2, 0, 0, 0)
    data = zlib.compress(b"".join(b"\0" + bytes(r) for r in rows), 6)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", data) + chunk(b"IEND", b""))


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__.strip().split("\n\n")[1])
    (size_a, rows_a), (size_b, rows_b) = read_png(sys.argv[1]), read_png(sys.argv[2])
    if size_a != size_b:
        sys.exit(f"sizes differ: {size_a} and {size_b}")
    changed, largest, total, diff_rows = 0, 0, 0, []
    for a, b in zip(rows_a, rows_b):
        d = [abs(x - y) for x, y in zip(a, b)]
        total += sum(d)
        largest = max(largest, max(d))
        changed += sum(1 for i in range(0, len(d), 3) if max(d[i], d[i + 1], d[i + 2]) > 2)
        diff_rows.append([min(255, v * 8) for v in d])
    pixels = size_a[0] * size_a[1]
    print(f"{changed / pixels * 100:.2f}% of pixels differ by more than 2/255, largest difference {largest}/255, "
          f"mean absolute difference {total / (pixels * 3):.3f}/255")
    if len(sys.argv) == 4:
        write_png(sys.argv[3], size_a, diff_rows)


main()
