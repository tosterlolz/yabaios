[BITS 16]
[ORG 0x8000]

; ------------------------------
; Stage2 loader for YabaiOS
; ------------------------------
; Loads kernel from disk after stage1.
; Loads kernel to 0x20000 and jumps there.
; ------------------------------

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x9000
    sti

    ; Read sector 8 into 0x8100 (kernel sector count)
    mov bx, 0x8100
    mov ah, 0x02
    mov al, 1
    mov ch, 0
    mov cl, 9
    mov dh, 0
    ; DL already contains boot drive (from BIOS)
    int 0x13
    jc disk_err

    ; Get kernel size (number of sectors)
    mov si, 0x8100
    mov cx, [si]

    ; Set ES:BX = 0x20000 (kernel load addr)
    mov ax, 0x2000
    mov es, ax
    xor bx, bx

    ; Start LBA = 9
    mov si, 9

read_kernel_loop:
    cmp cx, 0
    je kernel_done

    push cx
    push si

    call lba_to_chs     ; returns CH, CL, DH

    mov ah, 0x02        ; BIOS read
    mov al, 1
    ; DL already contains boot drive (from BIOS)
    int 0x13
    jc disk_err

    pop si
    pop cx

    add bx, 512
    jc .seg_inc
    jmp .no_seg_inc
.seg_inc:
    ; BX wrapped around 64K after add -> increment ES (BX already wrapped)
    mov ax, es
    add ax, 1
    mov es, ax
.no_seg_inc:

    inc si
    dec cx
    jmp read_kernel_loop

disk_err:
    mov ah, 0x0E
    mov al, 'E'
    int 0x10
    hlt

kernel_done:
    ; Jump to kernel loaded at 0x20000
    ; Segment = 0x2000, offset = 0x0000
    push word 0x2000
    push word 0x0000
    retf

; -------------------------------------------------
; LBA -> CHS conversion
; Input: SI = LBA
; Output: CH, CL, DH
; -------------------------------------------------
lba_to_chs:
    push ax
    push bx
    push dx

    mov bx, si
    xor dx, dx
    mov ax, bx
    mov cx, 36          ; sectors/track
    div cx              ; AX = track*heads + head, DX = sector-1
    mov di, ax
    inc dx              ; DX = sector
    mov cl, dl          ; CL = sector

    mov ax, di
    xor dx, dx
    mov cx, 2           ; heads
    div cx              ; AX = track, DX = head
    mov ch, al          ; CH = track
    mov dh, dl          ; DH = head

    mov bl, ch
    shr bl, 2
    and bl, 0xC0
    or cl, bl

    pop dx
    pop bx
    pop ax
    ret

BOOT_DRIVE: db 0

times 3584 - ($ - $$) db 0
