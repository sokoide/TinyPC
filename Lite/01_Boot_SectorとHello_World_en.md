---
title: "TinyPC Lite: Boot Sector and Hello World"
type: chapter
topic: 情報・コンピュータ
collection: TinyPC Lite
chapter: 01
created: 2026-10-12
updated: 2026-10-22
tags: [8086, BIOS, boot, NASM, 教材]
---

# 01 Boot Sector and Hello World

SeaBIOS loads the first sector of a bootable device at `0x7C00` and transfers control to it. This course places the signature `0xAA55` (the bytes `55 AA`) at the end of the sector. We begin by calling the BIOS video service, INT 10h, to display a message from the 512-byte boot sector.

`bits 16` tells NASM to assemble 16-bit code. `org 0x7C00` sets the address NASM assumes when calculating label values. `0000:7C00` refers to physical address `0x7C00`. See the full course chapter [[../01_8086とリアルモードの基礎]] for details on segments.

## boot.asm

In Chapter 1, save the following as `boot.asm` in an empty working directory. The distributed [boot.asm](../impl/lite/boot.asm) is the completed version for Chapter 2, so do not use it to overwrite this version yet.

```asm
bits 16                       ; Tell NASM to generate 16-bit machine code (not a CPU instruction)
org 0x7C00                    ; Calculate labels assuming the code will be placed at RAM address 0x7C00

start:
    cli                       ; Disable maskable external interrupts (this does not disable INT instructions)
    cld                       ; Clear the direction flag (DF); LODSB will then increment SI after reading
    xor ax, ax                ; Set AX to zero; XORing a value with itself produces zero
    mov ss, ax                ; Set SS to 0; the stack segment base is physical address 0
    mov sp, 0x7C00            ; Initial stack position; PUSH and INT use memory below this address
    mov ds, ax                ; Set DS to 0; physical addresses for data are DS×16 plus the offset
    sti                       ; Enable external interrupts after setting SS:SP
    mov si, message           ; Put the message's starting offset in SI; DS:SI points to its first byte
.next:
    lodsb                     ; Read one byte from DS:SI into AL; with DF=0, increment SI to the next byte
    test al, al               ; Check whether AL is zero by setting ZF; AL itself is unchanged
    jz .halt                  ; If AL=0 (the string terminator), stop displaying and halt
    mov ah, 0x0E              ; Select BIOS video function 0Eh to display the character in AL
    mov bx, 0x0007            ; BH=0 selects display page 0; BL=7 is used in graphics modes, not here
    int 0x10                  ; Call the BIOS video service; AH=0Eh displays the character in AL
    jmp .next                 ; Return to the start of the loop to read the next character
.halt:
    cli                       ; Disable maskable external interrupts (this does not disable INT instructions)
.wait:
    hlt                       ; Put the CPU in a wait state; this does not exit QEMU
    jmp .wait                 ; If the CPU resumes, return to HLT and wait again

message db 'Booting...', 13, 10, 0 ; Store the message, carriage return (13), line feed (10), and loop terminator (0)
times 510-($-$$) db 0         ; Fill the remaining bytes up to byte 510 with zeros; $-$$ is the current section size
dw 0xAA55                     ; Store the two-byte signature; little-endian encoding puts 55 AA in the file
```

### How `cld` and `lodsb` work together

`cld` (Clear Direction Flag) sets the CPU's direction flag, DF, to 0. It does not change SI. DF determines which direction string instructions such as `lodsb` move through memory.

| DF value | What `lodsb` does |
| :--- | :--- |
| 0 (set by `cld`) | Read one byte from `DS:SI` into AL, then add 1 to SI |
| 1 (set by `std`) | Read one byte from `DS:SI` into AL, then subtract 1 from SI |

For example, with `message db 'ABC', 0`, `mov si, message` points to the first character. Repeating `lodsb` with DF=0 reads `A`, then `B`, then `C`, then `0`. With DF=1, after reading `A`, SI would move to the byte before the string. We execute `cld` first so the code does not depend on the DF value left by the BIOS.

INT 10h with `AH=0Eh` writes the single character in `AL` to the text display. Our own loop processes one character at a time until it reaches the null terminator; INT 10h does not process the whole string. The internals of what the CPU does during an interrupt are covered in Chapter 03 of the full course; here, we use it as a BIOS API.

`times` pads the sector before the signature so the total size is 512 bytes. Because x86 is little-endian, `dw 0xAA55` places the bytes `55 AA` at the end of the file.

## Build and check the display

Use the same working directory through Chapter 2. This example creates `tinypc-lite-work` in your home directory.

```sh
mkdir -p ~/tinypc-lite-work
cd ~/tinypc-lite-work
# Save the code above as boot.asm
nasm -f bin boot.asm -o boot.bin
wc -c < boot.bin
od -An -tx1 -j 510 -N 2 boot.bin
```

The output should be `512` and `55 aa`, confirming the size and signature. Next, create a virtual floppy and boot it:

```sh
dd if=/dev/zero of=disk.img bs=512 count=2880
dd if=boot.bin of=disk.img conv=notrunc
qemu-system-i386 -boot a -drive format=raw,file=disk.img,if=floppy
```

Success: `Booting...` appears in the QEMU window. The program stops after printing because it does not start an operating system. Close the QEMU window to exit.

### Five-minute exercise: display your own message

Replace `Booting...` with any English text, then rerun `nasm`, both `dd` commands, and QEMU. Saving the source does not update the disk image by itself. Displaying Japanese text is outside the scope of this BIOS output example.

### The minimum background needed to read the code

- Registers are small storage locations inside the CPU. The upper 8 bits of `AX` are `AH`, and the lower 8 bits are `AL`. `mov` copies a value; `xor ax, ax` sets AX to zero.
- `DS:SI` identifies the location of a character. In real mode, the physical address is `DS × 16 + SI`. Here DS is zero, so SI is the physical address.
- `cld` clears the direction flag so `lodsb` increments SI. Do not assume a particular flag value at startup.
- `SS:SP` identifies the stack. `int` also saves return information on the stack, so this code initializes it. The stack grows toward lower addresses from `0x7C00`.
- `13, 10` mean carriage return and line feed. The final `0` ends our own string loop; INT 10h does not consume a whole string.
- `bits 16` and `org` are NASM directives, not instructions executed by the CPU. `org` neither loads data nor changes the CPU's execution mode.
- `$-$$` is the number of bytes emitted in this section so far. `times 510-($-$$)` pads the sector before the signature. NASM reports an error if code and data exceed 510 bytes.

`hlt` puts the CPU into a wait state; it does not exit QEMU. `cli` disables maskable external interrupts, but does not disable software interrupts such as `int 0x10`.
