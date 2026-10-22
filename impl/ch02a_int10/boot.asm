; ch02a_int10/boot.asm - the first boot sector: "Hello, BIOS!" via INT 10h
;
; What happens before this code runs:
;   1. QEMU PC reset -> physical 0xFFFFFFF0 -> SeaBIOS (BIOS ROM)
;   2. SeaBIOS POST -> INT 19h bootstrap -> reads LBA 0 of drive A
;   3. Signature 0xAA55 OK -> loaded at 0x0000:0x7C00 -> far jump here
;
; This version prints through the BIOS video API (INT 10h AH=0Eh
; teletype), so the output appears on the VGA text screen: watch it
; with `make run-gui S=ch02a`. A headless `make run S=ch02a` shows
; nothing, because -display none throws the VGA output away.

cpu 8086
bits 16
org 0x7C00                      ; the BIOS loads us at 0x7C00

INT10H_TTY equ 0x0E             ; AH=0Eh: teletype output (write char, advance cursor)
TTY_PAGE   equ 0x00             ; BH: video page 0
TTY_COLOR  equ 0x07             ; BL: foreground color (used in graphics modes only)
TTY_ATTR   equ TTY_PAGE*0x100 + TTY_COLOR

    jmp short start             ; first byte 0xEB: real DOS floppies put the
start:                          ; BPB here, we keep the jump for make dump
    cld                         ; initialize forward string traversal
    xor ax, ax
    mov ds, ax                  ; DS = 0: our data is at physical 0x7Cxx
    mov ss, ax
    mov sp, 0x7C00              ; the stack grows down below the boot sector

    mov si, msg_hello
.print:
    lodsb                       ; AL = [DS:SI], SI++
    or al, al                   ; NUL terminator?
    jz .halt
    mov ah, INT10H_TTY
    mov bx, TTY_ATTR
    int 0x10                    ; BIOS video: teletype the char in AL
    jmp .print
.halt:
    cli
    hlt
    jmp .halt

msg_hello db "Hello, BIOS!", 13, 10, 0

times 510-($-$$) db 0           ; pad the boot sector to 510 bytes
dw 0xAA55                       ; boot signature (little endian: 55 AA in the image)
