#!/usr/bin/env python3
"""Build the fixed, deterministic teaching FAT12 floppy without host mounts."""
import argparse
from pathlib import Path
import struct

SECTOR = 512
RESERVED = 8
FAT_SECTORS = 9
ROOT_LBA = RESERVED + 2 * FAT_SECTORS
DATA_LBA = ROOT_LBA + 14


def set_entry(fat, cluster, value):
    offset = cluster + cluster // 2
    word = int.from_bytes(fat[offset:offset + 2], 'little')
    if cluster & 1:
        word = (word & 0x000F) | (value << 4)
    else:
        word = (word & 0xF000) | value
    fat[offset:offset + 2] = word.to_bytes(2, 'little')


def build(boot, loader, kernel):
    if len(boot) != SECTOR or boot[-2:] != b'\x55\xaa':
        raise ValueError('boot sector size/signature')
    if not 0 < len(loader) <= (RESERVED - 1) * SECTOR:
        raise ValueError('loader exceeds reserved area')
    if not 0 < len(kernel) <= 16384:
        raise ValueError('kernel exceeds 32 sectors')
    if struct.unpack_from('<H', boot, 14)[0] != RESERVED:
        raise ValueError('reserved-sector BPB mismatch')
    image = bytearray(2880 * SECTOR)
    image[:SECTOR] = boot
    image[SECTOR:SECTOR + len(loader)] = loader
    fat = bytearray(FAT_SECTORS * SECTOR)
    fat[:3] = b'\xf0\xff\xff'
    root = bytearray(14 * SECTOR)

    def add(slot, name, data, chain):
        if len(chain) != (len(data) + SECTOR - 1) // SECTOR:
            raise ValueError('invalid chain length')
        entry = slot * 32
        root[entry:entry + 11] = name
        root[entry + 11] = 0x20
        for date_offset in (16, 18, 24):
            struct.pack_into('<H', root, entry + date_offset, 0x0021)  # 1980-01-01
        struct.pack_into('<HI', root, entry + 26,
                         chain[0] if chain else 0, len(data))
        for i, cluster in enumerate(chain):
            set_entry(fat, cluster, chain[i + 1] if i + 1 < len(chain) else 0xFFF)
            offset = (DATA_LBA + cluster - 2) * SECTOR
            part = data[i * SECTOR:(i + 1) * SECTOR]
            image[offset:offset + len(part)] = part

    add(0, b'KERNEL  BIN', kernel, list(range(2, 2 + (len(kernel) + 511) // 512)))
    add(1, b'HELLO   TXT', b'Hello FAT12!\r\n', [100])
    # Exercise both parity cases spanning a FAT sector boundary, and fragmentation.
    add(2, b'EDGE    BIN', b'A' * 512 + b'B' * 512 + b'edge-end', [341, 682, 101])
    add(3, b'EMPTY   TXT', b'', [])
    image[ROOT_LBA * SECTOR:(ROOT_LBA + 14) * SECTOR] = root
    for start in [RESERVED, RESERVED + FAT_SECTORS]:
        image[start * SECTOR:(start + FAT_SECTORS) * SECTOR] = fat
    return image


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('boot', type=Path)
    parser.add_argument('loader', type=Path)
    parser.add_argument('kernel', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.write_bytes(build(args.boot.read_bytes(), args.loader.read_bytes(),
                                 args.kernel.read_bytes()))
