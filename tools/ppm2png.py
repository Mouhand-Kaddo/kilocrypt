"""Convert binary PPM frames to PNG using only the standard library."""
import struct
import sys
import zlib


def convert(src, dst):
    data = open(src, "rb").read()
    header, _, rest = data.partition(b"\n")
    _, width, height, _ = header.split()
    width, height = int(width), int(height)
    rows = b"".join(b"\0" + rest[y * width * 3:(y + 1) * width * 3] for y in range(height))

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(rows, 6)) + chunk(b"IEND", b"")
    open(dst, "wb").write(png)


for path in sys.argv[1:]:
    convert(path, path[:-4] + ".png")
