cpu 8086
bits 16
global cmd_ls, cmd_load
extern fat_ls, fat_load, argc, argv, puts, put_crlf, put_hex_word
section .text
cmd_ls:
    call fat_ls
    jc load_error
    ret
cmd_load:
    cmp word [argc], 2
    jne bad_name
    mov si, [argv+2]
    call normalize
    jc bad_name
    mov si, fat_name
    mov di, 0x0600
    mov cx, 0x6A00             ; reserve 0x7000..0x7BFF for the stack
    call fat_load
    jc load_error
    push ax
    mov si, loaded
    call puts
    pop ax
    call put_hex_word
    call put_crlf
    ret
load_error:
    mov si, failed
    call puts
    call put_crlf
    ret
bad_name:
    mov si, invalid
    call puts
    call put_crlf
    ret

; Strict uppercase 8.3 conversion. Supported characters: A-Z, 0-9, _ and -.
; An optional extension must contain 1..3 characters. Reject paths/truncation.
normalize:
    mov di, fat_name
    mov cx, 11
    mov al, ' '
    rep stosb
    mov di, fat_name
    xor bx, bx
.base:
    lodsb
    or al, al
    jz .base_end
    cmp al, '.'
    je .extension
    cmp bx, 8
    jae .bad
    call character
    jc .bad
    stosb
    inc bx
    jmp .base
.base_end:
    or bx, bx
    jz .bad
    clc
    ret
.extension:
    or bx, bx
    jz .bad
    mov di, fat_name+8
    xor bx, bx
.ext:
    lodsb
    or al, al
    jz .ext_end
    cmp bx, 3
    jae .bad
    call character
    jc .bad
    stosb
    inc bx
    jmp .ext
.ext_end:
    or bx, bx
    jz .bad
    clc
    ret
.bad:
    stc
    ret
character:
    cmp al, 'a'
    jb .upper
    cmp al, 'z'
    ja .upper
    sub al, 32
.upper:
    cmp al, 'A'
    jb .digit
    cmp al, 'Z'
    jbe .ok
.digit:
    cmp al, '0'
    jb .symbol
    cmp al, '9'
    jbe .ok
.symbol:
    cmp al, '_'
    je .ok
    cmp al, '-'
    je .ok
    stc
    ret
.ok:
    clc
    ret
section .rodata
loaded db "loaded at 0x0600 bytes=0x",0
failed db "error: file missing, invalid chain, capacity or disk I/O",0
invalid db "error: expected load NAME[.EXT] (8.3)",0
section .bss
fat_name resb 11
