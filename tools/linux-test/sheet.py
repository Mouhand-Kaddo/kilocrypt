"""Convert every PPM frame in a directory to PNG and write a 3-column half-size contact sheet."""
import glob
import os
import struct
import sys
import zlib


def png(path, width, height, rows):
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    data = zlib.compress(b"".join(b"\0" + r for r in rows), 6)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", data) + chunk(b"IEND", b""))


def read_ppm(path):
    data = open(path, "rb").read()
    magic, width, height, _ = data.split(maxsplit=4)[:4]
    offset = len(b" ".join([magic, width, height, b"255"])) + 1
    width, height = int(width), int(height)
    return width, height, [data[offset + y * width * 3: offset + (y + 1) * width * 3] for y in range(height)]


def main(directory):
    smalls = []
    for path in sorted(glob.glob(os.path.join(directory, "*.ppm"))):
        width, height, rows = read_ppm(path)
        png(path[:-4] + ".png", width, height, rows)
        smalls.append([b"".join(r[x * 6:x * 6 + 3] for x in range(width // 2)) for r in rows[::2]])
        os.remove(path)
    if not smalls:
        return
    columns, half_w, half_h = 3, len(smalls[0][0]) // 3, len(smalls[0])
    blank = bytes(half_w * 3)
    sheet = []
    for gy in range((len(smalls) + columns - 1) // columns):
        for y in range(half_h):
            sheet.append(b"".join(smalls[gy * columns + gx][y] if gy * columns + gx < len(smalls) else blank for gx in range(columns)))
    png(os.path.join(directory, "sheet.png"), half_w * columns, len(sheet), sheet)


main(sys.argv[1])
