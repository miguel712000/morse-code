; morse_uefi.asm — Tabla ASCII→Morse + emitir en PC Speaker (UEFI x86-64)
; Ensamblar:
;   nasm -f win64 morse_uefi.asm -o morse_uefi.obj
;   lld-link /subsystem:efi_application /entry:efi_main /out:BOOTX64.EFI morse_uefi.obj
;      (ó) ld.lld -m i386pep -subsystem:efi_application -entry:efi_main -o BOOTX64.EFI morse_uefi.obj
; Copiar a ESP:
;   mcopy -i esp.img BOOTX64.EFI ::/EFI/BOOT/

BITS 64
default rel

%define UNIT_MS  200          ; 1 unidad = UNIT_MS mili segundos (ajústalo a gusto)
%define DOT_FREQ  500         ; tono para punto
%define DASH_FREQ 400         ; tono para raya

section .text
global efi_main

; Convención UEFI x64 (Microsoft x64):
; RCX = EFI_HANDLE ImageHandle
; RDX = EFI_SYSTEM_TABLE* SystemTable

efi_main:
    ; prólogo para llamadas (shadow space 32B + alineación)
    push rbp
    mov  rbp, rsp
    sub  rsp, 32

    ; ---- (Opcional) imprime un título en pantalla ----
    mov  rax, [rdx + 0x40]         ; ConOut*
    mov  [rel ConOutPtr], rax;
    mov  rcx, rax
    lea  rdx, [rel title_msg]
    call [rax + 8]                 ; ConOut->OutputString(this, CHAR16*)

    ; ---- Emitir una cadena de prueba (ASCII) ----
    lea  rcx, [rel test_ascii]     ; RCX = &"SOS 123"
    call play_morse_string
    ;mov  ecx, 2
    ;call pause_units


    ; fin OK
    xor  eax, eax
    add  rsp, 32
    pop  rbp
    ret

; ==========================================
; play_morse_string(RCX = char* ascii)
; Recorre la cadena ASCII y llama play_morse_char para cada char.
; ==========================================
play_morse_string:
    push rbp
    mov  rbp, rsp
    sub  rsp, 48                 ; 32 shadow + 16 para locals y alineación
    mov  [rbp-8], rbx            ; salvar RBX (callee-saved)
    mov  rbx, rcx                ; RBX = ptr a la cadena ASCII

.next_char:
    mov  al, [rbx]
    cmp  al, 0
    je   .done
    ; llamar por cada carácter
    mov  cl, al                    ; pasar char en CL (8 bits es suficiente)
    call play_morse_char
    inc  rbx
    jmp  .next_char

.done:
    mov rbx, [rbp-8]            ; restaurar RBX
    add  rsp, 48
    pop  rbp
    ret

; ==========================================
; play_morse_char(CL = ASCII)
; - Espacio ' '  → pausa 7u
; - A–Z / 0–9    → emite patrón . y -  con 1u entre símbolos y 3u entre letras
; - Otros        → se ignoran
; ==========================================
play_morse_char:
    push rbp
    mov  rbp, rsp
    sub  rsp, 48                   ; hace calls → reserva shadow space
    mov [rbp-8],r12

    ; normalizar a mayúsculas si es a–z
    mov  al, cl
    cmp  al, 'a'
    jb   .skip_up
    cmp  al, 'z'
    ja   .skip_up
    sub  al, 32                    ; a..z -> A..Z
.skip_up:

    ; si es espacio → pausa 7u y salir
    cmp  al, ' '
    jne  .not_space
    mov  ecx, 7
    call pause_units
    jmp  .done

.not_space:
    ; si es 'A'..'Z'
    cmp  al, 'A'
    jb   .check_digit
    cmp  al, 'Z'
    ja   .check_digit
    ; índice 0..25 = A..Z
    movzx r11d, al
    sub r11d, 'A'
    lea  r10, [rel morse_letters]
    mov  r12, [r10 + r11*8]        ; r12 = puntero al patrón ".-.-"
    jmp  .emit

.check_digit:
    ; si es '0'..'9'
    cmp  al, '0'
    jb   .unknown
    cmp  al, '9'
    ja   .unknown
    movzx r11d, al
    sub   r11d, '0' ; 0..9
    add  r11d, 26                  ; offset después de A..Z (26..35)
    lea  r10, [rel morse_letters]
    mov  r12, [r10 + r11*8]
    jmp  .emit

.unknown:
    ; cualquier otro char lo ignoramos (sin pausa extra)
    jmp  .done

.emit:
    ; r10 = ptr al string del patrón (bytes '.' y '-' terminados en 0)
.next_sym:
    mov  dl, [r12]
    test  dl, dl
    je   .after_char              
    cmp  dl, '.'                   ; ¿punto?
    jne  .dash
    call emit_dot
    jmp  .after_symbol
.dash:
    call emit_dash

.after_symbol:
    ; mirar si hay otro símbolo para dar pausa intra-caracter (1u)
    cmp  byte [r12+1], 0
    je   .advance_only
    mov  ecx, 1
    call pause_units
.advance_only:
    inc  r12
    jmp  .next_sym

.after_char:
    ; pausa entre letras = 3u (no se aplica si el char era espacio)
    mov  ecx, 3
    call pause_units

.done:
    mov r12, [rbp-8]
    add  rsp, 48
    pop  rbp
    ret

; ==========================================
; emit_dot(): tono DOT_FREQ durante 1u
; ==========================================
emit_dot:
    push rbp
    mov  rbp, rsp
    sub  rsp, 32
    mov  ecx, DOT_FREQ
    call pit_set_freq
    call speaker_on
    ;mov  ecx, UNIT_MS
    ;call delay_ms
    mov  ecx, 1
    call pause_units
    call speaker_off
    call print_dot
    add  rsp, 32
    pop  rbp
    ret

print_dot:
    push rbp
    mov  rbp, rsp
    sub  rsp, 32
    mov  rax, [rel ConOutPtr]
    mov  rcx, rax
    lea  rdx, [rel u16_dot]
    call [rax + 8]
    add  rsp, 32
    pop  rbp
    ret
    

; ==========================================
; emit_dash(): tono DASH_FREQ durante 3u
; ==========================================
emit_dash:
    push rbp
    mov  rbp, rsp
    sub  rsp, 32
    mov  ecx, DASH_FREQ
    call pit_set_freq
    call speaker_on
    ;mov  ecx, (3*UNIT_MS)
    ;call delay_ms
    mov  ecx, 3
    call pause_units
    call speaker_off
    call print_dash
    add  rsp, 32
    pop  rbp
    ret

print_dash:
    push rbp
    mov  rbp, rsp
    sub  rsp, 32
    mov  rax, [rel ConOutPtr]
    mov  rcx, rax
    lea  rdx, [rel u16_dash]      ; dw '-',0 en .data
    call [rax + 8]
    add  rsp, 32
    pop  rbp
    ret

; ==========================================
; pause_units(RCX = unidades) — silencio por RCX * UNIT_MS
; ==========================================
pause_units:
    push rbp
    mov  rbp, rsp
    sub  rsp, 32
    ; ECX = unidades → ECX = unidades * UNIT_MS
    imul ecx, ecx, UNIT_MS
    call delay_ms
    add  rsp, 32
    pop  rbp
    ret

; ==========================================
; pit_set_freq(RCX=freq_hz) — PIT canal 2 (modo 3), divisor=1193182/freq
; Sin retorno útil (efecto lateral).
; ==========================================
pit_set_freq:
    mov   eax, 1193182
    xor   edx, edx
    div   ecx                    ; EAX=cociente (divisor), EDX=resto
    mov   al, 0b10110110
    out   0x43, al               ; control word: ch2, lo/hi, mode3
    mov   edx, eax
    mov   al, dl
    out   0x42, al               ; low byte
    mov   al, dh
    out   0x42, al               ; high byte
    ret

; ==========================================
; speaker_on/off — puerto 0x61, bits 0 y 1
; ==========================================
speaker_on:
    in    al, 0x61
    or    al, 0b00000011
    out   0x61, al
    ret

speaker_off:
    in    al, 0x61
    and   al, 0b11111100
    out   0x61, al
    ret

; ==========================================
; delay_ms(RCX=millis) — busy-wait aproximado (ajusta la constante)
; ==========================================
delay_ms:
    mov   r8, rcx                ; r8 = ms
.outer:
    mov   ecx, 350000             ; constante a calibrar (sube/baja según QEMU)
.inner:
    dec   ecx
    jnz   .inner
    dec   r8
    jnz   .outer
    ret

; --------------- Tabla Morse (punteros a strings ".-" terminados en 0) ---------------
section .rodata
; Letras A..Z
mA: db ".-",0
mB: db "-...",0
mC: db "-.-.",0
mD: db "-..",0
mE: db ".",0
mF: db "..-.",0
mG: db "--.",0
mH: db "....",0
mI: db "..",0
mJ: db ".---",0
mK: db "-.-",0
mL: db ".-..",0
mM: db "--",0
mN: db "-.",0
mO: db "---",0
mP: db ".--.",0
mQ: db "--.-",0
mR: db ".-.",0
mS: db "...",0
mT: db "-",0
mU: db "..-",0
mV: db "...-",0
mW: db ".--",0
mX: db "-..-",0
mY: db "-.--",0
mZ: db "--..",0
; Dígitos 0..9
m0: db "-----",0
m1: db ".----",0
m2: db "..---",0
m3: db "...--",0
m4: db "....-",0
m5: db ".....",0
m6: db "-....",0
m7: db "--...",0
m8: db "---..",0
m9: db "----.",0

align 8
morse_letters:
    dq mA,mB,mC,mD,mE,mF,mG,mH,mI,mJ,mK,mL,mM,mN,mO,mP,mQ,mR,mS,mT,mU,mV,mW,mX,mY,mZ
    dq m0,m1,m2,m3,m4,m5,m6,m7,m8,m9

section .data
ConOutPtr:  dq 0
; Mensajes
title_msg:   dw 'M','o','r','s','e',' ','D','e','m','o',' ',':',' ',0    ; 1 = SOH → se ignora; evita CRLF si no quieres
test_ascii:  db 'a','1','2',0
u16_dot:     dw '.',0
u16_dash:    dw '-',0
