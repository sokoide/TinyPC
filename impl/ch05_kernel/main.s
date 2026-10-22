; main.s - kernel main, called from crt0 (ch05 version)
;
; Prints the banner and proves that crt0 cleared .bss, then returns to
; crt0's hlt loop. ch06 replaces the trailing return with `call
; shell_main` to enter the shell.

cpu 8086
bits 16

global main
extern puts, put_crlf, put_hex_word, put_hex_byte
extern __bss_start, __bss_end

section .text
main:
    mov si, msg_banner
    call puts

    ; show the .bss range the linker assigned (from linker.ld symbols)
    mov si, msg_bss
    call puts
    mov ax, __bss_start
    call put_hex_word
    mov si, msg_bss_to
    call puts
    mov ax, __bss_end
    call put_hex_word
    call put_crlf

    ; prove that crt0 cleared .bss (bss_test must read 0x00)
    mov si, msg_bsscheck
    call puts
    mov al, [bss_test]
    call put_hex_byte
    call put_crlf
    ret                         ; back to crt0's hlt loop

section .bss
bss_test resb 1

section .rodata
msg_banner  db "kernel: TinyPCBIOS kernel linked by ld.lld (elf32 -> flat binary)", 13, 10
            db "kernel: boot chain: SeaBIOS -> boot sector -> INT 13h -> 0x8000", 13, 10, 0
msg_bss     db "kernel: .bss 0x", 0
msg_bss_to  db "-0x", 0
msg_bsscheck db "kernel: bss_test=0x", 0
