cpu 8086
bits 16
global _start
extern fat_init, fat_load, uart_init, puts
extern __bss_start, __bss_end
section .text
_start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    cld
    push dx
    mov di, __bss_start
    mov cx, __bss_end
    sub cx, di
    rep stosb
    pop dx
    sti
    call uart_init
    call fat_init
    jc failure
    mov si, loading
    call puts
    mov si, kernel_name
    mov di, 0x8000
    mov cx, 0x4000
    call fat_load
    jc failure
    or ax, ax
    jz failure
    mov dl, [0x7C24]
    jmp 0:0x8000
failure:
    mov si, error
    call puts
.halt:
    cli
    hlt
    jmp .halt
section .rodata
loading db "boot: loading KERNEL.BIN by FAT12 name",13,10,0
kernel_name db "KERNEL  BIN"
error db "boot: FAT12 load failed",13,10,0
