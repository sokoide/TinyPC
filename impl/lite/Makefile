NASM ?= nasm
QEMU ?= qemu-system-i386
QEMU_DISPLAY ?= $(shell if [ "$$(uname -s)" = Darwin ]; then echo "-display cocoa,zoom-to-fit=on"; fi)

.PHONY: all disk run clean
all: disk

boot.bin: boot.asm
	$(NASM) -f bin -o $@ $<

stage2.bin: stage2.asm
	$(NASM) -f bin -o $@ $<

disk: boot.bin stage2.bin
	test "$$(wc -c < stage2.bin)" -le 512
	dd if=/dev/zero of=disk.img bs=512 count=2880
	dd if=boot.bin of=disk.img conv=notrunc
	dd if=stage2.bin of=disk.img bs=512 seek=1 conv=notrunc

run: disk
	$(QEMU) $(QEMU_DISPLAY) -drive format=raw,file=disk.img,if=floppy

clean:
	rm -f boot.bin stage2.bin disk.img
