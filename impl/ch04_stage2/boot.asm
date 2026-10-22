; boot.asm - common stage 1 boot sector (ch04 and later)
;
; Identical file in ch04..ch07. Loaded by the BIOS at 0x0000:0x7C00,
; it reads LBA 1..32 (the kernel area) to 0x0000:0x8000 through INT 13h
; and jumps there. The boot sector knows nothing about the disk beyond
; the INT 13h calling convention: it converts LBA to CHS by itself.

cpu 8086
bits 16
org 0x7C00

; --- kernel area ---
KERNEL_LBA_START equ 1          ; first sector of the kernel area
KERNEL_SECTORS   equ 32         ; LBA 1..32 = 16 KiB loaded at 0x8000
KERNEL_OFF       equ 0x8000
DRIVE_FLOPPY     equ 0x00       ; INT 13h drive number for drive A

; --- floppy geometry (1.44 MB: 80 cylinders, 2 heads, 18 sectors/track) ---
SECTORS_PER_CYL  equ 36         ; 2 heads * 18 sectors
SECTORS_PER_HEAD equ 18
RETRY_MAX        equ 3

; --- INT 13h services ---
INT13H_READ  equ 0x02
INT13H_RESET equ 0x00

; --- COM1 16550 UART ---
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
    mov es, ax                  ; ES:BX is the INT 13h buffer
    mov ss, ax
    mov sp, 0x7C00

    call uart_init
    mov si, msg_boot
    call puts

    mov di, KERNEL_LBA_START    ; DI = current LBA
    mov bp, KERNEL_SECTORS      ; BP = sectors left to read
    mov bx, KERNEL_OFF          ; ES:BX = load buffer (ES = 0)
.read_loop:
    mov ax, di
    call lba_to_chs             ; returns CH = cyl, DH = head, CL = sector
    mov byte [retry_left], RETRY_MAX
.retry:
    mov ah, INT13H_READ
    mov al, 1                   ; read one sector
    mov dl, DRIVE_FLOPPY
    int 0x13
    jnc .next
    ; carry set: reset the disk controller, then retry
    dec byte [retry_left]
    jz .disk_error
    mov ah, INT13H_RESET
    mov dl, DRIVE_FLOPPY
    int 0x13
    jmp .retry
.next:
    inc di
    add bx, 512
    dec bp
    jnz .read_loop

    mov si, msg_jump
    call puts
    jmp 0x0000:KERNEL_OFF

.disk_error:
    mov si, msg_disk_err
    call puts
    mov al, ah                  ; INT 13h error status
    call put_hex_byte
    call put_crlf
.halt:
    cli
    hlt
    jmp .halt

; lba_to_chs: AX = LBA -> CH = cylinder, DH = head, CL = sector
;   cyl  = lba / 36
;   head = (lba % 36) / 18
;   sect = (lba % 18) + 1
lba_to_chs:
    push bx                     ; BX is the caller's buffer pointer
    mov bx, SECTORS_PER_CYL
    xor dx, dx
    div bx                      ; AX = cyl, DX = lba % 36
    mov ch, al
    mov ax, dx
    xor dx, dx
    mov bx, SECTORS_PER_HEAD
    div bx                      ; AX = head, DX = lba % 18
    mov dh, al
    mov cl, dl
    inc cl
    pop bx
    ret

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
    xlatb
    call putchar
    pop bx
    ret

; ---- data ----
retry_left   db 0
msg_boot     db "boot: TinyPCBIOS stage 1 at 0x0000:0x7C00", 13, 10
             db "boot: loading kernel (LBA 1..32) to 0x0000:0x8000", 13, 10, 0
msg_jump     db "boot: jumping to 0x0000:0x8000", 13, 10, 0
msg_disk_err db "boot: disk error after 3 retries, AH=0x", 0
hex_table    db "0123456789ABCDEF"

times 510-($-$$) db 0
dw 0xAA55
