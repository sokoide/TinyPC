; console.s - serial console routines on COM1 (16550)
;
; The kernel's only output channel. These are plain procedures called
; with call/ret - the C runtime equivalent of a libc subset.

cpu 8086
bits 16

global uart_init, putchar, puts, put_crlf, put_hex_byte, put_hex_word

COM1         equ 0x3F8
UART_DATA    equ COM1 + 0
UART_IER     equ COM1 + 1
UART_LCR     equ COM1 + 3
UART_LSR     equ COM1 + 5
LCR_8N1      equ 0x03
LCR_DLAB     equ 0x80
LSR_THRE     equ 0x20
BAUD_DIVISOR equ 1

section .text

; uart_init: COM1 at 115200 baud, 8N1, polling only
uart_init:
    push ax
    push dx
    mov dx, UART_IER
    xor al, al
    out dx, al                  ; no UART interrupts
    mov dx, UART_LCR
    mov al, LCR_DLAB
    out dx, al                  ; DLAB=1: divisor registers visible
    mov dx, UART_DATA           ; DLL
    mov al, BAUD_DIVISOR & 0xFF
    out dx, al
    mov dx, UART_IER            ; DLM
    mov al, BAUD_DIVISOR >> 8
    out dx, al
    mov dx, UART_LCR
    mov al, LCR_8N1
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
    test al, LSR_THRE
    jz .wait
    mov dx, UART_DATA
    pop ax
    out dx, al
    pop dx
    ret

; puts: DS:SI = NUL-terminated string
puts:
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

put_hex_byte:
    push ax
    push bx
    push cx
    mov bl, al
    mov cl, 4
    shr al, cl
    call put_hex_nibble
    mov al, bl
    and al, 0x0F
    call put_hex_nibble
    pop cx
    pop bx
    pop ax
    ret
put_hex_nibble:
    push bx
    mov bx, hex_table
    xlatb
    call putchar
    pop bx
    ret

put_hex_word:
    push ax
    mov al, ah
    call put_hex_byte
    pop ax
    call put_hex_byte
    ret

section .rodata
hex_table db "0123456789ABCDEF"
