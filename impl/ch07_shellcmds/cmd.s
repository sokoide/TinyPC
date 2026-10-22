; cmd.s - shell core: prompt, tokenizing, jump-table dispatch (ch06)
;
; The line is tokenized in place (spaces become NUL) into argv/argc,
; then cmd_table - an array of {name, handler} pairs, the asm
; equivalent of a C function pointer table - picks the handler.
; ch07 extends cmd_table with the commands from cmds2.s.

cpu 8086
bits 16

global shell_main
global argc, argv              ; cmds2.s (ch07) reads these
extern cmd_peek, cmd_dump, cmd_poke, cmd_ivt, cmd_mem, cmd_ticks, cmd_vga, cmd_reboot
extern getline, putchar, puts, put_crlf

LINEBUF_SIZE equ 64
MAX_ARGS     equ 8

section .text

; shell_main: prompt / read / dispatch, forever ('q' halts the machine)
shell_main:
    mov si, msg_prompt
    call puts
    mov di, linebuf
    mov cx, LINEBUF_SIZE
    call getline
    mov di, linebuf
    call run_cmd
    jmp shell_main

; run_cmd: DI = line buffer, tokenized in place
run_cmd:
    xor cx, cx                  ; CX = argc
    mov si, di                  ; SI = line buffer
    mov di, argv                ; DI = &argv[i]
.token:
    mov al, [si]
    cmp al, ' '
    jne .tok_start
    inc si
    jmp .token
.tok_start:
    cmp al, 0
    je .tokenized
    cmp cx, MAX_ARGS
    jb .room
    mov si, msg_toomany
    call puts
    call put_crlf
    ret
.room:
    mov [di], si                ; argv[i] = token start
    add di, strict word 2      ; force imm16 for consistent listings; imm8 is also valid on 8086
    inc cx
.scan:
    mov al, [si]
    cmp al, 0
    je .tokenized
    cmp al, ' '
    je .cut
    inc si
    jmp .scan
.cut:
    mov byte [si], 0            ; end the token inside the line buffer
    inc si
    jmp .token
.tokenized:
    mov [argc], cx
    jcxz .ret                   ; empty line: nothing to do
    ; dispatch: linear scan of cmd_table for argv[0]
    mov si, cmd_table
.find:
    mov dx, [si]                ; name pointer, 0 = end of table
    or dx, dx
    jz .unknown
    push si
    mov di, dx
    mov si, [argv]
    call strcmp
    pop si
    cmp al, 1
    je .hit
    add si, strict word 4      ; next {name, handler} pair (8086 imm16 form)
    jmp .find
.hit:
    mov ax, [si+2]
    call ax                     ; 8086: call through register
.ret:
    ret
.unknown:
    mov si, msg_unknown
    call puts
    mov si, [argv]
    call puts
    call put_crlf
    ret

; strcmp: DS:SI vs DS:DI -> AL = 1 if equal, 0 if not
strcmp:
    push si
    push di
.loop:
    mov al, [si]
    cmp al, [di]
    jne .diff
    or al, al
    jz .same
    inc si
    inc di
    jmp .loop
.same:
    mov al, 1
    jmp .out
.diff:
    mov al, 0
.out:
    pop di
    pop si
    ret

; ---- ch06 commands ----

cmd_help:
    mov si, msg_help
    call puts
    mov si, cmd_table
.next:
    mov dx, [si]
    or dx, dx
    jz .end
    push si
    mov al, ' '
    call putchar
    mov si, dx
    call puts
    pop si
    add si, strict word 4
    jmp .next
.end:
    call put_crlf
    ret

cmd_echo:                       ; print argv[1..] separated by spaces
    mov cx, [argc]
    dec cx
    jz .newline
    mov bx, argv + 2
.arg:
    mov si, [bx]
    call puts
    add bx, strict word 2
    loop .sep
    jmp .newline
.sep:
    mov al, ' '
    call putchar
    jmp .arg
.newline:
    call put_crlf
    ret

cmd_cls:                        ; ANSI clear screen
    mov si, msg_cls
    call puts
    ret

cmd_q:                          ; quit: say bye and halt the CPU
    mov si, msg_bye
    call puts
    call put_crlf
.halt:
    cli
    hlt
    jmp .halt

section .rodata
msg_toomany db "error: too many arguments", 0
msg_prompt  db "> ", 0
msg_help    db "commands:", 0
msg_unknown db "unknown: ", 0
msg_bye     db "bye", 0
msg_cls     db 27, "[2J", 27, "[H", 0

cmd_table:                      ; {name pointer, handler} pairs
    dw name_help, cmd_help
    dw name_echo, cmd_echo
    dw name_cls,  cmd_cls
    dw name_q,    cmd_q
    dw name_peek, cmd_peek
    dw name_dump, cmd_dump
    dw name_poke, cmd_poke
    dw name_ivt, cmd_ivt
    dw name_mem, cmd_mem
    dw name_ticks, cmd_ticks
    dw name_vga, cmd_vga
    dw name_reboot, cmd_reboot
    dw 0, 0
name_peek db "peek", 0
name_dump db "dump", 0
name_poke db "poke", 0
name_ivt db "ivt", 0
name_mem db "mem", 0
name_ticks db "ticks", 0
name_vga db "vga", 0
name_reboot db "reboot", 0
name_help db "help", 0
name_echo db "echo", 0
name_cls  db "cls", 0
name_q    db "q", 0

section .bss
linebuf resb LINEBUF_SIZE
argv    resw MAX_ARGS
argc    resw 1
