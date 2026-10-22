cpu 8086
bits 16
org 0x7C00
jmp short start
nop
db "TINYPC  "
dw 512
db 1
dw 8
db 2
dw 224
dw 2880
db 0xF0
dw 9
dw 18,2
dd 0,0
db 0,0,0x29
dd 0x54494E59
db "TINYPC     "
db "FAT12   "
start:
	cli
	cld
	xor  ax, ax
	mov  ss, ax
	mov  sp, 0x7C00
	mov  ds, ax
	mov  es, ax
	sti
	mov  [0x7C24], dl
	mov  [boot_drive], dl
	mov  si, boot_message
	call puts

	mov ax, 0x0207
	mov bx, 0x2000
	mov cx, 0x0002
	xor dh, dh
	mov dl, [boot_drive]
	int 0x13
	jc  disk_error
	jmp 0x0000:0x2000

disk_error:
	mov  si, error_message
	call puts

.halt:
	cli
	hlt
	jmp .halt

puts:
	lodsb
	test al, al
	jz   .done
	mov  ah, 0x0E
	mov  bx, 0x0007
	int  0x10
	jmp  puts

.done:
	ret

boot_message  db 'Booting...', 13, 10, 0
error_message db 'Disk read failed', 13, 10, 0
boot_drive    db 0

times 510-($-$$) db 0
dw    0xAA55
