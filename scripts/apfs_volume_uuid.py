#!/usr/bin/env python3
"""Find APFS volume superblocks (APSB) in a disk image window and print their UUIDs.

XNU matches the root IOMedia by /chosen/root-matching -> UUID, so the UUID of
the APFS volume that carries the OS must come from the image we flashed.

Usage: apfs_volume_uuid.py IMAGE WINDOW_OFFSET WINDOW_BYTES
"""
import struct
import sys
import uuid

CHUNK = 1 << 20
OVERLAP = 4096


def le32(b, o):
    return struct.unpack_from('<I', b, o)[0]


def le64(b, o):
    return struct.unpack_from('<Q', b, o)[0]


def describe(f, window, absolute, magic):
    """Read the obj_phys header and the superblock fields around `absolute`."""
    f.seek(absolute)
    block = f.read(4096)
    if len(block) < 0x400:
        return None
    obj = 0  # APSB sits at obj + 32, obj itself is block aligned
    if block[32:36] != magic:
        return None
    otype = le32(block, 24)
    subtype = le32(block, 28)
    if magic == b'APSB':
        # obj_phys(32) + apfs_superblock: vol_uuid sits at obj+0xF0 and
        # volname (char[256]) at obj+0x2C0.  Verified against both an
        # Apple-produced dmg (044-76034-038.dmg volume 8846FE78-...) and a
        # mkapfs image (seed Data 7F00D031-...).
        vol_uuid = uuid.UUID(bytes=block[0xF0:0x100])
        name = block[0x2C0:0x3C0].split(b'\0', 1)[0].decode('utf-8', 'replace')
        return dict(kind='APSB', at=absolute, type=f'{otype:#x}', subtype=f'{subtype:#x}',
                    uuid=str(vol_uuid).upper(), name=name)
    if magic == b'NXSB':
        return dict(kind='NXSB', at=absolute, type=f'{otype:#x}', subtype=f'{subtype:#x}',
                    block_size=le32(block, 36), block_count=le64(block, 40))


def scan(f, window, size, label):
    hits = []
    f.seek(window)
    pending = b''
    done = 0
    while done < size:
        chunk = f.read(min(CHUNK, size - done))
        if not chunk:
            break
        data = pending + chunk
        base = done - len(pending)
        for magic in (b'NXSB', b'APSB'):
            start = 0
            while True:
                at = data.find(magic, start)
                if at < 0:
                    break
                start = at + 1
                absolute = window + base + at - 32
                if absolute < window or (absolute - window) % 4096:
                    continue
                info = describe(f, window, absolute, magic)
                if info:
                    info['window'] = label
                    hits.append(info)
                    print(f'  {label} {info}', flush=True)
        done += len(chunk)
        pending = data[-OVERLAP:]
    return hits


def main():
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    path, window, size = sys.argv[1], int(sys.argv[2], 0), int(sys.argv[3], 0)
    with open(path, 'rb') as f:
        print(f'{path} window {window:#x} size {size:#x}', flush=True)
        scan(f, window, size, 'window')


if __name__ == '__main__':
    main()
