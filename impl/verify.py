#!/usr/bin/env python3
"""QEMU checks for all chapter images, including corrupted FAT12 fixtures.

No GUI inspection is claimed: BIOS screen output is checked through VGA RAM.
Transcripts and the QEMU termination reason are retained under transcripts/.
"""
import argparse
import json
import os
from pathlib import Path
import re
import socket
import select
import subprocess
import tempfile
import time

from mkfat12 import DATA_LBA, RESERVED, ROOT_LBA, SECTOR, set_entry

BASE = Path(__file__).resolve().parent
LOG = BASE / 'transcripts'
RESULTS = []
QEMU = 'qemu-system-i386'
NASM = 'nasm'
LINKER = 'ld.lld'


def guest(name, image, commands=b'', expect=(), reject=(), reboot=False,
          screen=(), nosig=False, eject=False):
    with tempfile.TemporaryDirectory(prefix='tinypc-verify-') as tmp:
        tmp = Path(tmp)
        args = [QEMU, '-drive', f'file={image},format=raw,if=floppy',
                '-display', 'none', '-serial', 'stdio', '-no-reboot',
                '-monitor', 'none']
        if screen and not commands:
            args[-1] = 'stdio'
            args[args.index('-serial') + 1] = 'none'
        elif screen:
            args[-1] = f'unix:{tmp}/monitor,server=on,wait=off'
        if eject:
            args[-1] = f'unix:{tmp}/monitor,server=on,wait=off'
        if nosig:
            args += ['-debugcon', f'file:{tmp}/bios.log',
                     '-global', 'isa-debugcon.iobase=0x402']
        proc = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE)
        reason = 'guest-exit'
        prefix = b''
        try:
            if eject:
                deadline = time.monotonic() + 4
                while not prefix.endswith(b'> '):
                    if time.monotonic() >= deadline:
                        raise AssertionError('guest did not reach shell before eject')
                    ready, _, _ = select.select([proc.stdout], [], [], 0.1)
                    if ready:
                        chunk = os.read(proc.stdout.fileno(), 4096)
                        if not chunk:
                            raise AssertionError('QEMU exited before eject')
                        prefix += chunk
                with socket.socket(socket.AF_UNIX) as control:
                    control.settimeout(3)
                    control.connect(str(tmp / 'monitor'))
                    for command in (None, b'eject -f floppy0\n'):
                        if command:
                            control.sendall(command)
                        reply = b''
                        while b'(qemu)' not in reply:
                            part = control.recv(4096)
                            if not part:
                                raise AssertionError('monitor closed during eject')
                            reply += part
                        if b'Error' in reply:
                            raise AssertionError(reply.decode(errors='replace'))
                    (LOG / f'{name}-monitor.txt').write_bytes(reply)
            if screen and commands:
                proc.stdin.write(commands)
                proc.stdin.flush()
                time.sleep(0.7)
                with socket.socket(socket.AF_UNIX) as control:
                    control.settimeout(3)
                    control.connect(str(tmp / 'monitor'))
                    control.sendall(f'pmemsave 0xb8000 4000 "{tmp}/vga.bin"\n'.encode())
                    deadline = time.monotonic() + 3
                    while not (tmp / 'vga.bin').exists():
                        if time.monotonic() >= deadline:
                            raise AssertionError('monitor did not save VGA memory')
                        time.sleep(0.02)
                    control.sendall(b'quit\n')
                commands = None
            elif screen:
                time.sleep(0.7)
                commands = f'pmemsave 0xb8000 4000 "{tmp}/vga.bin"\nquit\n'.encode()
            output, error = proc.communicate(commands, timeout=1.5)
        except subprocess.TimeoutExpired:
            reason = 'harness-timeout'
            proc.terminate()
            try:
                output, error = proc.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                output, error = proc.communicate()
                reason = 'harness-kill'
        except Exception:
            proc.kill()
            proc.communicate()
            raise
        text = (prefix + output).decode('ascii', errors='replace').replace('\r', '')
        if screen:
            text += '\nVGA:\n' + (tmp / 'vga.bin').read_bytes()[::2].decode('ascii')
        if nosig:
            text += '\nBIOS:\n' + (tmp / 'bios.log').read_text(errors='replace')
        record = f'argv={args!r}\nreturncode={proc.returncode}\ntermination={reason}\n'
        (LOG / f'{name}.txt').write_text(record + text + '\nSTDERR:\n' + error.decode())
        for pattern in (*expect, *screen):
            if not re.search(pattern, text, re.M):
                raise AssertionError(f'{name}: missing {pattern!r}; see transcripts/{name}.txt')
        for pattern in reject:
            if re.search(pattern, text, re.M):
                raise AssertionError(f'{name}: unexpected {pattern!r}')
        if reboot or screen:
            assert proc.returncode == 0 and reason == 'guest-exit', name
        else:
            assert reason == 'harness-timeout' and proc.returncode in (0, -15), name
            assert b'terminating on signal 15' in error, name
        return text


def case(name, fn):
    try:
        fn()
    except Exception as exc:
        RESULTS.append({'name': name, 'status': 'FAIL', 'error': str(exc)})
        print(f'FAIL {name}: {exc}', flush=True)
    else:
        RESULTS.append({'name': name, 'status': 'PASS'})
        print(f'PASS {name}', flush=True)


def image(ch):
    return BASE / ch / f'{ch}.img'


def mutate(name, callback):
    data = bytearray(image('ch09_fat12').read_bytes())
    callback(data)
    path = LOG / f'{name}.img'
    path.write_bytes(data)
    return path


def fat_change(data, cluster, value):
    # Alter both copies; this reader uses the first copy.
    for lba in [RESERVED, RESERVED + 9]:
        start = lba * SECTOR
        fat = bytearray(data[start:start + 9 * SECTOR])
        set_entry(fat, cluster, value)
        data[start:start + len(fat)] = fat


def main():
    global QEMU, NASM, LINKER
    parser = argparse.ArgumentParser()
    parser.add_argument('--qemu', default=QEMU)
    parser.add_argument('--nasm', default=NASM)
    parser.add_argument('--linker', default=LINKER)
    options = parser.parse_args()
    QEMU, NASM, LINKER = options.qemu, options.nasm, options.linker
    LOG.mkdir(exist_ok=True)

    def structures():
        for path in BASE.glob('ch*/*.img'):
            data = path.read_bytes()
            assert len(data) == 1474560 and data[510:512] == b'\x55\xaa', path
        for path in BASE.glob('ch*/*'):
            if path.suffix in {'.s', '.asm'}:
                assert 'cpu 8086' in path.read_text(), path
        for directory in ['ch05_kernel', 'ch06_shell', 'ch07_shellcmds', 'ch09_fat12']:
            # Raw binary ENTRY alone does not position the first instruction.
            # The map must actually place _start at the linked load address.
            mapping = (BASE / directory / 'kernel.map').read_text()
            assert re.search(r'\b8000\b.*_start', mapping), mapping
        for path, bound in [('ch09_fat12/loader.bin', 3584),
                            ('ch09_fat12/kernel.bin', 16384)]:
            assert 0 < (BASE / path).stat().st_size <= bound
    case('structures', structures)

    def reset():
        path = LOG / 'reset.log'
        result = subprocess.run([QEMU, '-display', 'none', '-serial', 'none',
                                 '-monitor', 'none', '-d', 'in_asm', '-D', str(path)],
                                timeout=0.7, capture_output=True)
        raise AssertionError(f'unexpected QEMU exit {result.returncode}')
    # subprocess timeout is expected here, but the trace must contain the fetch.
    def reset_check():
        try:
            reset()
        except subprocess.TimeoutExpired:
            assert '0xfffffff0:' in (LOG / 'reset.log').read_text()
    case('reset', reset_check)
    case('ch02-vga', lambda: guest('ch02-vga', image('ch02a_int10'), screen=['Hello, BIOS!']))
    case('ch02-uart', lambda: guest('ch02-uart', image('ch02b_serial'), expect=['Hello, UART!']))
    def nosig():
        data = bytearray(image('ch02b_serial').read_bytes())
        data[510:512] = b'\0\0'
        path = LOG / 'nosig.img'
        path.write_bytes(data)
        guest('nosig', path, expect=['not a bootable disk'], reject=['Hello, UART!'], nosig=True)
    case('no-signature', nosig)
    case('ch03-ivt', lambda: guest('ch03-ivt', image('ch03_hook'), expect=['!!!', 'INT 10h ->']))
    case('ch04-stage2', lambda: guest('ch04-stage2', image('ch04_stage2'), expect=['stage2: hello']))
    case('ch05-bss', lambda: guest('ch05-bss', image('ch05_kernel'), expect=['bss_test=0x00']))
    def poisoned_bss(clear):
        name = 'bss-poison-clear' if clear else 'bss-poison-control'
        with tempfile.TemporaryDirectory(prefix='tinypc-bss-') as tmp:
            tmp = Path(tmp)
            source = (BASE / 'ch05_kernel/crt0.s').read_text()
            source = source.replace('    mov di, __bss_start',
                                    '    mov byte [__bss_start], 0xA5\n    mov di, __bss_start')
            if not clear:
                source = source.replace('    rep stosb', '    nop\n    nop')
            (tmp / 'crt0.s').write_text(source)
            subprocess.run([NASM, '-f', 'elf32', '-o', str(tmp / 'crt0.o'), str(tmp / 'crt0.s')], check=True)
            subprocess.run([LINKER, '-m', 'elf_i386', '-T', str(BASE / 'ch05_kernel/linker.ld'),
                            '-o', str(tmp / 'kernel.bin'), str(tmp / 'crt0.o'),
                            str(BASE / 'ch05_kernel/console.o'), str(BASE / 'ch05_kernel/main.o')], check=True)
            data = bytearray(image('ch05_kernel').read_bytes())
            data[512:512 + 16384] = bytes(16384)
            kernel = (tmp / 'kernel.bin').read_bytes()
            assert len(kernel) <= 16384
            data[512:512 + len(kernel)] = kernel
            path = LOG / f'{name}.img'
            path.write_bytes(data)
        expected = '00' if clear else 'A5'
        guest(name, path, expect=[f'bss_test=0x{expected}'])
    case('bss-poison-clear', lambda: poisoned_bss(True))
    case('bss-poison-control', lambda: poisoned_bss(False))
    case('ch06-shell', lambda: guest('ch06-shell', image('ch06_shell'),
         b'help\necho hi\nbogus\nq\n', expect=['commands: help echo cls q', '^hi$', 'unknown: bogus', '^bye$']))
    def input_checks():
        text = guest('ch06-input', image('ch06_shell'),
                     b'\r\necho abc\x08d\r\na b c d e f g h i\r\necho ' + b'x' * 80 + b'\nq\n',
                     expect=['^abd$', 'error: too many arguments', '^bye$'])
        assert len(re.findall(r'^> ', text, re.M)) == 5, text
        assert '\n' + 'x' * 58 + '\n' in text, text
    case('ch06-input-bounds', input_checks)
    case('ch07-memory', lambda: guest('ch07-memory', image('ch07_shellcmds'),
         b'ivt 10\npeek 7c00\ndump 7df0 10\npoke 7df0 5a\npeek 7df0\nmem\nticks\nq\n',
         expect=['INT 10h ->', '0x00007C00: EB', '55 AA', '0x00007DF0: 5A', 'mem: 0x', 'ticks: 0x', '^bye$']))
    def numeric():
        text = guest('ch07-invalid', image('ch07_shellcmds'),
                     b'peek z\npeek 1g\npeek 10000\npeek 0x\nivt 100\npoke 600 100\nq\n', expect=['^bye$'])
        assert text.count('error: bad address') == 6, text
    case('ch07-invalid-hex', numeric)
    case('ch07-vga', lambda: guest('ch07-vga', image('ch07_shellcmds'),
         b'vga HI\nq\n', expect=['vga: printed', '^bye$'], screen=['HI']))
    case('ch07-reboot', lambda: guest('ch07-reboot', image('ch07_shellcmds'),
         b'reboot\n', expect=['rebooting:'], reboot=True))
    case('ch09-files', lambda: guest('ch09-files', image('ch09_fat12'),
         b'ls\nload hello.txt\ndump 600 e\nload EDGE.BIN\ndump 600 1\ndump 800 1\ndump a00 8\nload EMPTY.TXT\nload nope.bin\nload TOOLONGXX.TXT\nload A.TOOL\nload ../X\nq\n',
         expect=['^KERNEL.BIN$', '^HELLO.TXT$', '^EDGE.BIN$', '^EMPTY.TXT$',
                 'bytes=0x000E', '48 65 6C 6C 6F', 'bytes=0x0408',
                 '0x00000600: 41', '0x00000800: 42', '65 64 67 65 2D 65 6E 64',
                 'bytes=0x0000', 'error: file missing', 'error: expected load', '^bye$']))
    # Mutations are applied to independent images; originals are never modified.
    for name, value in [('free', 0), ('reserved', 1), ('bad', 0xFF7),
                        ('out-of-range', 3000), ('early-eoc', 0xFFF), ('cycle', 341)]:
        def check(name=name, value=value):
            path = mutate(name, lambda data: fat_change(data, 341, value))
            guest(name, path, b'load EDGE.BIN\necho alive\nq\n',
                  expect=['error: file missing', '^alive$', '^bye$'], reject=['bytes=0x0408'])
        case('fat-' + name, check)
    def overflow():
        def change(data):
            entry = ROOT_LBA * SECTOR + 2 * 32
            data[entry + 28:entry + 32] = (0x7000).to_bytes(4, 'little')
        path = mutate('capacity', change)
        guest('capacity', path, b'load EDGE.BIN\necho alive\nq\n', expect=['error: file missing', '^alive$'])
    case('fat-capacity', overflow)
    def boot_bad():
        path = mutate('boot-cycle', lambda data: fat_change(data, 2, 2))
        guest('boot-cycle', path, expect=['boot: FAT12 load failed'], reject=['kernel:'])
    case('fat-boot-cycle', boot_bad)
    def bpb_bad():
        def change(data):
            data[13] = 2
        path = mutate('unsupported-bpb', change)
        guest('unsupported-bpb', path, expect=['boot: FAT12 load failed'], reject=['kernel:'])
    case('fat-unsupported-bpb', bpb_bad)

    def fragmented_boot():
        def change(data):
            kernel = (BASE / 'ch09_fat12/kernel.bin').read_bytes()
            count = (len(kernel) + 511) // 512
            chain = [341, 682] + list(range(200, 200 + count - 2))
            data[ROOT_LBA * SECTOR + 26:ROOT_LBA * SECTOR + 28] = chain[0].to_bytes(2, 'little')
            for i, cluster in enumerate(chain):
                fat_change(data, cluster, chain[i + 1] if i + 1 < count else 0xFFF)
                start = (DATA_LBA + cluster - 2) * SECTOR
                part = kernel[i * SECTOR:(i + 1) * SECTOR]
                data[start:start + len(part)] = part
        path = mutate('fragmented-kernel', change)
        guest('fragmented-kernel', path, b'echo booted\nq\n', expect=['^booted$', '^bye$'])
    case('fat-fragmented-kernel', fragmented_boot)
    def root_second_sector():
        def change(data):
            root = ROOT_LBA * SECTOR
            data[root + 16 * 32:root + 17 * 32] = data[root + 32:root + 64]
            data[root + 32] = 0xE5
            for slot in range(4, 16):
                data[root + slot * 32] = 0xE5
        path = mutate('root-second-sector', change)
        guest('root-second-sector', path, b'load HELLO.TXT\nq\n', expect=['bytes=0x000E', '^bye$'])
    case('fat-root-second-sector', root_second_sector)
    def disk_error():
        guest('disk-error', image('ch09_fat12'), b'load EDGE.BIN\necho alive\nq\n',
              expect=['error: file missing', '^alive$', '^bye$'], eject=True)
    case('fat-disk-error', disk_error)
    def oversized_boot():
        def change(data):
            start = ROOT_LBA * SECTOR + 28
            data[start:start + 4] = (0x4200).to_bytes(4, 'little')
        path = mutate('oversized-kernel', change)
        guest('oversized-kernel', path, expect=['boot: FAT12 load failed'], reject=['kernel:'])
    case('fat-oversized-kernel', oversized_boot)

    (LOG / 'summary.json').write_text(json.dumps(RESULTS, indent=2) + '\n')
    failures = sum(row['status'] == 'FAIL' for row in RESULTS)
    print(f'{len(RESULTS) - failures}/{len(RESULTS)} PASS; transcripts: {LOG}', flush=True)
    return bool(failures)


if __name__ == '__main__':
    os.chdir(BASE)
    raise SystemExit(main())
