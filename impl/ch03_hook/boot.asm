; ch03_hook/boot.asm - INT/IVT experiments in a boot sector
;
;   (1) Overwrite IVT[0x28] with our own handler and raise INT 0x28:
;       the IVT is just a RAM table, and anyone can register into it.
;   (2) Read IVT[0x10]: the INT 10h video handler that the BIOS itself
;       installed at boot (F000:xxxx points into the BIOS ROM).
;   (3) Wait for keys with INT 16h AH=00h. This works in `make run-gui`;
;       a headless run just sits here until the timeout kills QEMU.

cpu 8086
bits 16
org 0x7C00

; --- IVT layout: entry N is at N*4 (offset word, then segment word) ---
VEC_CUSTOM equ 0x28            ; our playground vector
VEC_VIDEO  equ 0x10            ; BIOS video services
KEY_ESC    equ 0x1B            ; ASCII code that ends the key demo

; --- COM1 16550 UART (same constants as ch02b) ---
COM1         equ 0x3F8
UART_DATA    equ COM1 + 0
UART_IER     equ COM1 + 1
UART_LCR     equ COM1 + 3
UART_LSR     equ COM1 + 5
LCR_8N1      equ 0x03
LCR_DLAB     equ 0x80
LSR_THRE     equ 0x20
BAUD_DIVISOR equ 1

    jmp short start             ; first byte 0xEB: real DOS floppies put the
start:                          ; BPB here, we keep the jump for make dump
    cld                         ; initialize forward string traversal
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0x7C00

    call uart_init
    mov si, msg_banner
    call puts

    ; --- (1) register our own INT 0x28 handler ---
    mov word [VEC_CUSTOM*4], int28_handler     ; offset part of IVT[0x28]
    mov ax, ds                                 ; our code lives at 0x0000:0x7Cxx
    mov word [VEC_CUSTOM*4 + 2], ax            ; segment part

    mov cx, 3                 ; raise INT 0x28 three times
.int28:
    int 0x28                  ; the handler prints '!'
    loop .int28
    call put_crlf

    ; --- (2) show the video vector the BIOS installed ---
    mov si, msg_ivt
    call puts
    mov ax, [VEC_VIDEO*4 + 2]                  ; segment part of IVT[0x10]
    call put_hex_word
    mov al, ':'
    call putchar
    mov ax, [VEC_VIDEO*4]                      ; offset part
    call put_hex_word
    call put_crlf

    ; --- (3) key input through INT 16h (GUI only) ---
    mov si, msg_key
    call puts
.key:
    mov ah, 0x00
    int 0x16                  ; wait for a key: AL = ASCII, AH = scan code
    mov dx, ax                ; keep the key in DX while printing
    mov si, msg_keyscan
    call puts
    mov al, dh
    call put_hex_byte         ; scan code
    mov si, msg_keyascii
    call puts
    mov al, dl
    call put_hex_byte         ; ASCII code
    cmp dl, 0x20              ; printable?
    jb .noprt
    cmp dl, 0x7F
    jae .noprt
    mov si, msg_keychar
    call puts
    mov al, dl
    call putchar
    mov al, 0x27              ; closing quote
    call putchar
.noprt:
    call put_crlf
    cmp dl, KEY_ESC
    jne .key

    mov si, msg_bye
    call puts
.halt:
    cli
    hlt
    jmp .halt

; --- INT 0x28 handler: print '!' and return with iret ---
int28_handler:
    push ax
    mov al, '!'
    call putchar
    pop ax
    iret

; ---- serial console helpers ----

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

puts:                         ; DS:SI = NUL-terminated string
    lodsb
    or al, al
    jz .done
    call putchar
    jmp puts
.done:
    ret

put_crlf:
    push ax
    mov al, 13
    call putchar
    mov al, 10
    call putchar
    pop ax
    ret

put_hex_byte:                 ; AL as two hex digits (AX preserved)
    push ax
    push cx
    mov cl, 4
    shr al, cl
    call put_hex_nibble
    pop cx
    pop ax
    and al, 0x0F
    ; fall through
put_hex_nibble:
    push bx
    mov bx, hex_table
    xlatb                     ; AL = hex_table[AL]
    call putchar
    pop bx
    ret

put_hex_word:                 ; AX as four hex digits (AX preserved)
    push ax
    mov al, ah
    call put_hex_byte
    pop ax
    call put_hex_byte
    ret

; ---- data ----
msg_banner   db "ch03: IVT hook demo", 13, 10, 0
msg_ivt      db "INT 10h -> ", 0
msg_key      db "key demo: press keys (ESC quits) - needs make run-gui", 13, 10, 0
msg_keyscan  db "key: scan=", 0
msg_keyascii db " ascii=", 0
msg_keychar  db " '", 0
msg_bye      db "bye", 13, 10, 0
hex_table    db "0123456789ABCDEF"

times 510-($-$$) db 0
dw 0xAA55
