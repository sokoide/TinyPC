; cmds2.s - memory / machine inspection commands (ch07)
;
; All commands read argc/argv prepared by run_cmd in cmd.s
; (argv[0] is the command name, so argv[1] is the first argument).

cpu 8086
bits 16

global cmd_peek, cmd_dump, cmd_poke, cmd_ivt, cmd_mem, cmd_ticks
global cmd_vga, cmd_reboot
extern putchar, puts, put_crlf, put_hex_byte, put_hex_word, put_hex, parse_hex
extern argc, argv

DUMP_ROW  equ 16              ; bytes per dump line
BDA_TICKS equ 0x046C          ; BIOS Data Area: timer ticks since midnight
KBC_CMD   equ 0x64            ; 8042 keyboard controller command port
KBC_RESET equ 0xFE            ; command "pulse the CPU reset line"

section .text

; usage: print "usage: " + SI + CRLF
usage:
    push si
    mov si, msg_usage
    call puts
    pop si
    call puts
    call put_crlf
    ret

bad_addr:                     ; print "error: bad address" + CRLF
    mov si, msg_badaddr
    call puts
    call put_crlf
    ret

; Note on 8086 jumps: bad_addr sits far below the commands, and an 8086
; conditional jump only reaches +/-127 bytes. So every argument check
; uses an inverted short Jcc plus a plain `jmp bad_addr`.
; `cmp reg, imm16` / `test` are used instead of `cmp word [mem], imm8`,
; which NASM would encode as opcode 83h (also valid on 8086).

; peek ADDR - read one byte and print it
cmd_peek:
    mov ax, [argc]              ; need 1 argument (8086 cmp form: reg,imm16)
    cmp ax, strict word 2
    jae .go
    mov si, msg_peek_usage
    call usage
    ret
.go:
    mov si, [argv+2]
    call parse_hex
    or dx, dx
    jnz .ok
    jmp bad_addr
.ok:
    xor dx, dx                  ; put_hex prints DX:AX; DX was only parse_hex's ok flag
    push ax
    call put_hex               ; "0x00007C00"
    mov al, ':'
    call putchar
    mov al, ' '
    call putchar
    pop ax
    mov bx, ax
    mov al, [bx]               ; DS = 0, so [BX] is physical 0x0000:addr
    call put_hex_byte
    call put_crlf
    ret

; dump ADDR [N] - print N bytes, 16 per line
cmd_dump:
    mov ax, [argc]
    cmp ax, strict word 2
    jae .go
    mov si, msg_dump_usage
    call usage
    ret
.go:
    mov si, [argv+2]
    call parse_hex
    or dx, dx
    jnz .ok
    jmp bad_addr
.ok:
    mov [dump_addr], ax
    mov word [dump_left], DUMP_ROW
    mov ax, [argc]
    cmp ax, strict word 3      ; strict: 8086 imm16 form
    jb .rowloop
    mov si, [argv+4]
    call parse_hex
    or dx, dx
    jnz .ok2
    jmp bad_addr
.ok2:
    mov [dump_left], ax
.rowloop:
    mov ax, [dump_left]
    test ax, ax
    jnz .row
    ret                        ; dumped the requested number of bytes
.row:
    mov ax, [dump_addr]
    xor dx, dx
    call put_hex               ; "0x%08X:"
    mov al, ':'
    call putchar
    mov al, ' '
    call putchar
    mov ax, DUMP_ROW
    cmp ax, [dump_left]
    jbe .setrow
    mov ax, [dump_left]
.setrow:
    mov [dump_rowlen], ax
.rowbyte:
    mov ax, [dump_rowlen]
    test ax, ax
    jz .endrow
    mov bx, [dump_addr]
    mov al, [bx]
    call put_hex_byte
    mov al, ' '
    call putchar
    inc word [dump_addr]
    dec word [dump_left]
    dec word [dump_rowlen]
    jmp .rowbyte
.endrow:
    call put_crlf
    jmp .rowloop

; poke ADDR VAL - write one byte
cmd_poke:
    mov ax, [argc]
    cmp ax, strict word 3
    jae .go
    mov si, msg_poke_usage
    call usage
    ret
.go:
    mov si, [argv+2]
    call parse_hex
    or dx, dx
    jnz .ok
    jmp bad_addr
.ok:
    mov bx, ax                 ; parse_hex preserves BX, so BX = address
    mov si, [argv+4]
    call parse_hex
    or dx, dx
    jnz .ok2
    jmp bad_addr
.ok2:
    cmp ax, 0xFF
    jbe .byte_ok
    jmp bad_addr
.byte_ok:
    mov [bx], al
    mov dl, al                 ; save the value: puts clobbers AL (lodsb)
    mov si, msg_poke_ok
    call puts
    mov al, dl
    call put_hex_byte          ; the value written
    mov si, msg_at
    call puts
    mov ax, bx
    xor dx, dx
    call put_hex
    call put_crlf
    ret

; ivt N - print interrupt vector N as "INT NNh -> SEGM:OFFS"
cmd_ivt:
    mov ax, [argc]
    cmp ax, strict word 2
    jae .go
    mov si, msg_ivt_usage
    call usage
    ret
.go:
    mov si, [argv+2]
    call parse_hex
    or dx, dx
    jnz .ok
    jmp bad_addr
.ok:
    cmp ax, 0xFF
    jbe .vector_ok
    jmp bad_addr
.vector_ok:
    mov dx, ax                 ; save the vector number: puts clobbers AL (lodsb)
    mov si, msg_int
    call puts
    mov al, dl
    call put_hex_byte          ; vector number, e.g. "10" (leaves AX changed)
    mov ax, dx                 ; restore the full vector for the shift
    mov si, msg_arrow
    call puts
    shl dx, 1                  ; DX = N*4: shift by 1 twice (8086 allows only
    shl dx, 1                  ; shift counts of 1 or CL)
    mov bx, dx
    mov ax, [bx+2]             ; segment part (higher address)
    call put_hex_word
    mov al, ':'
    call putchar
    mov ax, [bx]               ; offset part
    call put_hex_word
    call put_crlf
    ret

; mem - conventional memory size through INT 12h
cmd_mem:
    int 0x12                   ; AX = KB of conventional memory
    push ax
    mov si, msg_mem
    call puts
    pop ax
    call put_hex_word
    mov si, msg_kb
    call puts
    call put_crlf
    ret

; ticks - BDA timer tick counter (dword at 0x0046C)
cmd_ticks:
    mov si, msg_ticks
    call puts
    mov ax, [BDA_TICKS]        ; low word
    mov dx, [BDA_TICKS+2]      ; high word
    call put_hex
    call put_crlf
    ret

; vga MSG ... - teletype MSG to the VGA text screen via INT 10h
; (invisible in headless runs: use make run-gui S=ch07)
cmd_vga:
    mov ax, [argc]
    cmp ax, strict word 2
    jae .go
    mov si, msg_vga_usage
    call usage
    ret
.go:
    mov cx, [argc]
    dec cx                     ; number of words after "vga"
    mov bx, argv + 2
.arg:
    mov si, [bx]
.char:
    lodsb
    or al, al
    jz .nextarg
    push bx
    mov ah, 0x0E               ; INT 10h AH=0Eh: teletype output
    mov bx, 0x0007             ; BH = page 0, BL = color (text mode ignores it)
    int 0x10
    pop bx
    jmp .char
.nextarg:
    add bx, strict word 2
    dec cx
    jz .note
    push bx
    mov ax, 0x0E00 + ' '       ; AH=0Eh, AL=space: separator on the VGA screen
    mov bx, 0x0007
    int 0x10
    pop bx
    jmp .arg
.note:
    mov si, msg_vga_note
    call puts
    call put_crlf
    ret

; reboot - 8042 keyboard controller reset pulse; with -no-reboot QEMU exits
cmd_reboot:
    mov si, msg_reboot
    call puts
    mov al, KBC_RESET
    out KBC_CMD, al            ; pulse the CPU reset line
.hang:
    hlt                        ; reset happens immediately; just in case
    jmp .hang

section .bss
dump_addr   resw 1
dump_left   resw 1
dump_rowlen resw 1

section .rodata
msg_usage      db "usage: ", 0
msg_badaddr    db "error: bad address", 0
msg_peek_usage db "peek ADDR", 0
msg_dump_usage db "dump ADDR [N]", 0
msg_poke_usage db "poke ADDR VAL", 0
msg_ivt_usage  db "ivt N", 0
msg_vga_usage  db "vga MSG ...", 0
msg_poke_ok    db "poke: wrote 0x", 0
msg_at         db " at ", 0
msg_int        db "INT ", 0
msg_arrow      db "h -> ", 0
msg_mem        db "mem: 0x", 0
msg_kb         db " KB", 0
msg_ticks      db "ticks: ", 0
msg_vga_note   db "(vga: printed to the VGA text screen; make run-gui S=ch07 shows it)", 0
msg_reboot     db "rebooting: 8042 reset pulse (port 0x64 <- 0xFE)", 13, 10, 0
