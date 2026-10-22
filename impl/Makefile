NASM ?= nasm
LK ?= ld.lld
QEMU ?= qemu-system-i386
PYTHON ?= python3
TIMEOUT ?= 5
S ?= ch07
.DEFAULT_GOAL := all
DIR_ch02a = ch02a_int10
DIR_ch02b = ch02b_serial
DIR_ch03 = ch03_hook
DIR_ch04 = ch04_stage2
DIR_ch05 = ch05_kernel
DIR_ch06 = ch06_shell
DIR_ch07 = ch07_shellcmds
DIR_ch09 = ch09_fat12
D = $(DIR_$(S))
.PHONY: all run run-gui dump verify clean

ch02a_int10/boot.bin: ch02a_int10/boot.asm
	$(NASM) -f bin -l ch02a_int10/boot.lst -o $@ $<

ch02a_int10/ch02a_int10.img: ch02a_int10/boot.bin
	@dd if=/dev/zero of=$@ bs=512 count=2880 2>/dev/null
	@dd if=$< of=$@ conv=notrunc 2>/dev/null

ch02b_serial/boot.bin: ch02b_serial/boot.asm
	$(NASM) -f bin -l ch02b_serial/boot.lst -o $@ $<

ch02b_serial/ch02b_serial.img: ch02b_serial/boot.bin
	@dd if=/dev/zero of=$@ bs=512 count=2880 2>/dev/null
	@dd if=$< of=$@ conv=notrunc 2>/dev/null

ch03_hook/boot.bin: ch03_hook/boot.asm
	$(NASM) -f bin -l ch03_hook/boot.lst -o $@ $<

ch03_hook/ch03_hook.img: ch03_hook/boot.bin
	@dd if=/dev/zero of=$@ bs=512 count=2880 2>/dev/null
	@dd if=$< of=$@ conv=notrunc 2>/dev/null

ch04_stage2/boot.bin: ch04_stage2/boot.asm
	$(NASM) -f bin -l ch04_stage2/boot.lst -o $@ $<

ch04_stage2/stage2.bin: ch04_stage2/stage2.asm
	$(NASM) -f bin -o $@ $<
	@test "$$(wc -c < $@)" -le 16384

ch04_stage2/ch04_stage2.img: ch04_stage2/boot.bin ch04_stage2/stage2.bin
	@dd if=/dev/zero of=$@ bs=512 count=2880 2>/dev/null
	@dd if=$< of=$@ conv=notrunc 2>/dev/null
	@dd if=ch04_stage2/stage2.bin of=$@ bs=512 seek=1 conv=notrunc 2>/dev/null

ch05_kernel/boot.bin: ch05_kernel/boot.asm
	$(NASM) -f bin -l ch05_kernel/boot.lst -o $@ $<

ch05_kernel/crt0.o: ch05_kernel/crt0.s
	$(NASM) -f elf32 -l ch05_kernel/crt0.lst -o $@ $<

ch05_kernel/console.o: ch05_kernel/console.s
	$(NASM) -f elf32 -l ch05_kernel/console.lst -o $@ $<

ch05_kernel/main.o: ch05_kernel/main.s
	$(NASM) -f elf32 -l ch05_kernel/main.lst -o $@ $<

ch05_kernel/kernel.bin: ch05_kernel/crt0.o ch05_kernel/console.o ch05_kernel/main.o ch05_kernel/linker.ld
	$(LK) -m elf_i386 -T ch05_kernel/linker.ld -Map=ch05_kernel/kernel.map -o $@ ch05_kernel/crt0.o ch05_kernel/console.o ch05_kernel/main.o
	@test "$$(wc -c < $@)" -le 16384

ch05_kernel/ch05_kernel.img: ch05_kernel/boot.bin ch05_kernel/kernel.bin
	@dd if=/dev/zero of=$@ bs=512 count=2880 2>/dev/null
	@dd if=$< of=$@ conv=notrunc 2>/dev/null
	@dd if=ch05_kernel/kernel.bin of=$@ bs=512 seek=1 conv=notrunc 2>/dev/null

ch06_shell/boot.bin: ch06_shell/boot.asm
	$(NASM) -f bin -l ch06_shell/boot.lst -o $@ $<

ch06_shell/crt0.o: ch06_shell/crt0.s
	$(NASM) -f elf32 -l ch06_shell/crt0.lst -o $@ $<

ch06_shell/console.o: ch06_shell/console.s
	$(NASM) -f elf32 -l ch06_shell/console.lst -o $@ $<

ch06_shell/main.o: ch06_shell/main.s
	$(NASM) -f elf32 -l ch06_shell/main.lst -o $@ $<

ch06_shell/getline.o: ch06_shell/getline.s
	$(NASM) -f elf32 -l ch06_shell/getline.lst -o $@ $<

ch06_shell/cmd.o: ch06_shell/cmd.s
	$(NASM) -f elf32 -l ch06_shell/cmd.lst -o $@ $<

ch06_shell/kernel.bin: ch06_shell/crt0.o ch06_shell/console.o ch06_shell/main.o ch06_shell/getline.o ch06_shell/cmd.o ch06_shell/linker.ld
	$(LK) -m elf_i386 -T ch06_shell/linker.ld -Map=ch06_shell/kernel.map -o $@ ch06_shell/crt0.o ch06_shell/console.o ch06_shell/main.o ch06_shell/getline.o ch06_shell/cmd.o
	@test "$$(wc -c < $@)" -le 16384

ch06_shell/ch06_shell.img: ch06_shell/boot.bin ch06_shell/kernel.bin
	@dd if=/dev/zero of=$@ bs=512 count=2880 2>/dev/null
	@dd if=$< of=$@ conv=notrunc 2>/dev/null
	@dd if=ch06_shell/kernel.bin of=$@ bs=512 seek=1 conv=notrunc 2>/dev/null

ch07_shellcmds/boot.bin: ch07_shellcmds/boot.asm
	$(NASM) -f bin -l ch07_shellcmds/boot.lst -o $@ $<

ch07_shellcmds/crt0.o: ch07_shellcmds/crt0.s
	$(NASM) -f elf32 -l ch07_shellcmds/crt0.lst -o $@ $<

ch07_shellcmds/console.o: ch07_shellcmds/console.s
	$(NASM) -f elf32 -l ch07_shellcmds/console.lst -o $@ $<

ch07_shellcmds/main.o: ch07_shellcmds/main.s
	$(NASM) -f elf32 -l ch07_shellcmds/main.lst -o $@ $<

ch07_shellcmds/getline.o: ch07_shellcmds/getline.s
	$(NASM) -f elf32 -l ch07_shellcmds/getline.lst -o $@ $<

ch07_shellcmds/cmd.o: ch07_shellcmds/cmd.s
	$(NASM) -f elf32 -l ch07_shellcmds/cmd.lst -o $@ $<

ch07_shellcmds/strconv.o: ch07_shellcmds/strconv.s
	$(NASM) -f elf32 -l ch07_shellcmds/strconv.lst -o $@ $<

ch07_shellcmds/cmds2.o: ch07_shellcmds/cmds2.s
	$(NASM) -f elf32 -l ch07_shellcmds/cmds2.lst -o $@ $<

ch07_shellcmds/kernel.bin: ch07_shellcmds/crt0.o ch07_shellcmds/console.o ch07_shellcmds/main.o ch07_shellcmds/getline.o ch07_shellcmds/cmd.o ch07_shellcmds/strconv.o ch07_shellcmds/cmds2.o ch07_shellcmds/linker.ld
	$(LK) -m elf_i386 -T ch07_shellcmds/linker.ld -Map=ch07_shellcmds/kernel.map -o $@ ch07_shellcmds/crt0.o ch07_shellcmds/console.o ch07_shellcmds/main.o ch07_shellcmds/getline.o ch07_shellcmds/cmd.o ch07_shellcmds/strconv.o ch07_shellcmds/cmds2.o
	@test "$$(wc -c < $@)" -le 16384

ch07_shellcmds/ch07_shellcmds.img: ch07_shellcmds/boot.bin ch07_shellcmds/kernel.bin
	@dd if=/dev/zero of=$@ bs=512 count=2880 2>/dev/null
	@dd if=$< of=$@ conv=notrunc 2>/dev/null
	@dd if=ch07_shellcmds/kernel.bin of=$@ bs=512 seek=1 conv=notrunc 2>/dev/null

ch09_fat12/boot.bin: ch09_fat12/boot.asm
	$(NASM) -f bin -l ch09_fat12/boot.lst -o $@ $<

ch09_fat12/crt0.o: ch09_fat12/crt0.s
	$(NASM) -f elf32 -l ch09_fat12/crt0.lst -o $@ $<

ch09_fat12/console.o: ch09_fat12/console.s
	$(NASM) -f elf32 -l ch09_fat12/console.lst -o $@ $<

ch09_fat12/main.o: ch09_fat12/main.s
	$(NASM) -f elf32 -l ch09_fat12/main.lst -o $@ $<

ch09_fat12/getline.o: ch09_fat12/getline.s
	$(NASM) -f elf32 -l ch09_fat12/getline.lst -o $@ $<

ch09_fat12/cmd.o: ch09_fat12/cmd.s
	$(NASM) -f elf32 -l ch09_fat12/cmd.lst -o $@ $<

ch09_fat12/strconv.o: ch09_fat12/strconv.s
	$(NASM) -f elf32 -l ch09_fat12/strconv.lst -o $@ $<

ch09_fat12/cmds2.o: ch09_fat12/cmds2.s
	$(NASM) -f elf32 -l ch09_fat12/cmds2.lst -o $@ $<

ch09_fat12/cmd_fat.o: ch09_fat12/cmd_fat.s
	$(NASM) -f elf32 -l ch09_fat12/cmd_fat.lst -o $@ $<

ch09_fat12/fat12.o: common/fat12.s
	$(NASM) -f elf32 -l ch09_fat12/fat12.lst -o $@ $<

ch09_fat12/kernel.bin: ch09_fat12/crt0.o ch09_fat12/console.o ch09_fat12/main.o ch09_fat12/getline.o ch09_fat12/cmd.o ch09_fat12/strconv.o ch09_fat12/cmds2.o ch09_fat12/cmd_fat.o ch09_fat12/fat12.o ch09_fat12/linker.ld
	$(LK) -m elf_i386 -T ch09_fat12/linker.ld -Map=ch09_fat12/kernel.map -o $@ ch09_fat12/crt0.o ch09_fat12/console.o ch09_fat12/main.o ch09_fat12/getline.o ch09_fat12/cmd.o ch09_fat12/strconv.o ch09_fat12/cmds2.o ch09_fat12/cmd_fat.o ch09_fat12/fat12.o
	@test "$$(wc -c < $@)" -le 16384

ch09_fat12/loader.o: ch09_fat12/loader.s
	$(NASM) -f elf32 -o $@ $<

ch09_fat12/loader.bin: ch09_fat12/loader.o ch09_fat12/console.o ch09_fat12/fat12.o ch09_fat12/loader.ld
	$(LK) -m elf_i386 -T ch09_fat12/loader.ld -Map=ch09_fat12/loader.map -o $@ ch09_fat12/loader.o ch09_fat12/console.o ch09_fat12/fat12.o
	@test "$$(wc -c < $@)" -le 3584

ch09_fat12/ch09_fat12.img: ch09_fat12/boot.bin ch09_fat12/kernel.bin ch09_fat12/loader.bin mkfat12.py
	$(PYTHON) mkfat12.py ch09_fat12/boot.bin ch09_fat12/loader.bin ch09_fat12/kernel.bin $@

all: ch02a_int10/ch02a_int10.img ch02b_serial/ch02b_serial.img ch03_hook/ch03_hook.img ch04_stage2/ch04_stage2.img ch05_kernel/ch05_kernel.img ch06_shell/ch06_shell.img ch07_shellcmds/ch07_shellcmds.img ch09_fat12/ch09_fat12.img

run: $(D)/$(D).img
	@test -n "$(D)" || { echo "unknown scenario: $(S)"; exit 1; }
	@timeout --foreground $(TIMEOUT) $(QEMU) -drive file=$<,format=raw,if=floppy -serial stdio -display none -monitor none -no-reboot; rc=$$?; test $$rc -eq 0 -o $$rc -eq 124

run-gui: $(D)/$(D).img
	$(QEMU) -drive file=$<,format=raw,if=floppy -serial stdio -no-reboot

dump: $(D)/$(D).img
	ndisasm -b 16 -o 0x7C00 $(D)/boot.bin
	@if test -f $(D)/kernel.bin; then ndisasm -b 16 -o 0x8000 $(D)/kernel.bin; fi
	@if test -f $(D)/stage2.bin; then ndisasm -b 16 -o 0x8000 $(D)/stage2.bin; fi

verify: all
	$(PYTHON) verify.py --qemu $(QEMU) --nasm $(NASM) --linker $(LK)

clean:
	$(PYTHON) -c 'from pathlib import Path; [f.unlink() for d in Path(".").glob("ch*") if d.is_dir() for f in d.iterdir() if f.suffix in {".bin", ".img", ".o", ".lst", ".map"}]'
