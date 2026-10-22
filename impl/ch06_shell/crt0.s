; crt0.s - startup code: set segments, clear .bss, call main
;
; The linker script places this file first, so _start lands exactly at
; 0x8000 where boot.asm jumps. "Who calls main?" - crt0 does.

cpu 8086
bits 16

global _start
extern main
extern uart_init
extern __bss_start
extern __bss_end

STACK_TOP equ 0x7C00            ; stack grows down below the boot sector

section .text
_start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax                  ; ES:DI is the .bss clear target
    mov ss, ax
    mov sp, STACK_TOP
    sti

    call uart_init

    ; clear .bss: [__bss_start, __bss_end) - both symbols come from linker.ld
    mov di, __bss_start
    mov cx, __bss_end
    sub cx, di
    xor al, al
    cld                         ; do not rely on incoming DF
    rep stosb

    call main
.halt:
    hlt
    jmp .halt
