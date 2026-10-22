; ch04_stage2/stage2.asm - the first code loaded from disk
;
; Built as a flat binary (nasm -f bin) and written to LBA 1 by the
; Makefile. boot.asm reads it to 0x0000:0x8000 with INT 13h and does a
; far jump there, so CS:IP = 0x0000:0x8000 and org 0x8000 matches.

cpu 8086
bits 16
org 0x8000

COM1         equ 0x3F8
UART_DATA    equ COM1 + 0
UART_IER     equ COM1 + 1
UART_LCR     equ COM1 + 3
UART_LSR     equ COM1 + 5
LCR_8N1      equ 0x03
LCR_DLAB     equ 0x80
LSR_THRE     equ 0x20
BAUD_DIVISOR equ 1

stage2_start:
    cld                         ; initialize forward string traversal
    xor ax, ax
    mov ds, ax                  ; CS is already 0 (far jump from boot.asm);
    mov ss, ax                  ; set up our own DS/SS anyway so this code
    mov sp, 0x7C00              ; does not depend on the boot sector

    mov si, msg_hello
    call puts
.halt:
    cli
    hlt
    jmp .halt

uart_init:
    push ax
    push dx
    mov dx, UART_IER
    xor al, al
    out dx, al
    mov dx, UART_LCR
    mov al, LCR_DLAB
    out dx, al
    mov dx, UART_DATA
    mov al, BAUD_DIVISOR & 0xFF
    out dx, al
    mov dx, UART_IER
    mov al, BAUD_DIVISOR >> 8
    out dx, al
    mov dx, UART_LCR
    mov al, LCR_8N1
    out dx, al
    pop dx
    pop ax
    ret

putchar:
    push dx
    push ax
    mov dx, UART_LSR
.wait:
    in al, dx
    test al, LSR_THRE
    jz .wait
    mov dx, UART_DATA
    pop ax
    out dx, al
    pop dx
    ret

puts:
    lodsb
    or al, al
    jz .done
    call putchar
    jmp puts
.done:
    ret

msg_hello db "stage2: hello from LBA 1, running at 0x0000:0x8000", 13, 10, 0
