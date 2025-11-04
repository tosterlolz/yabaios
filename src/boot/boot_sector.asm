bits 16
org 0x7c00

; Minimal boot sector that loads stage2 (sectors 1..7) at 0x0000:0x8000

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00

    ; debug: print '1' to screen so we know boot sector ran
    mov ah, 0x0E
    mov al, '1'
    int 0x10

    ; load stage2 into 0x8000
    mov si, 1          ; LBA of first stage2 sector
    mov cx, 7          ; number of sectors to read (1..7)
    mov bx, 0x8000     ; buffer offset (we'll use ES=0)
    mov es, ax         ; ES = 0
read_stage2_loop:
    ; compute CHS for LBA in SI
    push si
    call lba_to_chs
    pop si
    mov ah, 0x02       ; read sectors
    mov al, 1
    mov dl, 0x00       ; floppy drive
    int 0x13
    jc disk_err

    add bx, 512
    add si, 1
    loop read_stage2_loop

    ; jump to stage2 at 0x0000:0x8000
    jmp 0x0000:0x8000

disk_err:
    hlt

; LBA->CHS conversion
; inputs: SI = LBA
; outputs: CH=track, CL=sector (bits 0-5, bits 6-7 = track bits 8-9), DH=head
lba_to_chs:
    push ax
    push bx
    push cx
    push dx
    push si

    ; SI = LBA
    mov ax, si
    xor dx, dx
    mov bx, 18
    div bx              ; AX = quotient, DX = remainder (sector-1)
    inc dl              ; DL = sector (1..18)
    mov cl, dl          ; CL = sector

    ; AX now = quotient = (cylinder*heads + head)
    ; divide by heads (2) to get cylinder and head
    mov bx, 2
    xor dx, dx
    div bx              ; AX = cylinder, DX = head
    mov ch, al          ; CH = cylinder low byte
    mov dh, dl          ; DH = head

    ; put top bits of cylinder into CL bits 6-7
    mov bx, ax          ; BX = cylinder
    shr bx, 8
    and bl, 0x03
    shl bl, 6
    or cl, bl

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

times 510-($-$$) db 0
dw 0xaa55
