; ch02b_serial/boot.asm - "Hello, UART!" through COM1 (port I/O)
;
; Same boot flow as ch02a, but instead of calling the BIOS video API
; we drive the 16550 UART ourselves with in/out. This is direct device
; access through I/O ports - the CPU talks to the hardware, no BIOS in
; between. The serial output is visible in headless runs: make run S=ch02b.

cpu 8086
bits 16
org 0x7C00

COM1         equ 0x3F8          ; 16550 UART, COM1
UART_DATA    equ COM1 + 0       ; THR (write) / RBR (read)
UART_IER     equ COM1 + 1       ; interrupt enable (also DLM when DLAB=1)
UART_LCR     equ COM1 + 3       ; line control (also the DLAB switch)
UART_LSR     equ COM1 + 5       ; line status
LCR_8N1      equ 0x03           ; 8 data bits, no parity, 1 stop bit
LCR_DLAB     equ 0x80           ; divisor latch access bit
LSR_THRE     equ 0x20           ; transmit holding register empty
BAUD_DIVISOR equ 1              ; divisor 1 = 115200 baud

    jmp short start             ; first byte 0xEB: real DOS floppies put the
start:                          ; BPB here, we keep the jump for make dump
    cld                         ; initialize forward string traversal
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0x7C00

    call uart_init
    mov si, msg_hello
.print:
    lodsb
    or al, al                   ; NUL terminator?
    jz .halt
    call putchar
    jmp .print
.halt:
    cli
    hlt
    jmp .halt

; uart_init: COM1 at 115200 baud, 8N1, polling only (no interrupts)
uart_init:
    push ax
    push dx
    mov dx, UART_IER
    xor al, al
    out dx, al                  ; no UART interrupts
    mov dx, UART_LCR
    mov al, LCR_DLAB
    out dx, al                  ; DLAB=1: divisor registers visible
    mov dx, UART_DATA           ; DLL (low byte of the divisor)
    mov al, BAUD_DIVISOR & 0xFF
    out dx, al
    mov dx, UART_IER            ; DLM (high byte, only while DLAB=1)
    mov al, BAUD_DIVISOR >> 8
    out dx, al
    mov dx, UART_LCR
    mov al, LCR_8N1             ; DLAB=0, 8N1
    out dx, al
    pop dx
    pop ax
    ret

; putchar: AL = byte to send (AL preserved)
putchar:
    push dx
    push ax
    mov dx, UART_LSR
.wait:
    in al, dx
    test al, LSR_THRE           ; transmitter holding register empty?
    jz .wait
    mov dx, UART_DATA
    pop ax
    out dx, al
    pop dx
    ret

msg_hello db "Hello, UART!", 13, 10, 0

times 510-($-$$) db 0
dw 0xAA55
