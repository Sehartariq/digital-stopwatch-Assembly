
; DIGITAL STOPWATCH 
; Student: Sehar Tariq (231196)
; Controls: S=Start, P=Pause, R=Reset, Q=Quit


.model small
.stack 256

.data
    seconds     db 0
    minutes     db 0  
    
    ; State: 0=READY, 1=RUNNING, 2=PAUSED
    state       db 0

    ; Used to track BIOS clock ticks for 1-second intervals
    last_tick   dw 0
    ; Scratch storage so printchar does not clobber our remainder
    ones_digit  db 0

    ; UI Messages
    title_msg   db '=== DIGITAL STOPWATCH ===$'
    ctrl_s      db '[S] Start $'
    ctrl_p      db '[P] Pause $'
    ctrl_r      db '[R] Reset $'
    ctrl_q      db '[Q] Quit  $'
    lbl_status  db 'Status: $'
    txt_running db 'RUNNING $'
    txt_paused  db 'PAUSED  $'
    txt_ready   db 'READY   $'
    lbl_time    db 'Time: $'

.code





; ============================================================
; Set cursor position  DH=row  DL=col
; ============================================================
CURSORposition proc
    mov ah, 02h      ;change cursor position
    mov bh, 0         ;display (on-screen)
    int 10h     ;video interrupt
    ret
CURSORposition endp

; ============================================================
; Print $-terminated string at DS:DX
; ============================================================
print proc
    mov ah, 09h
    int 21h
    ret
print endp

; ============================================================
; Print single character in DL
; ============================================================
printchar proc
    mov ah, 02h
    int 21h
    ret
printchar endp

; ============================================================
; Print 2-digit decimal in AL (0-99)
; Saves ones remainder to memory to avoid AH corruption
; ============================================================
print2digits proc
    push ax
    push bx
    push dx

    mov ah, 0
    mov bl, 10
    div bl              ; AL = tens, AH = ones

    mov ones_digit, ah  ; save BEFORE any INT call touches AH

    add al, '0'
    mov dl, al
    call printchar      ; print tens

    mov al, ones_digit
    add al, '0'
    mov dl, al
    call printchar      ; print ones

    pop dx
    pop bx
    pop ax
    ret
print2digits endp

; ============================================================
; Display time MM:SS at row 10, col 34
; ============================================================
show_time proc
    push ax
    push dx

    mov dh, 10
    mov dl, 34
    call CURSORposition

    mov dx, offset lbl_time
    call print

    mov al, minutes
    call print2digits

    mov dl, ':'
    call printchar

    mov al, seconds
    call print2digits

    pop dx
    pop ax
    ret
show_time endp

; ============================================================
; Show status: RUNNING / PAUSED / READY
; ============================================================
show_status proc
    push dx

    mov dh, 12
    mov dl, 34
    call CURSORposition
    mov dx, offset lbl_status
    call print

    cmp state, 1
    je  ss_running
    cmp state, 2
    je  ss_paused

    ; state = 0 -> READY
    mov dx, offset txt_ready
    call print
    jmp ss_done

ss_running:
    mov dx, offset txt_running
    call print
    jmp ss_done

ss_paused:
    mov dx, offset txt_paused
    call print

ss_done:
    pop dx
    ret
show_status endp

; ============================================================
; Draw the full UI
; ============================================================
draw_ui proc
   

    mov dh, 2
    mov dl, 26
    call CURSORposition
    mov dx, offset title_msg
    call print

    ; Draw a dashed separator line
    mov dh, 4
    mov dl, 26
    call CURSORposition
    mov cx, 28
draw_line_loop:
    mov dl, '-'
    call printchar
    loop draw_line_loop

    mov dh, 17
    mov dl, 26
    call CURSORposition
    mov dx, offset ctrl_s
    call print

    mov dh, 18
    mov dl, 26
    call CURSORposition
    mov dx, offset ctrl_p
    call print

    mov dh, 19
    mov dl, 26
    call CURSORposition
    mov dx, offset ctrl_r
    call print

    mov dh, 20
    mov dl, 26
    call CURSORposition
    mov dx, offset ctrl_q
    call print

    call show_time
    call show_status

    ret
draw_ui endp

; ============================================================
; Read BIOS tick count via INT 1Ah -> low word in DX
; ============================================================
get_ticks proc
    push ax
    mov ah, 0
    int 1Ah         ; CX:DX = tick count (~18.2 ticks/sec)  ; time services interrupt
    pop ax
    ret
get_ticks endp

; ============================================================
; Increment timer if 18 ticks (~1 second) have elapsed
; ============================================================
update_timer proc
    cmp state, 1
    jne ut_exit

    call get_ticks          ; DX = current tick (low word)

    mov ax, dx
    sub ax, last_tick       ; elapsed = current - last

    cmp ax, 18
    jl  ut_exit             ; less than 1 second, skip

    mov last_tick, dx       ; reset baseline

    ; Increment seconds
    mov al, seconds
    inc al
    cmp al, 60
    jl  ut_store_sec

    ; Seconds rolled over
    mov al, 0
    mov bl, minutes
    inc bl
    cmp bl, 60
    jl  ut_store_min
    mov bl, 0

ut_store_min:
    mov minutes, bl

ut_store_sec:
    mov seconds, al
    call show_time

ut_exit:
    ret
update_timer endp

; ============================================================
; Non-blocking keyboard check
; ============================================================
check_key proc
    mov ah, 01h
    int 16h
    jz  ck_exit             ; zero flag = no key waiting

    mov ah, 00h
    int 16h                 ; AL = ASCII of pressed key

    cmp al, 'S'
    je  ck_start
    cmp al, 's'
    je  ck_start

    cmp al, 'P'
    je  ck_pause
    cmp al, 'p'
    je  ck_pause

    cmp al, 'R'
    je  ck_reset
    cmp al, 'r'
    je  ck_reset

    cmp al, 'Q'
    je  ck_quit
    cmp al, 'q'
    je  ck_quit

    jmp ck_exit

ck_start:
    cmp state, 1
    je  ck_exit             ; already running, ignore
    mov state, 1
    call get_ticks
    mov last_tick, dx       ; snapshot tick so no instant jump
    call show_status
    jmp ck_exit

ck_pause:
    cmp state, 1
    jne ck_exit             ; only pause when running
    mov state, 2
    call show_status
    jmp ck_exit

ck_reset:
    mov state, 0
    mov seconds, 0
    mov minutes, 0
    call show_time
    call show_status
    jmp ck_exit

ck_quit:
    
    mov ah, 01h             ; restore cursor before exit
    mov ch, 06h
    mov cl, 07h
    int 10h
    mov ax, 4C00h
    int 21h

ck_exit:
    ret
check_key endp

; ============================================================
; MAIN
; ============================================================
main proc
    mov ax, @data
    mov ds, ax

    
    mov seconds,    0
    mov minutes,    0
    mov state,      0
    mov last_tick,  0
    mov ones_digit, 0

 
    call draw_ui

main_loop:
    call update_timer
    call check_key


    jmp main_loop

main endp
end main
