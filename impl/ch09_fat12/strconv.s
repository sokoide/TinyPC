; strconv.s - hex string parsing and address printing (ch07)
;
; parse_hex is the "atoi" of this shell: it turns "0x7C00" into AX.
; put_hex prints a segment:offset pair as one 20-bit style "0x%08X"
; number, e.g. put_hex(0x0000, 0x7C00) -> "0x00007C00".

cpu 8086
bits 16

global parse_hex, put_hex
extern putchar, put_hex_word

section .text

parse_hex:
    push bx
    push cx
    xor ax, ax
    xor dx, dx
    cmp byte [si], '0'
    jne .digit
    cmp byte [si+1], 'x'
    je .skip
    cmp byte [si+1], 'X'
    jne .digit
.skip:
    add si, 2
.digit:
    mov bl, [si]
    or bl, bl
    jz .done
    cmp bl, '0'
    jb .bad
    cmp bl, '9'
    jbe .decimal
    or bl, 0x20
    cmp bl, 'a'
    jb .bad
    cmp bl, 'f'
    ja .bad
    sub bl, 'a'-10
    jmp .shift
.decimal:
    sub bl, '0'
.shift:
    test ax, 0xF000
    jnz .bad
    mov cl, 4
    shl ax, cl
    or al, bl
    mov dx, 1
    inc si
    jmp .digit
.bad:
    xor dx, dx
.done:
    pop cx
    pop bx
    ret

; put_hex: print DX:AX as "0x%08X", e.g. put_hex(0, 0x7C00) -> "0x00007C00"
put_hex:
    push ax
    push dx
    mov al, '0'
    call putchar
    mov al, 'x'
    call putchar
    pop dx
    mov ax, dx
    call put_hex_word
    pop ax
    call put_hex_word
    ret
