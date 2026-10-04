; NANO.COM - ultra simple nano clone for DOS 3.3 / 8086 4.77 MHz
; Build : nasm -f bin -o NANO.COM nano.asm
; Usage : NANO file.txt
;
; Keys  : arrows, Home/End, PgUp/PgDn, Backspace, Del, Enter, Tab
;         ^S/^O save   ^X exit   ^K delete line

cpu 8086
org 100h

TEXTROWS equ 22                 ; screen rows 1..22 = text
MAXLEN   equ 65000              ; max file size in memory
ATTR_N   equ 07h
ATTR_I   equ 70h

start:
        ; --- text buffer segment: 64 KB right after the program
        mov ax, cs
        add ax, 1000h
        mov [bufseg], ax
        add ax, 1000h
        cmp ax, [2]             ; PSP:2 = top of available memory
        jbe .memok
        mov dx, msg_mem
        jmp die
.memok:
        ; --- file name from the command line
        mov si, 81h
        mov cl, [80h]
        xor ch, ch
        mov di, fname
.skip:  jcxz .noarg
        lodsb
        dec cx
        cmp al, ' '
        je .skip
        cmp al, 9
        je .skip
.copy:  stosb
        jcxz .cdone
        lodsb
        dec cx
        cmp al, ' '
        ja .copy
.cdone: mov byte [di], 0
        jmp .video
.noarg: mov dx, msg_usage
        jmp die

.video: ; --- video mode: mono (B000) or 80-col color (B800)
        mov ah, 0Fh
        int 10h
        cmp al, 7
        jne .notmono
        mov word [vidseg], 0B000h
        jmp .load
.notmono:
        cmp al, 2
        je .load
        cmp al, 3
        je .load
        mov ax, 0003h
        int 10h

.load:  ; --- load file (CR and ^Z dropped)
        mov es, [bufseg]
        mov ax, 3D00h
        mov dx, fname
        int 21h
        jnc .opened
        mov word [msg], msg_new
        jmp main
.opened:
        mov [handle], ax
.rd:    mov bx, [handle]
        mov ah, 3Fh
        mov cx, 512
        mov dx, iobuf
        int 21h
        jc .rdend
        or ax, ax
        jz .rdend
        mov cx, ax
        mov si, iobuf
        mov di, [len]
.cp:    lodsb
        cmp al, 13
        je .nx
        cmp al, 1Ah
        je .nx
        cmp di, MAXLEN
        jae .toobig
        stosb
.nx:    loop .cp
        mov [len], di
        jmp .rd
.toobig:
        mov [len], di
        mov word [msg], msg_big
.rdend: mov bx, [handle]
        mov ah, 3Eh
        int 21h

; ================= main loop =================
main:
        call scroll_fix
        call draw
        xor ah, ah
        int 16h
        mov word [msg], 0
        or al, al
        jz extkey
        cmp al, 0E0h            ; grey keys on enhanced keyboards
        jne .ascii
        cmp ah, 47h
        jb .ascii
        cmp ah, 53h
        jbe extkey
.ascii:
        cmp al, 8
        je k_bs
        cmp al, 13
        je k_enter
        cmp al, 0Fh
        je k_save
        cmp al, 13h             ; ^S
        je k_save
        cmp al, 18h
        je k_quit
        cmp al, 0Bh
        je k_cut
        cmp al, 9
        je k_ins
        cmp al, 20h
        jb main                 ; other control chars ignored
        cmp al, 7Fh
        je main
k_ins:  call insert
        jmp main
k_enter:
        mov al, 10
        jmp k_ins

extkey: cmp ah, 4Bh
        je k_left
        cmp ah, 4Dh
        je k_right
        cmp ah, 48h
        je k_up
        cmp ah, 50h
        je k_down
        cmp ah, 47h
        je k_home
        cmp ah, 4Fh
        je k_end
        cmp ah, 49h
        je k_pgup
        cmp ah, 51h
        je k_pgdn
        cmp ah, 53h
        je k_del
        jmp main

k_left: cmp word [cur], 0
        je main
        dec word [cur]
        jmp main
k_right:
        mov ax, [cur]
        cmp ax, [len]
        jae main
        inc word [cur]
        jmp main
k_up:   call go_up
        jmp main
k_down: call go_down
        jmp main
k_home: mov bx, [cur]
        call line_start
        mov [cur], bx
        jmp main
k_end:  mov bx, [cur]
        call line_end
        mov [cur], bx
        jmp main
k_pgup: mov cx, TEXTROWS-1
.l:     push cx
        call go_up
        pop cx
        loop .l
        jmp main
k_pgdn: mov cx, TEXTROWS-1
.l:     push cx
        call go_down
        pop cx
        loop .l
        jmp main
k_bs:   cmp word [cur], 0
        je main
        dec word [cur]
k_del:  mov ax, [cur]
        cmp ax, [len]
        jae main
        mov cx, 1
        call delete
        jmp main
k_cut:  mov bx, [cur]
        call line_start
        push bx
        call line_end
        cmp bx, [len]
        jae .nolf
        inc bx                  ; include the line feed
.nolf:  pop ax
        mov [cur], ax
        mov cx, bx
        sub cx, ax
        jcxz .z
        call delete
.z:     jmp main
k_save: call save
        jmp main
k_quit: cmp byte [modified], 0
        je quit
        mov word [msg], msg_ask
        call draw
        xor ah, ah
        int 16h
        mov word [msg], 0
        and al, 0DFh            ; uppercase
        cmp al, 'N'
        je quit
        cmp al, 'Y'
        jne main
.sv:    call save
        cmp byte [modified], 0
        jne main
quit:   mov ax, 0600h
        mov bh, ATTR_N
        xor cx, cx
        mov dx, 184Fh
        int 10h
        mov ah, 02h
        xor bh, bh
        xor dx, dx
        int 10h
        mov ax, 4C00h
        int 21h

die:    mov ah, 09h
        int 21h
        mov ax, 4C01h
        int 21h

; ================= editing =================
; insert AL at [cur]
insert: mov cx, [len]
        cmp cx, MAXLEN
        jb .ok
        mov word [msg], msg_full
        ret
.ok:    push ds
        sub cx, [cur]           ; bytes to shift
        mov di, [len]
        mov si, di
        dec si
        mov bx, [cur]
        push es
        pop ds
        std
        rep movsb
        cld
        mov [bx], al
        pop ds
        inc word [len]
        inc word [cur]
        mov byte [modified], 1
        ret

; delete CX bytes starting at AX
delete: push ds
        mov di, ax
        mov si, ax
        add si, cx
        mov dx, [len]
        sub [len], cx
        sub dx, si              ; bytes to move down
        mov cx, dx
        push es
        pop ds
        rep movsb
        pop ds
        mov byte [modified], 1
        ret

; ================= navigation =================
; BX = pos -> BX = start of line
line_start:
.l:     or bx, bx
        jz .r
        cmp byte [es:bx-1], 10
        je .r
        dec bx
        jmp .l
.r:     ret

; BX = pos -> BX = end of line (on the LF or len)
line_end:
.l:     cmp bx, [len]
        jae .r
        cmp byte [es:bx], 10
        je .r
        inc bx
        jmp .l
.r:     ret

; SI = line start, BX = pos -> AX = visual column
vcol:   xor ax, ax
.l:     cmp si, bx
        jae .r
        cmp byte [es:si], 9
        jne .n
        or ax, 7
.n:     inc ax
        inc si
        jmp .l
.r:     ret

; SI = line start, DX = wanted column -> SI = position
pos_at_col:
        xor ax, ax
.l:     cmp si, [len]
        jae .r
        mov cx, ax
        cmp byte [es:si], 10
        je .r
        cmp byte [es:si], 9
        jne .n
        or cx, 7
.n:     inc cx
        cmp cx, dx
        ja .r
        mov ax, cx
        inc si
        jmp .l
.r:     ret

; current column: BX = start of cur's line -> DX
cur_col:
        push bx
        mov si, bx
        mov bx, [cur]
        call vcol
        mov dx, ax
        pop bx
        ret

go_up:  mov bx, [cur]
        call line_start
        or bx, bx
        jz .r
        call cur_col
        dec bx
        call line_start
        mov si, bx
        call pos_at_col
        mov [cur], si
.r:     ret

go_down:
        mov bx, [cur]
        call line_start
        call cur_col
        call line_end
        cmp bx, [len]
        jae .r
        lea si, [bx+1]
        call pos_at_col
        mov [cur], si
.r:     ret

; adjust top / left, compute crow / ccol
scroll_fix:
        mov bx, [cur]
        call line_start         ; BX = start of current line
        xor cx, cx
        cmp bx, [top]
        jae .count
        mov [top], bx
        jmp .vdone
.count: mov si, [top]
.c:     cmp si, bx
        jae .adv
        cmp byte [es:si], 10
        jne .n
        inc cx
.n:     inc si
        jmp .c
.adv:   cmp cx, TEXTROWS
        jb .vdone
        mov si, [top]
.f:     inc si
        cmp byte [es:si-1], 10
        jne .f
        mov [top], si
        dec cx
        jmp .adv
.vdone: mov [crow], cl
        mov si, bx
        mov bx, [cur]
        call vcol               ; AX = visual column
        cmp ax, [left]
        jae .h1
        mov [left], ax
.h1:    mov dx, [left]
        add dx, 79
        cmp ax, dx
        jbe .h2
        mov dx, ax
        sub dx, 79
        mov [left], dx
.h2:    sub ax, [left]
        mov [ccol], al
        ret

; ================= display =================
; write 0-terminated string DS:SI to ES:DI with attribute AH
puts:   lodsb
        or al, al
        jz .r
        stosw
        jmp puts
.r:     ret

; clear a screen row: DI = start, AH = attribute
clrrow: push di
        mov al, ' '
        mov cx, 80
        rep stosw
        pop di
        ret

draw:   push es
        mov es, [vidseg]
        ; title bar
        xor di, di
        mov ah, ATTR_I
        call clrrow
        add di, 4
        mov si, msg_title
        call puts
        mov si, fname
        call puts
        cmp byte [modified], 0
        je .text
        mov di, 70*2
        mov si, msg_mod
        call puts
.text:  ; text
        mov bp, [left]
        mov dx, TEXTROWS
        mov di, 160
        mov si, [top]
        mov ds, [cs:bufseg]
.row:   mov ah, ATTR_N
        call clrrow
        xor bx, bx              ; visual column
.ch:    cmp si, [cs:len]
        jae .eof
        lodsb
        cmp al, 10
        je .eol
        cmp al, 9
        je .tab
        call put
        jmp .ch
.tab:   mov al, ' '
.t1:    call put
        test bx, 7
        jnz .t1
        jmp .ch
.eof:   mov si, [cs:len]
        inc si                  ; following rows empty
.eol:   add di, 160
        dec dx
        jnz .row
        push cs
        pop ds
        ; message row
        mov di, 23*160
        mov ah, ATTR_N
        call clrrow
        mov si, [msg]
        or si, si
        jz .help
        mov ah, ATTR_I
        call puts
.help:  ; help row
        mov di, 24*160
        mov ah, ATTR_N
        call clrrow
        mov si, help
.hl:    mov ah, ATTR_I
        call puts
        mov ah, ATTR_N
        call puts
        cmp byte [si], 0
        jne .hl
.hend:  pop es
        ; hardware cursor
        mov ah, 02h
        xor bh, bh
        mov dh, [crow]
        inc dh
        mov dl, [ccol]
        int 10h
        ret

; AL = char, BX = visual column, BP = left, DI = row start
put:    mov cx, bx
        sub cx, bp
        jb .s
        cmp cx, 80
        jae .s
        shl cx, 1
        push di
        add di, cx
        mov ah, ATTR_N
        stosw
        pop di
.s:     inc bx
        ret

; ================= save (LF -> CR LF) =================
save:   mov ah, 3Ch
        xor cx, cx
        mov dx, fname
        int 21h
        jc .err
        mov [handle], ax
        xor si, si
        mov di, iobuf
.l:     cmp si, [len]
        jae .fin
        mov al, [es:si]
        inc si
        cmp al, 10
        jne .p
        mov byte [di], 13
        inc di
.p:     mov [di], al
        inc di
        cmp di, iobuf+510
        jb .l
        call flush
        jc .errc
        jmp .l
.fin:   call flush
        jc .errc
        mov bx, [handle]
        mov ah, 3Eh
        int 21h
        mov byte [modified], 0
        mov word [msg], msg_saved
        ret
.errc:  mov bx, [handle]
        mov ah, 3Eh
        int 21h
.err:   mov word [msg], msg_err
        ret

flush:  mov cx, di
        sub cx, iobuf
        jcxz .ok
        mov bx, [handle]
        mov dx, iobuf
        mov ah, 40h
        int 21h
        jc .r
        cmp ax, cx
        jne .full
        mov di, iobuf
.ok:    clc
.r:     ret
.full:  stc
        ret

; ================= data =================
msg_usage db 'Usage: NANO file', 13, 10, '$'
msg_mem   db 'Not enough memory', 13, 10, '$'
msg_title db 'nano8086  ', 0
msg_mod   db 'Modified', 0
msg_new   db ' [ New File ] ', 0
msg_big   db ' [ File too big, truncated! ] ', 0
msg_full  db ' [ Buffer full ] ', 0
msg_saved db ' [ Saved ] ', 0
msg_err   db ' [ Write error ] ', 0
msg_ask   db ' Save modified buffer? (Y/N, other = cancel) ', 0
help      db '^S', 0, ' Save   ', 0
          db '^X', 0, ' Exit   ', 0
          db '^K', 0, ' Delete line', 0, 0

vidseg    dw 0B800h
len       dw 0
cur       dw 0
top       dw 0
left      dw 0
msg       dw 0
modified  db 0
crow      db 0
ccol      db 0

section .bss
bufseg    resw 1
handle    resw 1
fname     resb 128
iobuf     resb 512
