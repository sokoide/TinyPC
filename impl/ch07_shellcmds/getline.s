; getline.s - read one line from COM1 into a buffer
;
; - every character is echoed back
; - Backspace (0x08): erase the last character by sending "\b \b"
; - CR or LF commits the line (CRLF is echoed; a LF right after a CR
;   is ignored, so both terminal Enter and printf '\n' input work)
; - other control characters and input beyond the limit are dropped
;
; Entry: DI = buffer, CX = buffer size including the NUL slot.
; The line is returned NUL-terminated in the buffer.

cpu 8086
bits 16

global getline
extern putchar, put_crlf

CR equ 0x0D
LF equ 0x0A
BS equ 0x08

COM1      equ 0x3F8
UART_DATA equ COM1 + 0
UART_LSR  equ COM1 + 5
LSR_RX    equ 0x01             ; received data available

section .text

; getchar: block until a byte arrives on COM1, return it in AL
getchar:
    push dx
    mov dx, UART_LSR
.wait:
    in al, dx
    test al, LSR_RX
    jz .wait
    mov dx, UART_DATA
    in al, dx
    pop dx
    ret

; getline: DI = buffer, CX = buffer size (incl. NUL). Returns NUL-terminated line.
getline:
    push ax
    push bx
    push cx
    push di
    xor bx, bx                  ; BX = number of characters buffered
    dec cx                      ; reserve one slot for the NUL
.loop:
    call getchar
    cmp al, LF
    jne .not_lf
    cmp byte [skip_lf], 1       ; LF right after CR?
    jne .commit                 ; no: a plain LF also commits
    mov byte [skip_lf], 0       ; yes: swallow it
    jmp .loop
.not_lf:
    mov byte [skip_lf], 0
    cmp al, CR
    je .commit
    cmp al, BS
    je .backspace
    cmp al, 0x20                ; drop other control characters
    jb .loop
    cmp bx, cx                  ; buffer full?
    jae .loop
    mov [di+bx], al
    inc bx
    call putchar                ; echo
    jmp .loop
.backspace:
    or bx, bx
    jz .loop                    ; nothing to erase
    dec bx
    mov al, BS
    call putchar
    mov al, ' '                 ; overwrite the erased character...
    call putchar
    mov al, BS                  ; ...and move the cursor back
    call putchar
    jmp .loop
.commit:
    cmp al, CR
    jne .store_nul
    mov byte [skip_lf], 1       ; swallow a LF that immediately follows CR
.store_nul:
    mov byte [di+bx], 0
    call put_crlf
    pop di
    pop cx
    pop bx
    pop ax
    ret

section .bss
skip_lf resb 1
