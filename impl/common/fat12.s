; Read-only FAT12 for the teaching floppy: 512 B/sector, one sector/cluster,
; 2880 sectors, two FATs of nine sectors, 224 root entries, CHS 18x2.
; DS=ES=0, DF=0. SCRATCH is private to these routines. No IRQ handler.
cpu 8086
bits 16
global fat_init, fat_find, fat_load, fat_ls, file_size
extern putchar, put_crlf
SCRATCH equ 0x7E00
section .text
; DL = BIOS drive. CF=1 for an unsupported BPB.
fat_init:
    mov [drive], dl
    cmp word [0x7C0B], 512
    jne .bad
    cmp byte [0x7C0D], 1
    jne .bad
    cmp byte [0x7C10], 2
    jne .bad
    cmp word [0x7C11], 224
    jne .bad
    cmp word [0x7C13], 2880
    jne .bad
    cmp word [0x7C16], 9
    jne .bad
    cmp word [0x7C18], 18
    jne .bad
    cmp word [0x7C1A], 2
    jne .bad
    mov ax, [0x7C0E]
    cmp ax, 8
    jne .bad
    mov [fat_lba], ax
    add ax, 18
    mov [root_lba], ax
    add ax, 14
    mov [data_lba], ax
    mov bx, 2881
    sub bx, ax
    mov [max_cluster], bx
    clc
    ret
.bad:
    stc
    ret

; AX=LBA, DI=destination (a whole 512-byte sector must fit).
; All general/segment registers preserved; only FLAGS is returned.
read_sector:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push es
    mov [io_lba], ax
    mov si, 3
.retry:
    mov ax, [io_lba]
    cmp ax, 2880
    jae .bad
    xor dx, dx
    mov bx, 18
    div bx
    mov cl, dl
    inc cl
    xor dx, dx
    mov bx, 2
    div bx
    mov ch, al
    mov dh, dl
    mov dl, [drive]
    xor ax, ax
    mov es, ax
    mov bx, di
    mov ax, 0x0201
    int 0x13
    jnc .ok
    mov dl, [drive]
    xor ax, ax
    int 0x13
    dec si
    jnz .retry
.bad:
    stc
    jmp .out
.ok:
    clc
.out:
    pop es
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; SI points at exactly 11 bytes of an uppercase, space-padded 8.3 name.
; On success populate file_size and first_cluster. CF=1: absent or I/O error.
; Clobbers AX,BX,CX,DX,SI,DI,BP; requires DS=ES=0 and DF=0.
fat_find:
    mov [name_ptr], si
    mov ax, [root_lba]
    mov [scan_lba], ax
    mov bp, 14
.sector:
    mov ax, [scan_lba]
    mov di, SCRATCH
    call read_sector
    jc .bad
    mov bx, SCRATCH
    mov dx, 16
.entry:
    cmp byte [bx], 0
    je .bad
    cmp byte [bx], 0xE5
    je .next
    test byte [bx+11], 0x18
    jnz .next
    mov si, [name_ptr]
    mov di, bx
    mov cx, 11
    repe cmpsb
    jne .next
    cmp word [bx+30], 0
    jne .bad
    mov ax, [bx+26]
    mov [first_cluster], ax
    mov ax, [bx+28]
    mov [file_size], ax
    clc
    ret
.next:
    add bx, 32
    dec dx
    jnz .entry
    inc word [scan_lba]
    dec bp
    jnz .sector
.bad:
    stc
    ret

; AX=current cluster -> AX=next (including an EOC value). CF=I/O failure.
; Handles a two-byte FAT entry spanning sectors without a second buffer.
fat_next:
    mov [current], ax
    mov bx, ax
    shr bx, 1
    add ax, bx
    xor dx, dx
    mov bx, 512
    div bx
    mov [entry_offset], dx
    add ax, [fat_lba]
    mov [entry_sector], ax
    mov di, SCRATCH
    call read_sector
    jc .bad
    mov bx, SCRATCH
    add bx, [entry_offset]
    mov al, [bx]
    mov [entry_low], al
    cmp word [entry_offset], 511
    jne .same
    mov ax, [entry_sector]
    inc ax
    call read_sector
    jc .bad
    mov ah, [SCRATCH]
    jmp .decode
.same:
    mov ah, [bx+1]
.decode:
    mov al, [entry_low]
    test word [current], 1
    jz .even
    mov cl, 4
    shr ax, cl
.even:
    and ax, 0x0FFF
    clc
    ret
.bad:
    stc
    ret

; SI=name, DI=destination, CX=capacity. CF=0, AX=file bytes on success.
; Capacity includes sector rounding. Incomplete writes on error are invalid.
; Clobbers AX,BX,CX,DX,SI,DI,BP. Caller must discard partial output on CF=1.
; Exact-length chains are required: early EOC, cycles and excess links fail.
fat_load:
    mov [destination], di
    mov [capacity], cx
    call fat_find
    jc .bad
    mov ax, [file_size]
    cmp ax, 0xFE00
    ja .bad
    add ax, 511
    and ax, 0xFE00
    cmp ax, [capacity]
    ja .bad
    mov bx, [destination]
    add bx, ax
    jc .bad
    mov [remaining], ax
    mov ax, [first_cluster]
    cmp word [remaining], 0
    jne .cluster
    or ax, ax
    jnz .bad
    jmp .ok
.cluster:
    cmp ax, 2
    jb .bad
    cmp ax, [max_cluster]
    ja .bad
    mov [current], ax
    sub ax, 2
    add ax, [data_lba]
    mov di, [destination]
    call read_sector
    jc .bad
    add word [destination], 512
    mov ax, [current]
    call fat_next
    jc .bad
    sub word [remaining], 512
    jz .last
    jmp .cluster
.last:
    cmp ax, 0xFF8
    jb .bad
.ok:
    mov ax, [file_size]
    clc
    ret
.bad:
    stc
    ret

fat_ls:
    mov ax, [root_lba]
    mov [scan_lba], ax
    mov bp, 14
.sector:
    mov ax, [scan_lba]
    mov di, SCRATCH
    call read_sector
    jc .bad
    mov bx, SCRATCH
    mov dx, 16
.entry:
    cmp byte [bx], 0
    je .ok
    cmp byte [bx], 0xE5
    je .next
    test byte [bx+11], 0x18
    jnz .next
    mov si, bx
    mov cx, 8
.name:
    lodsb
    cmp al, ' '
    je .skip
    call putchar
.skip:
    loop .name
    cmp byte [si], ' '
    je .newline
    mov al, '.'
    call putchar
    mov cx, 3
.ext:
    lodsb
    cmp al, ' '
    je .skip_ext
    call putchar
.skip_ext:
    loop .ext
.newline:
    call put_crlf
.next:
    add bx, 32
    dec dx
    jnz .entry
    inc word [scan_lba]
    dec bp
    jnz .sector
.ok:
    clc
    ret
.bad:
    stc
    ret

section .bss
drive resb 1
fat_lba resw 1
root_lba resw 1
data_lba resw 1
max_cluster resw 1
io_lba resw 1
scan_lba resw 1
name_ptr resw 1
first_cluster resw 1
file_size resw 1
current resw 1
entry_offset resw 1
entry_sector resw 1
entry_low resb 1
destination resw 1
capacity resw 1
remaining resw 1
