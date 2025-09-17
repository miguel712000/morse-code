; morse_uefi.asm — UEFI x86-64: ASCII→Morse por PC Speaker (NASM)
; Build:
;   nasm -f win64 morse_uefi.asm -o morse_uefi.obj
;   lld-link /subsystem:efi_application /entry:efi_main /out:BOOTX64.EFI morse_uefi.obj
;   truncate -s 64M esp.img
;   mkfs.vfat -F 32 -n ESP esp.img
;   mmd   -i esp.img ::/EFI
;   mmd   -i esp.img ::/EFI/BOOT
; Copiar a la ESP:
;   mcopy -i esp.img BOOTX64.EFI ::/EFI/BOOT/
; Correr:
;   qemu-system-x86_64   -machine q35 -m 256   -bios /usr/share/OVMF/OVMF_CODE.fd   -drive file=esp.img,format=raw,if=virtio   -audiodev pa,id=snd0   -machine pcspk-audiodev=snd0 -serial stdio


BITS 64
default rel                       ; direcciones relativas a RIP (EFI reubicable)

%define UNIT_MS   200             ; 1 unidad de tiempo (ms) para Morse
%define DOT_FREQ  500             ; frecuencia (Hz) para punto
%define DASH_FREQ 400             ; frecuencia (Hz) para raya

section .text
global efi_main

; Convención UEFI x64 (Microsoft x64):
; RCX = ImageHandle, RDX = EFI_SYSTEM_TABLE*
; Regla ABI: reservar 32 bytes (shadow space) antes de cada call y alinear la pila a 16B.

efi_main:
    ; --- prólogo (marco + shadow space) ---
    push rbp
    mov  rbp, rsp
    sub  rsp, 32

    ; --- obtener ConOut y mostrar título ---
    mov  rax, [rdx + 0x40]        ; RAX = SystemTable->ConOut*
    mov  [rel ConOutPtr], rax     ; guardar ConOut globalmente (para imprimir símbolos)
    mov  rcx, rax                 ; RCX = this (ConOut)
    lea  rdx, [rel title_msg]     ; RDX = u16*
    call [rax + 8]                ; ConOut->OutputString(this, msg)

    ; --- demo: emitir cadena fija en Morse ---
    lea  rcx, [rel test_ascii]    ; RCX = "a12"
    call play_morse_string

    ; --- epílogo ---
    xor  eax, eax                 ; EFI_SUCCESS
    add  rsp, 32
    pop  rbp
    ret

; ----------------------------------------------------------------------
; play_morse_string(RCX=char* ascii)
; Recorre una cadena ASCII terminada en 0 y emite cada carácter en Morse.
; Usa RBX (callee-saved) como puntero de recorrido.
; ----------------------------------------------------------------------
play_morse_string:
    push rbp
    mov  rbp, rsp
    sub  rsp, 48
    mov  [rbp-8], rbx             ; salvar RBX (callee-saved)
    mov  rbx, rcx                 ; RBX = ptr a la cadena

.next_char:
    mov  al, [rbx]                ; AL = *p
    cmp  al, 0
    je   .done
    mov  cl, al                   ; CL = carácter actual (8 bits)
    call play_morse_char
    inc  rbx
    jmp  .next_char

.done:
    mov  rbx, [rbp-8]             ; restaurar RBX
    add  rsp, 48
    pop  rbp
    ret

; ----------------------------------------------------------------------
; play_morse_char(CL=ASCII)
; - ' '  → pausa 7u (entre palabras)
; - 'A'..'Z' y '0'..'9' → emite su patrón ".-"
; - Otros → se ignoran.
; Usa R12 (callee-saved) como puntero al patrón ".-".
; ----------------------------------------------------------------------
play_morse_char:
    push rbp
    mov  rbp, rsp
    sub  rsp, 48
    mov  [rbp-8], r12             ; salvar R12

    ; mayúsculas si es 'a'..'z'
    mov  al, cl
    cmp  al, 'a'
    jb   .skip_up
    cmp  al, 'z'
    ja   .skip_up
    sub  al, 32                   ; a..z → A..Z
.skip_up:

    ; espacio → 7 unidades de silencio
    cmp  al, ' '
    jne  .not_space
    mov  ecx, 7
    call pause_units
    jmp  .done

.not_space:
    ; letras 'A'..'Z' (índice 0..25)
    cmp  al, 'A'
    jb   .check_digit
    cmp  al, 'Z'
    ja   .check_digit
    movzx r11d, al
    sub   r11d, 'A'
    lea   r10, [rel morse_letters]
    mov   r12, [r10 + r11*8]      ; R12 = ptr al patrón ".-"
    jmp   .emit

.check_digit:
    ; dígitos '0'..'9' (índice 26..35)
    cmp  al, '0'
    jb   .unknown
    cmp  al, '9'
    ja   .unknown
    movzx r11d, al
    sub   r11d, '0'
    add   r11d, 26
    lea   r10, [rel morse_letters]
    mov   r12, [r10 + r11*8]
    jmp   .emit

.unknown:
    jmp  .done                    ; caract. fuera de rango → no hace nada

.emit:
    ; recorre el string ".-" hasta byte 0
.next_sym:
    mov   dl, [r12]               ; DL = símbolo actual
    test  dl, dl
    je    .after_char
    cmp   dl, '.'
    jne   .dash
    call  emit_dot
    jmp   .after_symbol
.dash:
    call  emit_dash

.after_symbol:
    ; si hay otro símbolo luego, pausa intra-caracter = 1u
    cmp  byte [r12+1], 0
    je   .advance_only
    mov  ecx, 1
    call pause_units
.advance_only:
    inc  r12
    jmp  .next_sym

.after_char:
    ; pausa entre letras = 3u
    mov  ecx, 3
    call pause_units

.done:
    mov  r12, [rbp-8]             ; restaurar R12
    add  rsp, 48
    pop  rbp
    ret

; ----------------------------------------------------------------------
; emit_dot(): tono DOT_FREQ durante 1u + imprime '.'
; ----------------------------------------------------------------------
emit_dot:
    push rbp
    mov  rbp, rsp
    sub  rsp, 32
    mov  ecx, DOT_FREQ
    call pit_set_freq
    call speaker_on
    mov  ecx, 1                   ; 1 unidad encendido
    call pause_units
    call speaker_off
    call print_dot                ; eco visual
    add  rsp, 32
    pop  rbp
    ret

; imprime un carácter UTF-16 ('.') usando ConOut->OutputString
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

; ----------------------------------------------------------------------
; emit_dash(): tono DASH_FREQ durante 3u + imprime '-'
; ----------------------------------------------------------------------
emit_dash:
    push rbp
    mov  rbp, rsp
    sub  rsp, 32
    mov  ecx, DASH_FREQ
    call pit_set_freq
    call speaker_on
    mov  ecx, 3                   ; 3 unidades encendido
    call pause_units
    call speaker_off
    call print_dash               ; eco visual
    add  rsp, 32
    pop  rbp
    ret

; imprime un carácter UTF-16 ('-') usando ConOut->OutputString
print_dash:
    push rbp
    mov  rbp, rsp
    sub  rsp, 32
    mov  rax, [rel ConOutPtr]
    mov  rcx, rax
    lea  rdx, [rel u16_dash]
    call [rax + 8]
    add  rsp, 32
    pop  rbp
    ret

; ----------------------------------------------------------------------
; pause_units(RCX=unidades)
; Convierte unidades ITU a ms (unidades * UNIT_MS) y llama delay_ms.
; ----------------------------------------------------------------------
pause_units:
    push rbp
    mov  rbp, rsp
    sub  rsp, 32
    imul ecx, ecx, UNIT_MS        ; ECX = unidades * UNIT_MS
    call delay_ms
    add  rsp, 32
    pop  rbp
    ret

; ----------------------------------------------------------------------
; pit_set_freq(RCX=freq_hz)
; Programa PIT (canal 2, modo 3) con divisor = 1193182 / freq.
; EAX=divisor (cociente), EDX=resto (no usado).
; ----------------------------------------------------------------------
pit_set_freq:
    mov   eax, 1193182
    xor   edx, edx
    div   ecx                     ; EAX = divisor
    mov   al, 0b10110110          ; canal2, lobyte/hibyte, modo3, binario
    out   0x43, al
    mov   edx, eax                ; usar DL/DH como low/high
    mov   al, dl
    out   0x42, al                ; low byte
    mov   al, dh
    out   0x42, al                ; high byte
    ret

; ----------------------------------------------------------------------
; speaker_on/off
; Puerto 0x61: bit0=SPK data, bit1=gate hacia PIT ch2.
; ----------------------------------------------------------------------
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

; ----------------------------------------------------------------------
; delay_ms(RCX=millis)
; Espera aproximada por bucle (calibrar constante según QEMU/PC).
; ----------------------------------------------------------------------
delay_ms:
    mov   r8, rcx                 ; r8 = ms restantes
.outer:
    mov   ecx, 350000             ; ← ajusta: +lento (↑), +rápido (↓)
.inner:
    dec   ecx
    jnz   .inner
    dec   r8
    jnz   .outer
    ret

; ======================= Datos (tablas y mensajes) =======================
section .rodata
; Letras A..Z (una etiqueta por línea)
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
ConOutPtr:  dq 0                   ; guardamos ConOut* para imprimir símbolos

; Mensajes (UTF-16 terminado en 0)
title_msg:  dw 'M','o','r','s','e',' ','D','e','m','o',' ',':',' ',0

; Cadena demo (ASCII, termina en 0)
test_ascii: db 'S','O','S',' ','1','2',0

; Símbolos para eco visual por OutputString (UTF-16)
u16_dot:    dw '.',0
u16_dash:   dw '-',0
